#!/usr/bin/env python3
"""Simulation d'une saison de 10 semaines de Garage Spotter (mise à neuf).

Relancer :  python3 tools/sim/simulate_season.py            (rapport complet)
            python3 tools/sim/simulate_season.py --runs 10  (plus rapide)
            python3 tools/sim/simulate_season.py --csv out/ (séries par jour)

Bibliothèque standard uniquement. Les règles reprennent scripts/economy.gd et
scripts/game_state.gd (Phase 0) ; si elles changent, mettre à jour la section
« Règles » ci-dessous.

Modèle du joueur type (GDD) : 6 sessions de 3 min par jour, achat le plus
rentable à chaque session, hors ligne entre les sessions, spots dont la
nouveauté décroît quand la collection se remplit (catalogue réel de 600
modèles, fréquences de rue en loi de Zipf dans chaque rareté).
"""
import argparse
import math
import os
import random
import statistics

# --- Règles (scripts/economy.gd) ----------------------------------------
BASE_INCOME = [1.0, 2.5, 6.0, 15.0, 40.0, 100.0]
SPOT_CHANCE = [0.60, 0.25, 0.10, 0.04, 0.009, 0.001]
SPOT_GAIN_MINUTES = [20.0, 30.0, 45.0, 60.0, 120.0, 240.0]
MILESTONES = [25, 50, 100, 150, 200]
MAX_LEVEL = 200
COST_GROWTH = 1.10
COST_FACTOR = 20.0
STAGES = [(3, 0.0), (6, 20000.0), (8, 2.0e6), (10, 2.0e8)]  # (pièces, prix)
START_SLOTS = 3
MAX_SLOTS = 20
COLLECTION_BONUS = 0.01
OFFLINE_FULL = 7200.0
OFFLINE_MAX = 28800.0
OFFLINE_LATE = 0.5
TAP_FRACTION = 0.05
TAP_MIN = 1.0
RUSH_TAPS = 20
RUSH_DURATION = 30.0
RUSH_MULT = 2.0

# --- Hypothèses de simulation --------------------------------------------
DAYS = 70
SESSION_HOURS = [8.0, 10.5, 13.0, 16.0, 19.0, 22.5]   # 6 sessions de 3 min
SESSION_SECONDS = 180.0
TAPS_PER_SESSION = 20          # de quoi déclencher un rush par session
CATALOG = [240, 180, 110, 50, 15, 5]   # 600 modèles réels
ZIPF_S = 1.0                   # fréquence dans la rue du k-ième modèle ∝ 1/k^s
SWAP_HORIZON = 3600.0          # échange d'une voiture exposée : budget de comparaison (1 h de revenu)
PERIODS = [(0, 3), (3, 14), (14, 49), (49, 70)]


def milestones_passed(level):
    return sum(1 for s in MILESTONES if level >= s)


def next_milestone(level):
    for s in MILESTONES:
        if level < s:
            return s
    return -1


def part_cost(b, level):
    return COST_FACTOR * b * COST_GROWTH ** level


def cost_for_levels(b, level, count):
    if count <= 0:
        return 0.0
    return part_cost(b, level) * (COST_GROWTH ** count - 1.0) / (COST_GROWTH - 1.0)


def part_term(level):
    return (1.0 + level) * 2.0 ** milestones_passed(level)


def car_income(b, levels):
    return b * 0.1 * sum(part_term(l) for l in levels)


def slot_cost(n):
    return 100.0 * 5.0 ** (n - 3)


def offline_gain(inc, seconds):
    s = min(max(seconds, 0.0), OFFLINE_MAX)
    full = min(s, OFFLINE_FULL)
    late = max(0.0, s - OFFLINE_FULL)
    return inc * (full + OFFLINE_LATE * late)


# --- Catalogue et rue ------------------------------------------------------
class Street:
    """Tirage d'un spot : rareté (SPOT_CHANCE) puis modèle selon sa fréquence (Zipf)."""

    def __init__(self, rng):
        self.rng = rng
        self.weights = [[1.0 / (k + 1) ** ZIPF_S for k in range(n)] for n in CATALOG]
        self.cum = []
        for w in self.weights:
            acc, c = 0.0, []
            for x in w:
                acc += x
                c.append(acc)
            self.cum.append(c)

    def draw(self):
        u = self.rng.random()
        acc, rarity = 0.0, 0
        for i, p in enumerate(SPOT_CHANCE):
            acc += p
            if u < acc:
                rarity = i
                break
        c = self.cum[rarity]
        x = self.rng.random() * c[-1]
        lo, hi = 0, len(c) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if c[mid] < x:
                lo = mid + 1
            else:
                hi = mid
        return rarity, lo


# --- Profils -----------------------------------------------------------------
# spots(d) : spots par jour au jour d (0-indexé)
# restore : "quota" (mise à neuf, 5/jour) ou "none" (ancien modèle : tout est utilisable)
# ads : pubs regardées quand il n'y a plus de jeton et qu'une voiture grise attend
PROFILES = {
    "gratuit": dict(label="Gratuit (5 mises à neuf/j, sans pub)", spots=lambda d: 6, restore="quota", ads=False),
    "pubs": dict(label="Pubs (5 + 5 pubs/j)", spots=lambda d: 6, restore="quota", ads=True),
    "rural": dict(label="Rural (2 spots/j)", spots=lambda d: 2, restore="quota", ads=False),
    "gros_spotteur": dict(label="Gros spotteur (14 spots/j)", spots=lambda d: 14, restore="quota", ads=False),
    "gros_spotteur_pubs": dict(label="Gros spotteur + pubs", spots=lambda d: 14, restore="quota", ads=True),
    "ancien": dict(label="Ancien modèle (sans mise à neuf)", spots=lambda d: 6, restore="none", ads=False),
    "ancien_rural": dict(label="Ancien modèle, rural", spots=lambda d: 2, restore="none", ads=False),
}


class Car:
    __slots__ = ("rarity", "model", "levels", "restored", "b")

    def __init__(self, rarity, model, restored):
        self.rarity = rarity
        self.model = model
        self.b = BASE_INCOME[rarity]
        self.levels = [0] * 10
        self.restored = restored

    def income(self):
        return car_income(self.b, self.levels)


class Game:
    def __init__(self, profile, seed, free_per_day=5, ads_per_day=5, token_rule="max",
                 gift_extra=0, gray_bonus=0.0):
        self.p = profile
        self.rng = random.Random(seed)
        self.street = Street(self.rng)
        self.free_per_day = free_per_day
        self.ads_per_day = ads_per_day
        self.token_rule = token_rule      # "max" (jeu actuel) ou "add" (cumul plafonné)
        self.gray_bonus = gray_bonus      # part du bonus collection accordée aux voitures grises
        self.coins = 0.0
        self.cars = []
        self.owned = set()
        self.exhibited = []
        self.slots = START_SLOTS
        self.stage = 0
        self.tokens = free_per_day
        self.ads_today = 0
        # Tutoriel : 2 communes + 1 peu commune, mises à neuf gratuitement.
        gifts = [(0, 0), (0, 1), (1, 0)] + [(0, 2 + i) for i in range(gift_extra)]
        for r, m in gifts:
            c = self._add(r, m, True)
            if len(self.exhibited) < self.slots:
                self.exhibited.append(c)
        self.stats = dict(restores=0, ads=0, new=0, spots=0, buys_sessions=0, sessions=0,
                          token_waste=0, spot_coins=0.0)

    # --- état ---
    def _add(self, rarity, model, restored):
        c = Car(rarity, model, restored)
        self.cars.append(c)
        self.owned.add((rarity, model))
        return c

    def unique_restored(self):
        return sum(1 for c in self.cars if c.restored)

    def mult(self):
        gray = len(self.cars) - self.unique_restored()
        return 1.0 + COLLECTION_BONUS * (self.unique_restored() + self.gray_bonus * gray)

    def income(self):
        return sum(c.income() for c in self.exhibited) * self.mult()

    def locked(self):
        return [c for c in self.cars if not c.restored]

    def parts(self):
        return STAGES[self.stage][0]

    # --- quotidien ---
    def new_day(self):
        if self.token_rule == "max":
            self.tokens = max(self.tokens, self.free_per_day)
        else:  # cumul : +quota, plafonné à 3 jours de quota
            self.tokens = min(self.tokens + self.free_per_day, 3 * self.free_per_day)
        self.ads_today = 0

    # --- spot et mise à neuf ---
    def spot(self):
        rarity, model = self.street.draw()
        gain = max(self.income(), TAP_MIN) * SPOT_GAIN_MINUTES[rarity] * 60.0
        self.coins += gain
        self.stats["spot_coins"] += gain
        self.stats["spots"] += 1
        if (rarity, model) not in self.owned:
            self.stats["new"] += 1
            self._add(rarity, model, self.p["restore"] == "none")

    def do_restores(self):
        if self.p["restore"] == "none":
            return
        waiting = sorted(self.locked(), key=lambda c: -c.rarity)
        for c in waiting:
            if self.tokens <= 0 and self.p["ads"] and self.ads_today < self.ads_per_day:
                self.ads_today += 1
                self.tokens += 1
                self.stats["ads"] += 1
            if self.tokens <= 0:
                break
            self.tokens -= 1
            c.restored = True
            self.stats["restores"] += 1

    # --- exposition ---
    def potential(self, car, budget):
        """Revenu de `car` après avoir dépensé `budget` au mieux sur elle seule."""
        levels = list(car.levels)
        parts = self.parts()
        spent = 0.0
        for _ in range(400):
            best = None
            for p in range(parts):
                l = levels[p]
                if l >= MAX_LEVEL:
                    continue
                for n in (1, (next_milestone(l) - l) if next_milestone(l) > 0 else 1):
                    cost = cost_for_levels(car.b, l, n)
                    if spent + cost > budget:
                        continue
                    d = part_term(l + n) - part_term(l)
                    r = cost / d
                    if best is None or r < best[0]:
                        best = (r, p, n, cost)
            if best is None:
                break
            _, p, n, cost = best
            levels[p] += n
            spent += cost
        return car_income(car.b, levels)

    def arrange(self):
        """Expose les voitures mises à neuf : places libres puis échanges rentables."""
        idle = [c for c in self.cars if c.restored and c not in self.exhibited]
        idle.sort(key=lambda c: -c.income())
        for c in list(idle):
            if len(self.exhibited) < self.slots:
                self.exhibited.append(c)
                idle.remove(c)
        if not idle:
            return
        budget = max(self.income(), 1.0) * SWAP_HORIZON
        for c in sorted(idle, key=lambda c: -c.b):
            worst = min(self.exhibited, key=lambda e: e.income())
            if c.b <= worst.b:
                continue
            if self.potential(c, budget) > self.potential(worst, budget):
                self.exhibited.remove(worst)
                self.exhibited.append(c)

    # --- achats ---
    def candidates(self):
        inc = max(self.income(), 1e-9)
        m = self.mult()
        out = []
        parts = self.parts()
        for car in self.exhibited:
            for p in range(parts):
                l = car.levels[p]
                if l >= MAX_LEVEL:
                    continue
                nm = next_milestone(l)
                opts = {1}
                if nm > 0:
                    opts.add(nm - l)
                for n in opts:
                    cost = cost_for_levels(car.b, l, n)
                    d = car.b * 0.1 * (part_term(l + n) - part_term(l)) * m
                    out.append((cost / d + max(0.0, cost - self.coins) / inc, cost, ("part", car, p, n)))
        # place : seulement s'il y a une voiture mise à neuf qui attend
        if self.slots < MAX_SLOTS:
            idle = [c for c in self.cars if c.restored and c not in self.exhibited]
            if idle:
                best = max(c.income() for c in idle) * m
                cost = slot_cost(self.slots + 1)
                out.append((cost / best + max(0.0, cost - self.coins) / inc, cost, ("slot",)))
        # étape : on l'évalue avec la montée des nouvelles pièces jusqu'au palier 25
        if self.stage + 1 < len(STAGES):
            newp = STAGES[self.stage + 1][0] - parts
            price = STAGES[self.stage + 1][1]
            bc, bd = price, 0.0
            for car in self.exhibited:
                bc += newp * cost_for_levels(car.b, 0, 25)
                bd += newp * car.b * 0.1 * (part_term(25) - part_term(0)) * m
            if bd > 0:
                out.append((bc / bd + max(0.0, price - self.coins) / inc, price, ("stage",)))
        return out

    def buy_loop(self):
        bought = False
        for _ in range(5000):
            cands = self.candidates()
            if not cands:
                break
            cands.sort(key=lambda x: x[0])
            score, cost, act = cands[0]
            if cost > self.coins:
                break
            self.coins -= cost
            bought = True
            if act[0] == "part":
                _, car, p, n = act
                car.levels[p] += n
                # achats en rafale sur la même pièce tant qu'elle reste la meilleure
                second = cands[1][0] if len(cands) > 1 else float("inf")
                inc = max(self.income(), 1e-9)
                m = self.mult()
                while n == 1 and car.levels[p] < MAX_LEVEL:
                    l = car.levels[p]
                    c = part_cost(car.b, l)
                    d = car.b * 0.1 * (part_term(l + 1) - part_term(l)) * m
                    if c > self.coins or c / d > second:
                        break
                    self.coins -= c
                    car.levels[p] += 1
            elif act[0] == "slot":
                self.slots += 1
                self.arrange()
            else:
                self.stage += 1
        return bought

    # --- session ---
    def session(self, offline_s, n_spots):
        self.stats["sessions"] += 1
        self.coins += offline_gain(self.income(), offline_s)
        for _ in range(n_spots):
            self.spot()
        self.do_restores()
        self.arrange()
        bought = self.buy_loop()
        inc = self.income()
        taps = TAPS_PER_SESSION * max(inc * TAP_FRACTION, TAP_MIN)
        self.coins += inc * (SESSION_SECONDS + (RUSH_MULT - 1.0) * RUSH_DURATION) + taps
        bought = self.buy_loop() or bought
        if bought:
            self.stats["buys_sessions"] += 1


def run(profile_key, seed, days=DAYS, game=None, **kw):
    p = PROFILES[profile_key]
    g = game or Game(p, seed, **kw)
    daily = []
    last_end = None  # heure absolue (h) de fin de la dernière session
    for d in range(days):
        g.new_day()
        g.stats["token_waste_day"] = 0
        n = p["spots"](d)
        per = [n // 6 + (1 if i < n % 6 else 0) for i in range(6)]
        tokens_start = g.tokens
        new_before = g.stats["new"]
        restores_before = g.stats["restores"]
        for i, h in enumerate(SESSION_HOURS):
            t = d * 24.0 + h
            off = 0.0 if last_end is None else (t - last_end) * 3600.0
            g.session(off, per[i])
            last_end = t + SESSION_SECONDS / 3600.0
        used = g.stats["restores"] - restores_before
        daily.append(dict(day=d + 1, income=g.income(), locked=len(g.locked()),
                          models=len(g.cars), restored=g.unique_restored(), new=g.stats["new"] - new_before,
                          restores=used, tokens_left=g.tokens, slots=g.slots, stage=g.stage,
                          unused_quota=max(0, min(tokens_start, g.free_per_day) - used)))
    return g, daily


def doubling_times(i0, daily):
    inc = {0: i0}
    for row in daily:
        inc[row["day"]] = row["income"]
    out = []
    for a, b in PERIODS:
        ia, ib = inc[a], inc[b]
        out.append(float("inf") if ib <= ia else (b - a) * 24.0 * math.log(2) / math.log(ib / ia))
    return out


def season2(profile_key, seed, target, **kw):
    """Saison 2 : niveaux, pièces, places, étape et pièces d'or remis à zéro ;
    la collection (voitures, mises à neuf ou grises) est conservée.
    Renvoie le nombre de jours pour retrouver `target` (revenu de fin de S1)."""
    g, _ = run(profile_key, seed, **kw)
    g.coins = 0.0
    g.slots = START_SLOTS
    g.stage = 0
    for c in g.cars:
        c.levels = [0] * 10
    g.exhibited = sorted([c for c in g.cars if c.restored], key=lambda c: -c.b)[:START_SLOTS]
    g.tokens = g.free_per_day
    _, daily = run(profile_key, seed + 7777, days=30, game=g)
    for row in daily:
        if row["income"] >= target:
            return row["day"]
    return float("inf")


def fmt(x):
    if x == float("inf"):
        return "∞"
    if x >= 1e6:
        e = int(math.floor(math.log10(x)))
        return f"{x / 10 ** e:.2f}e{e}"
    if x >= 100:
        return f"{x:,.0f}".replace(",", " ")
    return f"{x:.1f}"


def pct(xs, q):
    xs = sorted(xs)
    k = (len(xs) - 1) * q
    lo = int(math.floor(k))
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def summarize(key, runs, s2=True, **kw):
    ends, dts, buy_share, ads, gray_peak, gray_end = [], [], [], [], [], []
    series = None
    rows_all = []
    for r in range(runs):
        seed = 1000 + r
        g0 = Game(PROFILES[key], seed, **kw)
        i0 = g0.income()
        g, daily = run(key, seed, **kw)
        rows_all.append(daily)
        ends.append(daily[-1]["income"])
        dts.append(doubling_times(i0, daily))
        buy_share.append(g.stats["buys_sessions"] / g.stats["sessions"])
        ads.append(g.stats["ads"] / DAYS)
        gray_peak.append(max(row["locked"] for row in daily))
        gray_end.append(daily[-1]["locked"])
    # moyenne par jour des séries
    series = []
    for d in range(DAYS):
        series.append({k: statistics.median(rs[d][k] for rs in rows_all)
                       for k in ("income", "locked", "models", "restored", "new", "restores", "unused_quota", "slots", "stage", "tokens_left")})
    res = dict(
        key=key, label=PROFILES[key]["label"],
        end_med=statistics.median(ends), end_p10=pct(ends, 0.1), end_p90=pct(ends, 0.9),
        dt=[statistics.median(d[i] for d in dts) for i in range(len(PERIODS))],
        buy=statistics.mean(buy_share), ads=statistics.mean(ads),
        gray_peak=statistics.median(gray_peak), gray_end=statistics.median(gray_end),
        series=series,
    )
    if s2:
        s2days = [season2(key, 1000 + r, ends[r], **kw) for r in range(min(runs, 8))]
        res["s2"] = statistics.median(s2days)
    return res


def print_profile_table(results, ref_end):
    print("| Profil | Doublement j0-3 | j3-14 | j14-49 | j49-70 | Sessions avec achat | Revenu fin (médiane) | P10 – P90 | vs gratuit | Pubs/j | Gris max | Gris j70 | Rattrapage S2 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in results:
        dt = " | ".join(f"{x:.1f} h" if x != float("inf") else "∞" for x in r["dt"])
        print(f"| {r['label']} | {dt} | {r['buy'] * 100:.0f} % | {fmt(r['end_med'])}/s | {fmt(r['end_p10'])} – {fmt(r['end_p90'])} "
              f"| {r['end_med'] / ref_end:.2f} | {r['ads']:.1f} | {r['gray_peak']:.0f} | {r['gray_end']:.0f} | {r.get('s2', float('nan')):.0f} j |")


def print_series(results, days=(1, 2, 3, 5, 7, 10, 14, 21, 28, 35, 49, 63, 70)):
    print("\nVoitures grises en attente (médiane, fin de journée) :\n")
    print("| Jour | " + " | ".join(r["label"] for r in results) + " |")
    print("|---|" + "---|" * len(results))
    for d in days:
        print(f"| {d} | " + " | ".join(f"{r['series'][d - 1]['locked']:.0f}" for r in results) + " |")
    print("\nNouveaux modèles / mises à neuf / quota gratuit perdu par jour (médiane) :\n")
    print("| Jour | " + " | ".join(r["label"] for r in results) + " |")
    print("|---|" + "---|" * len(results))
    for d in days:
        cells = []
        for r in results:
            s = r["series"][d - 1]
            cells.append(f"{s['new']:.0f} / {s['restores']:.0f} / {s['unused_quota']:.0f}")
        print(f"| {d} | " + " | ".join(cells) + " |")
    print("\nRevenu par seconde (médiane, fin de journée) :\n")
    print("| Jour | " + " | ".join(r["label"] for r in results) + " |")
    print("|---|" + "---|" * len(results))
    for d in days:
        print(f"| {d} | " + " | ".join(fmt(r["series"][d - 1]["income"]) for r in results) + " |")
    print("\nCollection (modèles possédés / mis à neuf), places, étape au jour 7, 14, 70 :\n")
    print("| Profil | j7 | j14 | j70 |")
    print("|---|---|---|---|")
    for r in results:
        cells = []
        for d in (7, 14, 70):
            s = r["series"][d - 1]
            cells.append(f"{s['models']:.0f}/{s['restored']:.0f}, {s['slots']:.0f} pl., ét. {s['stage']:.0f}")
        print(f"| {r['label']} | " + " | ".join(cells) + " |")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=30)
    ap.add_argument("--csv", default="")
    ap.add_argument("--no-variants", action="store_true")
    a = ap.parse_args()

    print(f"# Saison de {DAYS} jours, {a.runs} tirages par profil (médianes)\n")
    print("## Règles actuelles\n")
    keys = ["gratuit", "pubs", "rural", "gros_spotteur", "gros_spotteur_pubs", "ancien", "ancien_rural"]
    results = [summarize(k, a.runs) for k in keys]
    ref = results[0]["end_med"]
    print_profile_table(results, ref)
    print_series(results)

    if a.csv:
        os.makedirs(a.csv, exist_ok=True)
        for r in results:
            with open(os.path.join(a.csv, f"{r['key']}.csv"), "w", encoding="utf-8") as f:
                cols = list(r["series"][0].keys())
                f.write("jour," + ",".join(cols) + "\n")
                for d, s in enumerate(r["series"]):
                    f.write(f"{d + 1}," + ",".join(f"{s[c]:.6g}" for c in cols) + "\n")

    if a.no_variants:
        return
    print("\n## Variantes de réglage (gros spotteur sans pub, puis gratuit)\n")
    variants = [
        ("Actuel : 5/j, jetons = max(jetons, 5)", {}),
        ("A : 5/j + jetons cumulables (plafond 15)", dict(token_rule="add")),
        ("B : 8/j, max", dict(free_per_day=8)),
        ("C : grises = 0,5 % de bonus collection", dict(gray_bonus=0.5)),
        ("A + C", dict(token_rule="add", gray_bonus=0.5)),
        ("D : 3/j, max (plus serré)", dict(free_per_day=3)),
    ]
    print("| Variante | Profil | Revenu fin | vs ancien modèle | Gris max | Gris j70 | Doublement j3-14 | Sessions avec achat |")
    print("|---|---|---|---|---|---|---|---|")
    anc = results[5]["end_med"]
    for name, kw in variants:
        for key in ("gros_spotteur", "gratuit"):
            r = summarize(key, max(8, a.runs // 2), s2=False, **kw)
            print(f"| {name} | {r['label']} | {fmt(r['end_med'])}/s | {r['end_med'] / anc:.2f} | {r['gray_peak']:.0f} | {r['gray_end']:.0f} "
                  f"| {r['dt'][1]:.1f} h | {r['buy'] * 100:.0f} % |")


if __name__ == "__main__":
    main()
