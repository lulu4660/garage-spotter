#!/usr/bin/env python3
"""Simulation de la progression longue de Garage Spotter sur une saison de 10 semaines :
prestige (réputation), arbre de compétences, mécaniciens, collections (séries),
missions du jour et succès.

S'appuie sur tools/sim/simulate_season.py (rue, voitures, joueur type, mise à neuf),
qui reste utilisable seul avec toutes ses options.

Relancer :
  python3 tools/sim/simulate_progression.py                    (rapport complet, ≈ 15-25 min)
  python3 tools/sim/simulate_progression.py --runs 4 --quick   (contrôle rapide)
  python3 tools/sim/simulate_progression.py --only base        (sections : base, profils, sensib, variantes, s2)
  python3 tools/sim/simulate_progression.py --csv out/         (séries par jour, profil type)

Bibliothèque standard uniquement. Les valeurs reprennent scripts/progression.gd et
scripts/game_state.gd ; `check_sources()` signale tout écart avec le code du jeu.

Joueur simulé (en plus de simulate_season.py) :
- prestige quand le gain ≥ 50 % de la réputation à vie (≥ 1 point s'il n'en a aucune),
  au plus tôt PRESTIGE_DELAY_H heures après le début ou le prestige précédent ;
- arbre : achète la compétence disponible la moins chère, à égalité Revenus > Atelier
  > Spot > Garage, juste après chaque prestige ;
- réclame missions et succès à chaque session ; 20 touches (1 rush) par session ;
- les mécaniciens travaillent seulement appli ouverte (game_state.tick), pas hors ligne.
"""
import argparse
import heapq
import math
import os
import random
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simulate_season as S  # noqa: E402
from simulate_season import (  # noqa: E402
    BASE_INCOME, COST_FACTOR, COST_GROWTH, MAX_LEVEL, MAX_SLOTS, START_SLOTS, TERM, NEXT_MS, POW,
    SESSION_HOURS, SESSION_SECONDS, TAPS_PER_SESSION, TAP_FRACTION, TAP_MIN, OFFLINE_LATE,
    SPOT_GAIN_MINUTES, CATALOG, COLLECTION_BONUS, PROFILES, Game, cost_for_levels, slot_cost,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DAYS = S.DAYS

# --- Valeurs du jeu (scripts/progression.gd, scripts/game_state.gd) ---------------
BRANCH_ORDER = {"revenus": 0, "atelier": 1, "spot": 2, "garage": 3}
SKILLS = [
    ("r1", "revenus", 1, {"income_mult": 1.10}),
    ("r2", "revenus", 2, {"offline_full_h": 2.0}),
    ("r3", "revenus", 4, {"income_mult": 1.25}),
    ("r4", "revenus", 6, {"rush_duration": 15.0, "rush_mult": 1.25}),
    ("r5", "revenus", 10, {"offline_max_h": 4.0}),
    ("r6", "revenus", 20, {"income_mult": 2.0}),
    ("a1", "atelier", 1, {"upgrade_cost_mult": 0.90}),
    ("a2", "atelier", 2, {"staff_slots": 1}),
    ("a3", "atelier", 4, {"upgrade_cost_mult": 0.85}),
    ("a4", "atelier", 6, {"staff_speed_mult": 2.0}),
    ("a5", "atelier", 10, {"staff_slots": 1}),
    ("a6", "atelier", 18, {"upgrade_cost_mult": 0.70}),
    ("s1", "spot", 1, {"spot_gain_mult": 1.5}),
    ("s2", "spot", 3, {"extra_restores": 1}),
    ("s3", "spot", 4, {"spot_cooldown_mult": 0.70}),
    ("s4", "spot", 7, {"extra_restores": 2}),
    ("s5", "spot", 10, {"collection_bonus": 0.01}),
    ("s6", "spot", 16, {"spot_gain_mult": 3.0}),
    ("g1", "garage", 1, {"start_slots": 1}),
    ("g2", "garage", 3, {"stage_cost_mult": 0.75}),
    ("g3", "garage", 4, {"start_coins": 50000.0}),
    ("g4", "garage", 7, {"slot_cost_mult": 0.5}),
    ("g5", "garage", 10, {"start_stage": 1}),
    ("g6", "garage", 20, {"start_stage": 1, "start_slots": 1}),
]
MULT_KEYS = {"income_mult", "upgrade_cost_mult", "stage_cost_mult", "slot_cost_mult", "spot_gain_mult",
             "spot_cooldown_mult", "rush_mult", "staff_speed_mult"}
ADD_KEYS = ["offline_full_h", "offline_max_h", "rush_duration", "extra_restores", "collection_bonus",
            "start_slots", "start_stage", "start_coins", "staff_slots", "income_bonus"]

# Séries : (id, paliers). Appartenance : voir SERIES_SHARE.
SERIES = [("fr", [2, 4, 7]), ("de", [2, 5, 10]), ("jp", [2, 3, 5]), ("it", [1, 2, 4]),
          ("util", [1, 2, 4]), ("open", [1, 2, 3]), ("exo", [1, 3, 6])]
SERIES_BONUS = [0.05, 0.10, 0.25]
# Le catalogue de la saison (600 modèles) n'a pas encore de marques : on reprend, par rareté,
# les proportions du catalogue de phase 0 (scripts/catalog.gd, 32 modèles).
# Marque (exclusives) : fr, de, jp, it, autre ; carrosserie (exclusives) : util, open, exo, autre.
SERIES_SHARE = {
    0: ({"fr": 6, "de": 1, "jp": 1}, 10, {"util": 2}, 10),
    1: ({"fr": 1, "de": 3, "jp": 2}, 7, {"util": 2, "open": 1}, 7),
    2: ({"de": 4, "jp": 1}, 7, {"open": 1}, 7),
    3: ({"de": 2, "it": 1}, 3, {"exo": 3}, 3),
    4: ({"de": 1, "it": 1}, 3, {"open": 1, "exo": 2}, 3),
    5: ({"it": 1}, 2, {"exo": 2}, 2),
}

MISSIONS = [  # (stat, objectifs, récompense)
    ("spots", [3, 5, 8], {"restores": 1}),
    ("levels", [25, 60, 150], {"minutes": 30}),
    ("taps", [100, 250, 500], {"minutes": 20}),
    ("restores", [1, 2, 3], {"restores": 1}),
    ("rushes", [2, 4, 6], {"minutes": 30}),
    ("milestones", [2, 4, 8], {"minutes": 45}),
]
ACHIEVEMENTS = [  # (id, stat, objectif, récompense)
    ("first_restore", "restores", 1, {"minutes": 10}),
    ("spots_10", "spots", 10, {"restores": 1}),
    ("spots_100", "spots", 100, {"restores": 3}),
    ("models_10", "models", 10, {"restores": 2}),
    ("models_25", "models", 25, {"restores": 5}),
    ("levels_500", "levels", 500, {"minutes": 60}),
    ("levels_5000", "levels", 5000, {"minutes": 120}),
    ("part_100", "max_part", 100, {"restores": 2}),
    ("part_200", "max_part", 200, {"restores": 5}),
    ("stage_1", "stage", 1, {"minutes": 30}),
    ("stage_3", "stage", 3, {"restores": 3}),
    ("taps_1000", "taps", 1000, {"minutes": 30}),
    ("rush_25", "rushes", 25, {"minutes": 60}),
    ("prestige_1", "prestiges", 1, {"restores": 3}),
    ("prestige_5", "prestiges", 5, {"restores": 5}),
    ("rare", "best_rarity", 2, {"restores": 2}),
    ("legend", "best_rarity", 4, {"restores": 5}),
    ("series", "best_series", 3, {"restores": 5}),
]

DEFAULT = dict(
    prestige_divisor=1.0e7,
    rep_income_bonus=0.01,
    skill_costs=None,          # dict id -> coût (None : valeurs de SKILLS)
    skill_fx=None,             # dict id -> effets (remplace ceux de SKILLS)
    staff_interval=8.0,
    staff_budget=0.3,
    staff_by_stage=[0, 1, 1, 2],
    series_bonus=SERIES_BONUS,
    mission_restores=1.0,      # facteur sur les récompenses « mises à neuf » des missions
    achievement_restores=1.0,  # idem pour les succès
    reward_minutes=1.0,        # facteur sur les récompenses en minutes
    stage_prices=None,         # [Atelier, Showroom, Hangar]
    mult_mode="mul",           # "mul" (code actuel) ou "add" (tous les bonus globaux additionnés)
    prestige=True, skills=True, staff=True, series=True, missions=True, achievements=True,
    manual_parts=True,         # False : le joueur n'achète jamais de niveaux lui-même
    prestige_delay_h=24.0,     # délai mini entre deux prestiges (heures réelles)
    prestige_ratio=0.5,        # gain ≥ ratio × réputation à vie
)


def check_sources():
    """Compare les valeurs recopiées ici avec celles du code du jeu ; renvoie la liste des écarts."""
    issues = []
    try:
        prog = open(os.path.join(ROOT, "scripts", "progression.gd"), encoding="utf-8").read()
        gs = open(os.path.join(ROOT, "scripts", "game_state.gd"), encoding="utf-8").read()
    except OSError as e:
        return [f"sources illisibles : {e}"]
    m = re.search(r"PRESTIGE_DIVISOR := ([0-9.e]+)", prog)
    if not m or float(m.group(1)) != DEFAULT["prestige_divisor"]:
        issues.append("PRESTIGE_DIVISOR")
    m = re.search(r"REP_INCOME_BONUS := ([0-9.]+)", prog)
    if not m or float(m.group(1)) != DEFAULT["rep_income_bonus"]:
        issues.append("REP_INCOME_BONUS")
    for sid, _, cost, _ in SKILLS:
        m = re.search(r'"id": "%s".*?"cost": (\d+)' % sid, prog)
        if not m or int(m.group(1)) != cost:
            issues.append(f"coût {sid}")
    m = re.search(r"STAFF_INTERVAL := ([0-9.]+)", gs)
    if not m or float(m.group(1)) != DEFAULT["staff_interval"]:
        issues.append("STAFF_INTERVAL")
    m = re.search(r"STAFF_BUDGET := ([0-9.]+)", gs)
    if not m or float(m.group(1)) != DEFAULT["staff_budget"]:
        issues.append("STAFF_BUDGET")
    return issues


def _series_table():
    rng = random.Random(4242)
    table = {}
    for r, n in enumerate(CATALOG):
        brands, nb, bodies, nbo = SERIES_SHARE[r]
        for k in range(n):
            out = []
            for shares, tot in ((brands, nb), (bodies, nbo)):
                u, acc = rng.random() * tot, 0.0
                for sid, w in shares.items():
                    acc += w
                    if u < acc:
                        out.append(sid)
                        break
            table[(r, k)] = tuple(out)
    return table


SERIES_OF = _series_table()


def _score(x):
    return x[0]


class PGame(Game):
    def __init__(self, profile, seed, cfg=None, **kw):
        self.cfg = dict(DEFAULT)
        self.cfg.update(cfg or {})
        self.mrng = random.Random(seed * 7 + 3)  # missions : hasard séparé, la rue reste appariée
        super().__init__(profile, seed, **kw)
        c = self.cfg
        self.costs = {sid: (c["skill_costs"] or {}).get(sid, cost) for sid, _, cost, _ in SKILLS}
        self.skill_fx = {sid: (c["skill_fx"] or {}).get(sid, fx) for sid, _, _, fx in SKILLS}
        self.rep = 0
        self.rep_total = 0
        self.skills = set()
        self.run_earnings = 0.0
        self.prestiges = 0
        self.now = 0.0
        self.last_prestige = 0.0
        self.lstats = {}   # compteurs à vie (succès)
        self.today = {}
        self.missions = []
        self.claimed = set()
        self.series_count = {sid: 0 for sid, _ in SERIES}
        for car in self.cars:
            if car.restored:
                self._on_restored(car, count=False)
        self._fx = None
        self._mult = None
        self.run_peak = 0.0
        self.first_point = None  # heure où le 1er point de réputation est disponible
        self.events = []       # prestiges : dict(t, gain, rep_total, before, recovered_h)
        self.pending = []      # prestiges dont le revenu d'avant n'est pas encore retrouvé
        self.skill_times = []  # (heure, id)
        self.p_levels = self.s_levels = 0
        self.p_spent = self.s_spent = 0.0
        self.s_sessions = 0    # sessions où les mécaniciens ont acheté
        self.p_buy_sessions = 0
        self.reward_tokens = 0
        self.mission_tokens = 0
        self.ach_tokens = 0
        self.reward_coins = 0.0
        self.absorbed = 0      # jetons perdus à la remise à niveau quotidienne (max)
        self.earned = 0.0
        self.src = dict(offline=0.0, spot=0.0, session=0.0, reward=0.0)

    # --- effets ---
    def fx(self):
        if self._fx is None:
            fx = {k: 1.0 for k in MULT_KEYS}
            fx.update({k: 0.0 for k in ADD_KEYS})
            if self.cfg["skills"]:
                for sid in self.skills:
                    for k, v in self.skill_fx[sid].items():
                        fx[k] = fx[k] * v if k in MULT_KEYS else fx[k] + v
            fx["income_bonus"] += self.series_bonus_total()
            self._fx = fx
        return self._fx

    def series_bonus_total(self):
        if not self.cfg["series"]:
            return 0.0
        b = 0.0
        for sid, tiers in SERIES:
            t = sum(1 for need in tiers if self.series_count[sid] >= need)
            b += sum(self.cfg["series_bonus"][:t])
        return b

    def best_series(self):
        return max(sum(1 for need in tiers if self.series_count[sid] >= need) for sid, tiers in SERIES)

    def invalidate(self):
        self._fx = None
        self._mult = None

    def mult_parts(self):
        fx = self.fx()
        coll = (COLLECTION_BONUS + fx["collection_bonus"]) * self.n_restored
        rep = self.cfg["rep_income_bonus"] * self.rep_total
        return coll, rep, fx["income_bonus"], fx["income_mult"]

    def mult(self):
        if self._mult is None:
            coll, rep, ser, im = self.mult_parts()
            if self.cfg["mult_mode"] == "add":
                self._mult = 1.0 + coll + rep + ser + (im - 1.0)
            else:
                self._mult = (1.0 + coll) * (1.0 + rep + ser) * im
        return self._mult

    def base_inc(self):
        return sum(c.income() for c in self.exhibited) * self.mult()

    income = base_inc

    def parts(self):
        return S.STAGES[self.stage][0]

    def stage_price(self):
        prices = self.cfg["stage_prices"]
        p = prices[self.stage] if prices else S.STAGES[self.stage + 1][1]
        return p * self.fx()["stage_cost_mult"]

    def staff_count(self):
        if not self.cfg["staff"]:
            return 0
        return self.cfg["staff_by_stage"][self.stage] + int(self.fx()["staff_slots"])

    # --- gains ---
    def earn(self, x, src):
        self.coins += x
        self.run_earnings += x
        self.earned += x
        self.src[src] += x

    def count(self, k, n=1):
        if n:
            self.lstats[k] = self.lstats.get(k, 0) + n
            self.today[k] = self.today.get(k, 0) + n

    def record_max(self, k, v):
        self.lstats[k] = max(self.lstats.get(k, 0), v)

    # --- quotidien ---
    def new_day(self, day=0):
        self.day = day
        q = self.quota() + int(self.fx()["extra_restores"])
        if self.token_rule == "max":
            if self.tokens < q:
                self.absorbed += self.tokens
            self.tokens = max(self.tokens, q)
        else:
            self.tokens = min(self.tokens + q, 3 * q)
        self.ads_today = 0
        self.today = {}
        self.missions = []
        if self.cfg["missions"]:
            for k in self.mrng.sample(range(len(MISSIONS)), 3):
                stat, goals, reward = MISSIONS[k]
                self.missions.append([stat, self.mrng.choice(goals), reward, False])

    # --- spot et mise à neuf ---
    def spot(self):
        rarity, model = self.street.draw()
        gain = max(self.base_inc(), TAP_MIN) * SPOT_GAIN_MINUTES[rarity] * 60.0 * self.fx()["spot_gain_mult"]
        self.earn(gain, "spot")
        self.stats["spots"] += 1
        self.count("spots")
        if (rarity, model) not in self.owned:
            self.stats["new"] += 1
            free = self.p["restore"] == "none" or rarity >= self.free_rarity
            car = self._add(rarity, model, free)
            if free:
                self._on_restored(car)

    def _on_restored(self, car, count=True):
        for sid in SERIES_OF[(car.rarity, car.model)]:
            self.series_count[sid] += 1
        if count:
            self.count("restores")
            self.record_max("best_rarity", car.rarity)
            self.invalidate()

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
            self.n_restored += 1
            self.stats["restores"] += 1
            self._on_restored(c)

    # --- récompenses ---
    def stat(self, k):
        if k == "models":
            return self.n_restored
        if k == "best_series":
            return self.best_series()
        return self.lstats.get(k, 0)

    def reward(self, rw, kind):
        c = self.cfg
        f = c["mission_restores"] if kind == "m" else c["achievement_restores"]
        n = int(round(rw.get("restores", 0) * f))
        if n:
            self.tokens += n
            self.reward_tokens += n
            if kind == "m":
                self.mission_tokens += n
            else:
                self.ach_tokens += n
        if "minutes" in rw:
            x = max(self.base_inc(), 1.0) * 60.0 * rw["minutes"] * c["reward_minutes"]
            self.reward_coins += x
            self.earn(x, "reward")

    def claim(self):
        got = False
        for m in self.missions:
            if not m[3] and self.today.get(m[0], 0) >= m[1]:
                m[3] = True
                self.reward(m[2], "m")
                got = True
        if self.cfg["achievements"]:
            for aid, st, goal, rw in ACHIEVEMENTS:
                if aid not in self.claimed and self.stat(st) >= goal:
                    self.claimed.add(aid)
                    self.reward(rw, "a")
                    got = True
        if got:
            self.do_restores()
            self.arrange()

    # --- achats du joueur (copie de Game.candidates/buy_loop avec réductions et compteurs) ---
    def candidates(self, idle_best):
        inc = max(self.base_inc(), 1e-9)
        m = self.mult()
        fx = self.fx()
        cm = fx["upgrade_cost_mult"]
        coins = self.coins
        out = []
        parts = self.parts()
        if self.cfg["manual_parts"]:
            for car in self.exhibited:
                k = car.b * 0.1 * m
                base = COST_FACTOR * car.b / (COST_GROWTH - 1.0) * cm
                for p in range(parts):
                    l = car.levels[p]
                    if l >= MAX_LEVEL:
                        continue
                    nm = NEXT_MS[l]
                    for n in ((1, nm - l) if nm > 0 and nm - l > 1 else (1,)):
                        cost = base * POW[l] * (POW[n] - 1.0)
                        d = k * (TERM[l + n] - TERM[l])
                        w = cost - coins
                        out.append((cost / d + (w / inc if w > 0 else 0.0), cost, car, p, n))
        if self.slots < MAX_SLOTS and idle_best > 0:
            cost = slot_cost(self.slots + 1) * fx["slot_cost_mult"]
            w = cost - coins
            out.append((cost / (idle_best * m) + (w / inc if w > 0 else 0.0), cost, None, "slot", 0))
        if self.stage + 1 < len(S.STAGES):
            newp = S.STAGES[self.stage + 1][0] - parts
            price = self.stage_price()
            bc, bd = price, 0.0
            for car in self.exhibited:
                bc += newp * cost_for_levels(car.b, 0, 25) * cm
                bd += newp * car.b * 0.1 * (TERM[25] - TERM[0]) * m
            if bd > 0:
                w = price - coins
                out.append((bc / bd + (w / inc if w > 0 else 0.0), price, None, "stage", 0))
        return out

    def _levels_bought(self, car, p, n, who, cost):
        before = car.levels[p]
        car.add_levels(p, n)
        self.count("levels", n)
        self.count("milestones", S.milestones_passed(before + n) - S.milestones_passed(before))
        self.record_max("max_part", before + n)
        if who == "p":
            self.p_levels += n
            self.p_spent += cost
        else:
            self.s_levels += n
            self.s_spent += cost

    def buy_loop(self):
        bought = False
        idle = self.idle()
        idle_best = max((c.income() for c in idle), default=0.0)
        cm = self.fx()["upgrade_cost_mult"]
        for _ in range(20000):
            cands = self.candidates(idle_best)
            if not cands:
                break
            top = heapq.nsmallest(2, cands, key=_score)
            score, cost, car, p, n = top[0]
            if cost > self.coins:
                break
            self.coins -= cost
            bought = True
            if car is not None:
                self._levels_bought(car, p, n, "p", cost)
                second = top[1][0] if len(top) > 1 else float("inf")
                k = car.b * 0.1 * self.mult()
                while car.levels[p] < MAX_LEVEL:
                    l = car.levels[p]
                    c = S.part_cost(car.b, l) * cm
                    if c > self.coins or c / (k * (TERM[l + 1] - TERM[l])) > second:
                        break
                    self.coins -= c
                    self._levels_bought(car, p, 1, "p", c)
            elif p == "slot":
                self.slots += 1
                self.arrange()
                idle = self.idle()
                idle_best = max((c.income() for c in idle), default=0.0)
            else:
                self.stage += 1
                self.record_max("stage", self.stage)
        return bought

    # --- mécaniciens (game_state._work_staff : la pièce la moins chère, ≤ budget × pièces) ---
    def work_staff(self, n):
        cm = self.fx()["upgrade_cost_mult"]
        parts = self.parts()
        did = False
        for _ in range(n):
            best = None
            for car in self.exhibited:
                lv = car.levels
                p = min(range(parts), key=lambda i: lv[i])
                l = lv[p]
                if l >= MAX_LEVEL:
                    continue
                price = COST_FACTOR * car.b * POW[l] * cm
                if best is None or price < best[0]:
                    best = (price, car, p)
            if best is not None and best[0] <= self.coins * self.cfg["staff_budget"]:
                self.coins -= best[0]
                self._levels_bought(best[1], best[2], 1, "s", best[0])
                did = True
        return did

    # --- prestige et arbre ---
    def prestige_gain(self):
        if self.run_earnings <= 0:
            return 0
        return int(math.floor(math.sqrt(self.run_earnings / self.cfg["prestige_divisor"])))

    def maybe_prestige(self):
        if not self.cfg["prestige"]:
            return False
        g = self.prestige_gain()
        if g >= 1 and self.first_point is None:
            self.first_point = self.now
        if g < 1 or self.now - self.last_prestige < self.cfg["prestige_delay_h"]:
            return False
        if self.rep_total > 0 and g < self.cfg["prestige_ratio"] * self.rep_total:
            return False
        before = max(self.run_peak, self.base_inc())
        self.rep += g
        self.rep_total += g
        self.prestiges += 1
        self.count("prestiges")
        self.invalidate()
        fx = self.fx()
        self.coins = fx["start_coins"]
        self.run_earnings = 0.0
        for c in self.cars:
            c.reset()
        self.stage = min(int(fx["start_stage"]), len(S.STAGES) - 1)
        self.slots = START_SLOTS + int(fx["start_slots"])
        self.exhibited = self.exhibited[:self.slots]
        ev = dict(t=self.now, gain=g, rep_total=self.rep_total, before=before, recovered_h=None,
                  coins_lost=0.0)
        self.events.append(ev)
        self.pending = [ev]  # un nouveau prestige annule le suivi du précédent
        self.last_prestige = self.now
        self.run_peak = 0.0
        self.buy_skills()
        self.arrange()
        return True

    def buy_skills(self):
        if not self.cfg["skills"]:
            return
        order = [s[0] for s in SKILLS]
        branch = {s[0]: s[1] for s in SKILLS}
        while True:
            avail = []
            for i, sid in enumerate(order):
                if sid in self.skills:
                    continue
                prev = order[i - 1] if i % 6 else None
                if prev and prev not in self.skills:
                    continue
                if self.costs[sid] <= self.rep:
                    avail.append((self.costs[sid], BRANCH_ORDER[branch[sid]], sid))
            if not avail:
                return
            cost, _, sid = min(avail)
            self.rep -= cost
            self.skills.add(sid)
            self.skill_times.append((self.now, sid))
            self.invalidate()

    # --- session ---
    def session(self, offline_s, n_spots):
        self.stats["sessions"] += 1
        fx = self.fx()
        full = S.OFFLINE_FULL + fx["offline_full_h"] * 3600.0
        most = S.OFFLINE_MAX + fx["offline_max_h"] * 3600.0
        s = min(max(offline_s, 0.0), most)
        self.earn(self.base_inc() * (min(s, full) + OFFLINE_LATE * max(0.0, s - full)), "offline")
        for _ in range(n_spots):
            self.spot()
        self.do_restores()
        self.arrange()
        self.claim()
        pl0 = self.p_levels
        bought = self.buy_loop()
        # 20 touches : gains de touche puis rush
        inc = self.base_inc()
        self.earn(TAPS_PER_SESSION * max(inc * TAP_FRACTION, TAP_MIN), "session")
        self.count("taps", TAPS_PER_SESSION)
        self.count("rushes")
        fx = self.fx()
        rmult = S.RUSH_MULT * fx["rush_mult"]
        rdur = S.RUSH_DURATION + fx["rush_duration"]
        n_staff = self.staff_count()
        if n_staff == 0:
            self.earn(inc * (SESSION_SECONDS + (rmult - 1.0) * min(rdur, SESSION_SECONDS)), "session")
        else:
            step = self.cfg["staff_interval"] / fx["staff_speed_mult"]
            t, worked = 0.0, False
            while t < SESSION_SECONDS - 1e-9:
                dt = min(step, SESSION_SECONDS - t)
                rush_part = max(0.0, min(t + dt, rdur) - t)
                self.earn(self.base_inc() * (dt + (rmult - 1.0) * rush_part), "session")
                t += dt
                if dt >= step - 1e-9:
                    worked = self.work_staff(n_staff) or worked
            if worked:
                self.s_sessions += 1
        bought = self.buy_loop() or bought
        if bought:
            self.stats["buys_sessions"] += 1
        if self.p_levels > pl0:
            self.p_buy_sessions += 1
        self.claim()
        inc = self.base_inc()
        self.run_peak = max(self.run_peak, inc)
        for ev in list(self.pending):
            if inc >= ev["before"]:
                ev["recovered_h"] = self.now - ev["t"]
                self.pending.remove(ev)
        if self.maybe_prestige():
            self.buy_loop()
            self.claim()


def run(profile_key, seed, cfg=None, days=DAYS, game=None, t0=0.0, **kw):
    p = PROFILES[profile_key]
    g = game or PGame(p, seed, cfg, **kw)
    daily = []
    last_end = None
    carry = 0.0
    record = 0.0
    for d in range(days):
        g.new_day(d)
        carry += p["spots"](d)
        n = int(carry)
        carry -= n
        per = [n // 6 + (1 if i < n % 6 else 0) for i in range(6)]
        r0, rt0, ab0 = g.stats["restores"], g.reward_tokens, g.absorbed
        new0 = g.stats["new"]
        for i, h in enumerate(SESSION_HOURS):
            t = t0 + d * 24.0 + h
            g.now = t + SESSION_SECONDS / 3600.0
            off = 0.0 if last_end is None else (t - last_end) * 3600.0
            g.session(off, per[i])
            last_end = t + SESSION_SECONDS / 3600.0
            record = max(record, g.base_inc())
        coll, rep, ser, im = g.mult_parts()
        daily.append(dict(day=d + 1, income=g.base_inc(), record=record, rep_total=g.rep_total,
                          prestiges=g.prestiges, skills=len(g.skills), locked=len(g.locked()),
                          restores=g.stats["restores"] - r0, new=g.stats["new"] - new0,
                          reward_tokens=g.reward_tokens - rt0, absorbed=g.absorbed - ab0,
                          stage=g.stage, slots=g.slots, staff=g.staff_count(), mult=g.mult(),
                          coll=coll, rep=rep, ser=ser, im=im, models=g.n_restored,
                          p_levels=g.p_levels, s_levels=g.s_levels, earned=g.earned))
    return g, daily


# --- statistiques ------------------------------------------------------------
def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def pct(xs, q):
    return S.pct(xs, q)


def fmt(x):
    if x is None:
        return "–"
    if isinstance(x, float) and math.isinf(x):
        return "∞"
    if abs(x) >= 1e6:
        e = int(math.floor(math.log10(abs(x))))
        return f"{x / 10 ** e:.2f}e{e}".replace(".", ",")
    if abs(x) >= 100:
        return f"{x:,.0f}".replace(",", " ")
    return f"{x:.1f}".replace(".", ",")


def fh(h):
    """Heure de jeu absolue → « j2 13 h »."""
    if h is None:
        return "–"
    d = int(h // 24)
    return f"j{d + 1} {h - 24 * d:.0f} h"


def doubling(i0, daily, key="record"):
    inc = {0: i0}
    for row in daily:
        inc[row["day"]] = row[key]
    out = []
    for a, b in S.PERIODS:
        ia, ib = inc[a], inc[b]
        out.append(float("inf") if ib <= ia else (b - a) * 24.0 * math.log(2) / math.log(ib / ia))
    return out


def _one(args):
    key, seed, cfg, kw = args
    g0 = PGame(PROFILES[key], seed, cfg, **kw)
    i0 = g0.base_inc()
    g, daily = run(key, seed, cfg, **kw)
    tree_full = g.skill_times[-1][0] if len(g.skills) == len(SKILLS) else None
    lv = g.p_levels + g.s_levels
    return dict(
        events=g.events, skill_times=g.skill_times, daily=daily, i0=i0, dt=doubling(i0, daily),
        first_p=g.events[0]["t"] if g.events else None, first_point=g.first_point,
        n_p=g.prestiges, rep=g.rep_total, skills=len(g.skills), tree_full=tree_full,
        rec=[ev["recovered_h"] for ev in g.events],
        staff_share=g.s_levels / lv if lv else 0.0,
        staff_spent=g.s_spent / (g.s_spent + g.p_spent) if g.p_spent + g.s_spent else 0.0,
        p_buy=g.p_buy_sessions / g.stats["sessions"], buy=g.stats["buys_sessions"] / g.stats["sessions"],
        m_tok=g.mission_tokens, a_tok=g.ach_tokens, restores=g.stats["restores"],
        absorbed=g.absorbed, reward_coins=g.reward_coins, earned=g.earned, src=dict(g.src),
        gray_peak=max(x["locked"] for x in daily), ads=g.stats["ads"],
        end=daily[-1]["record"], end_now=daily[-1]["income"],
    )


POOL = None


def pmap(fn, items):
    return POOL.map(fn, items) if POOL else list(map(fn, items))


def collect(key, runs, cfg=None, **kw):
    """Lance `runs` parties (en parallèle) et rassemble les indicateurs."""
    return pmap(_one, [(key, 1000 + r, cfg, kw) for r in range(runs)])


def skill_day(res, n):
    """Jour médian où la n-ième compétence est achetée."""
    out = []
    for x in res:
        st = x["skill_times"]
        out.append(st[n - 1][0] / 24.0 + 1 if len(st) >= n else None)
    return out


def series_med(res, d, k):
    return statistics.median(x["daily"][d - 1][k] for x in res)


DAYS_SHOWN = (1, 2, 3, 5, 7, 10, 14, 21, 28, 35, 49, 63, 70)


# --- sections du rapport ----------------------------------------------------
def section_base(runs):
    print("## A. Joueur type (gratuit), règles actuelles\n")
    base = collect("gratuit", runs)
    nosys = collect("gratuit", runs, dict(prestige=False, skills=False, staff=False, series=False,
                                          missions=False, achievements=False))
    nop = collect("gratuit", runs, dict(prestige=False))
    fp = [x["first_p"] for x in base]
    print("| Indicateur | Médiane | P10 – P90 |")
    print("|---|---|---|")

    def row(name, xs, f=fmt):
        xs2 = [x for x in xs if x is not None]
        if not xs2:
            print(f"| {name} | – | – |")
            return
        print(f"| {name} | {f(med(xs2))} | {f(pct(xs2, 0.1))} – {f(pct(xs2, 0.9))} |")
    row("1er point de réputation disponible (heure de jeu)", [x["first_point"] for x in base], fh)
    row("1er prestige (heure de jeu)", fp, fh)
    row("Prestiges sur 70 j", [x["n_p"] for x in base])
    row("Réputation à vie, j70", [x["rep"] for x in base])
    row("Compétences achetées (sur 24)", [x["skills"] for x in base])
    row("Jour de la 12e compétence", skill_day(base, 12))
    row("Arbre complet (heure de jeu)", [x["tree_full"] for x in base], fh)
    print(f"\nArbre complet dans {sum(1 for x in base if x['tree_full'] is not None)}/{runs} parties.\n")

    print("### Chronologie des prestiges (médiane des parties qui l'atteignent)\n")
    print("| Prestige | Parties | Heure de jeu | Points gagnés | Réputation à vie | Revenu avant (/s) | Rattrapage (h réelles) | Rattrapé avant le suivant |")
    print("|---|---|---|---|---|---|---|---|")
    maxp = max(x["n_p"] for x in base)
    for k in range(min(maxp, 12)):
        evs = [x["events"][k] for x in base if len(x["events"]) > k]
        recs = [e["recovered_h"] for e in evs]
        ok = sum(1 for r in recs if r is not None)
        print(f"| {k + 1} | {len(evs)} | {fh(med([e['t'] for e in evs]))} | {fmt(med([e['gain'] for e in evs]))} "
              f"| {fmt(med([e['rep_total'] for e in evs]))} | {fmt(med([e['before'] for e in evs]))} "
              f"| {fmt(med(recs)) if ok else '–'} | {ok}/{len(evs)} |")

    print("\n### Revenu record (/s, fin de journée) : avec tout / sans prestige / sans aucun nouveau système\n")
    print("| Jour | Tout (règles actuelles) | Sans prestige | Sans nouveaux systèmes | Tout ÷ sans systèmes | Réputation | Compétences | Multiplicateur global | dont collection | réputation + séries | arbre (×) |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for d in DAYS_SHOWN:
        a = series_med(base, d, "record")
        b = series_med(nop, d, "record")
        c = series_med(nosys, d, "record")
        ratio = statistics.median(x["daily"][d - 1]["record"] / y["daily"][d - 1]["record"] for x, y in zip(base, nosys))
        print(f"| {d} | {fmt(a)} | {fmt(b)} | {fmt(c)} | {ratio:.2f} | {series_med(base, d, 'rep_total'):.0f} "
              f"| {series_med(base, d, 'skills'):.0f} | ×{series_med(base, d, 'mult'):.2f} | +{series_med(base, d, 'coll') * 100:.0f} % "
              f"| +{(series_med(base, d, 'rep') + series_med(base, d, 'ser')) * 100:.0f} % (séries +{series_med(base, d, 'ser') * 100:.0f} %) | ×{series_med(base, d, 'im'):.2f} |")

    print("\n### Doublement du revenu record, sessions avec achat\n")
    print("| Variante | j0-3 | j3-14 | j14-49 | j49-70 | Sessions avec achat (joueur) | Sessions avec achat (joueur ou mécano) |")
    print("|---|---|---|---|---|---|---|")
    for name, rs in (("Tout", base), ("Sans prestige", nop), ("Sans nouveaux systèmes", nosys)):
        dt = " | ".join(f"{med([x['dt'][i] for x in rs]):.0f} h" for i in range(4))
        print(f"| {name} | {dt} | {statistics.mean(x['p_buy'] for x in rs) * 100:.0f} % | "
              f"{statistics.mean(x['buy'] for x in rs) * 100:.0f} % |")

    print("\n### Mécaniciens et récompenses\n")
    print(f"- Part des niveaux achetés par les mécaniciens : {statistics.mean(x['staff_share'] for x in base) * 100:.0f} % "
          f"(part des pièces dépensées : {statistics.mean(x['staff_spent'] for x in base) * 100:.1f} %).")
    print(f"- Mises à neuf gagnées en missions : {statistics.mean(x['m_tok'] for x in base) / DAYS:.2f}/j ; "
          f"en succès : {statistics.mean(x['a_tok'] for x in base):.0f} sur la saison.")
    print(f"- Mises à neuf faites : {statistics.mean(x['restores'] for x in base) / DAYS:.2f}/j ; jetons perdus au changement de jour : "
          f"{statistics.mean(x['absorbed'] for x in base) / DAYS:.2f}/j.")
    src = {k: statistics.mean(x["src"][k] / x["earned"] for x in base) for k in base[0]["src"]}
    print("- Origine des gains : " + ", ".join(f"{k} {v * 100:.1f} %" for k, v in src.items()) + ".")
    return base, nosys, nop


def section_staff_rewards(runs, base):
    print("\n## B. Mécaniciens : le jeu se joue-t-il seul ?\n")
    auto = collect("gratuit", runs, dict(manual_parts=False))
    nostaff = collect("gratuit", runs, dict(staff=False))
    print("| Variante | Revenu record j7 | j14 | j28 | j70 | ÷ joueur actif (j70) | Part des niveaux par mécano | Sessions avec achat du joueur |")
    print("|---|---|---|---|---|---|---|---|")
    for name, rs in (("Joueur actif + mécaniciens (actuel)", base), ("Joueur actif, sans mécaniciens", nostaff),
                     ("Mécaniciens seuls (le joueur n'achète aucun niveau)", auto)):
        cells = " | ".join(fmt(series_med(rs, d, "record")) for d in (7, 14, 28, 70))
        ratio = statistics.median(x["end"] / y["end"] for x, y in zip(rs, base))
        print(f"| {name} | {cells} | {ratio:.2f} | {statistics.mean(x['staff_share'] for x in rs) * 100:.0f} % "
              f"| {statistics.mean(x['p_buy'] for x in rs) * 100:.0f} % |")
    print("\nMécaniciens au fil de la saison (joueur type, médiane) :\n")
    print("| Jour | Mécaniciens | Niveaux cumulés joueur | Niveaux cumulés mécano | Part mécano (cumul) |")
    print("|---|---|---|---|---|")
    for d in (1, 3, 7, 14, 28, 49, 70):
        p = series_med(base, d, "p_levels")
        s = series_med(base, d, "s_levels")
        print(f"| {d} | {series_med(base, d, 'staff'):.0f} | {p:.0f} | {s:.0f} | {s / (p + s) * 100 if p + s else 0:.0f} % |")

    print("\n## C. Missions et succès : impact sur la mise à neuf\n")
    norew = dict(mission_restores=0.0, achievement_restores=0.0)
    rows = []
    for key in ("gratuit", "rural", "gros_spotteur"):
        a = base if key == "gratuit" else collect(key, runs)
        b = collect(key, runs, norew)
        rows.append((key, a, b))
    print("| Profil | Mises à neuf/j (quota 5 + arbre) | gagnées en missions/j | succès (saison) | jetons perdus au changement de jour/j | Grises max (avec / sans récompenses) | Revenu j14 avec ÷ sans | j70 avec ÷ sans |")
    print("|---|---|---|---|---|---|---|---|")
    for key, a, b in rows:
        r14 = statistics.median(x["daily"][13]["record"] / y["daily"][13]["record"] for x, y in zip(a, b))
        r70 = statistics.median(x["end"] / y["end"] for x, y in zip(a, b))
        print(f"| {PROFILES[key]['label']} | {statistics.mean(x['restores'] for x in a) / DAYS:.2f} "
              f"| {statistics.mean(x['m_tok'] for x in a) / DAYS:.2f} | {statistics.mean(x['a_tok'] for x in a):.0f} "
              f"| {statistics.mean(x['absorbed'] for x in a) / DAYS:.2f} "
              f"| {med([x['gray_peak'] for x in a]):.0f} / {med([x['gray_peak'] for x in b]):.0f} | {r14:.2f} | {r70:.2f} |")
    gros = rows[2][1]
    print("\nGros spotteur, par jour (médiane) : nouveaux modèles / mises à neuf / jetons de récompense / grises en attente\n")
    print("| Jour | Valeurs |")
    print("|---|---|")
    for d in (1, 2, 3, 5, 7, 10, 14, 21, 28, 49, 70):
        print(f"| {d} | {series_med(gros, d, 'new'):.0f} / {series_med(gros, d, 'restores'):.0f} / "
              f"{series_med(gros, d, 'reward_tokens'):.0f} / {series_med(gros, d, 'locked'):.0f} |")


def profile_table(runs, cfg=None, title="", keys=("gratuit", "pubs", "rural", "gros_spotteur", "gros_spotteur_pubs", "ancien")):
    if title:
        print(title)
    print("| Profil | 1er prestige | Prestiges | Réputation j70 | Compétences | Doublement j0-3 | j3-14 | j14-49 | j49-70 | Sessions avec achat (joueur) | Revenu record j70 | P10 – P90 | ÷ gratuit | Grises max |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    out = {}
    for k in keys:
        out[k] = collect(k, runs, cfg)
    ref = med([x["end"] for x in out["gratuit"]]) if "gratuit" in out else None
    for k, rs in out.items():
        ends = [x["end"] for x in rs]
        dt = " | ".join(f"{med([x['dt'][i] for x in rs]):.0f} h" for i in range(4))
        lab = PROFILES[k]["label"] if k != "ancien" else "Payeur (mises à neuf illimitées)"
        print(f"| {lab} | {fh(med([x['first_p'] for x in rs]))} | {med([x['n_p'] for x in rs]):.0f} | {med([x['rep'] for x in rs]):.0f} "
              f"| {med([x['skills'] for x in rs]):.0f} | {dt} | {statistics.mean(x['p_buy'] for x in rs) * 100:.0f} % "
              f"| {fmt(med(ends))} | {fmt(pct(ends, 0.1))} – {fmt(pct(ends, 0.9))} | {med(ends) / ref:.2f} | {med([x['gray_peak'] for x in rs]):.0f} |")
    return out


def summary_row(name, rs, ref_rs=None):
    ends = [x["end"] for x in rs]
    dt = " | ".join(f"{med([x['dt'][i] for x in rs]):.0f} h" for i in range(4))
    rec1 = med([x["rec"][0] for x in rs if x["rec"]])
    tree = [x["tree_full"] for x in rs]
    ntree = sum(1 for t in tree if t is not None)
    ratio = f"{statistics.median(x['end'] / y['end'] for x, y in zip(rs, ref_rs)):.2f}" if ref_rs else "–"
    print(f"| {name} | {fh(med([x['first_p'] for x in rs]))} | {med([x['n_p'] for x in rs]):.0f} | {med([x['rep'] for x in rs]):.0f} "
          f"| {med([x['skills'] for x in rs]):.0f} | {fh(med(tree)) if ntree * 2 > len(rs) else f'{ntree}/{len(rs)}'} "
          f"| {fmt(rec1)} | {dt} | {statistics.mean(x['staff_share'] for x in rs) * 100:.0f} % "
          f"| {statistics.mean(x['p_buy'] for x in rs) * 100:.0f} % | {fmt(med(ends))} | {ratio} |")


SUMMARY_HEAD = ("| Variante | 1er prestige | Prestiges | Réputation j70 | Compétences | Arbre complet | Rattrapage 1er prestige (h) "
                "| Doubl. j0-3 | j3-14 | j14-49 | j49-70 | Part mécano | Sessions avec achat | Revenu record j70 | ÷ sans systèmes |\n"
                "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")


def section_sensitivity(runs, nosys):
    print("\n## D. Sensibilité de la règle de prestige du joueur\n")
    print(SUMMARY_HEAD)
    for name, cfg in (("Délai 24 h, ratio 50 % (référence)", {}),
                      ("Délai 6 h", dict(prestige_delay_h=6.0)),
                      ("Délai 72 h", dict(prestige_delay_h=72.0)),
                      ("Ratio 100 % (prestiges plus rares)", dict(prestige_ratio=1.0)),
                      ("Ratio 25 % (prestiges fréquents)", dict(prestige_ratio=0.25))):
        summary_row(name, collect("gratuit", runs, cfg), nosys)


PROPOSAL = dict(
    prestige_divisor=1.0e9,
    rep_income_bonus=0.02,
    skill_costs={"r1": 1, "r2": 2, "r3": 4, "r4": 8, "r5": 12, "r6": 30,
                 "a1": 1, "a2": 3, "a3": 5, "a4": 8, "a5": 14, "a6": 25,
                 "s1": 2, "s2": 3, "s3": 5, "s4": 8, "s5": 15, "s6": 25,
                 "g1": 1, "g2": 3, "g3": 5, "g4": 8, "g5": 14, "g6": 30},
    skill_fx={"r6": {"income_mult": 1.5}, "s6": {"spot_gain_mult": 2.0}},
    staff_interval=15.0, staff_budget=0.10,
    series_bonus=[0.02, 0.04, 0.08],
    mission_restores=0.0, achievement_restores=0.4,
    mult_mode="add",
    stage_prices=[1.0e5, 1.0e8, 1.0e10],
)


def section_variants(runs, nosys):
    print("\n## E. Variantes de réglage (joueur type)\n")
    print(SUMMARY_HEAD)
    P = PROPOSAL
    variants = [
        ("Actuel", {}),
        ("Diviseur 1e8", dict(prestige_divisor=1e8)),
        ("Diviseur 1e9", dict(prestige_divisor=1e9)),
        ("Diviseur 1e10", dict(prestige_divisor=1e10)),
        ("Bonus de réputation 0,5 %/pt", dict(rep_income_bonus=0.005)),
        ("Bonus globaux additionnés (pas de produit)", dict(mult_mode="add")),
        ("Séries +2/+4/+8 %", dict(series_bonus=[0.02, 0.04, 0.08])),
        ("Coûts de l'arbre ×2", dict(skill_costs={s[0]: 2 * s[2] for s in SKILLS})),
        ("Mécaniciens 15 s, budget 10 %", dict(staff_interval=15.0, staff_budget=0.10)),
        ("Étapes 1e5 / 1e8 / 1e10", dict(stage_prices=[1e5, 1e8, 1e10])),
        ("Diviseur 1e9 + additionnés + séries réduites", dict(prestige_divisor=1e9, mult_mode="add", series_bonus=[0.02, 0.04, 0.08])),
        ("PROPOSITION complète", P),
    ]
    out = {}
    for name, cfg in variants:
        rs = collect("gratuit", runs, cfg)
        out[name] = rs
        summary_row(name, rs, nosys)
    return out


def section_proposal(runs, nosys_by_profile):
    print("\n## F. Proposition : tous profils\n")
    out = profile_table(runs, PROPOSAL)
    print("\nRevenu record de la proposition (/s, médiane) :\n")
    print("| Jour | " + " | ".join(PROFILES[k]["label"] for k in out) + " |")
    print("|---|" + "---|" * len(out))
    for d in DAYS_SHOWN:
        print(f"| {d} | " + " | ".join(fmt(series_med(rs, d, "record")) for rs in out.values()) + " |")
    print("\nProposition, joueur type : chronologie des prestiges\n")
    rs = out["gratuit"]
    print("| Prestige | Parties | Heure de jeu | Points | Réputation à vie | Revenu avant | Rattrapage (h) |")
    print("|---|---|---|---|---|---|---|")
    for k in range(min(max(x["n_p"] for x in rs), 10)):
        evs = [x["events"][k] for x in rs if len(x["events"]) > k]
        print(f"| {k + 1} | {len(evs)} | {fh(med([e['t'] for e in evs]))} | {fmt(med([e['gain'] for e in evs]))} "
              f"| {fmt(med([e['rep_total'] for e in evs]))} | {fmt(med([e['before'] for e in evs]))} | {fmt(med([e['recovered_h'] for e in evs]))} |")
    print("\nProposition, joueur type : achat des compétences (jour médian de la n-ième)\n")
    print("| n | " + " | ".join(str(n) for n in (1, 4, 8, 12, 16, 20, 24)) + " |")
    print("|---|" + "---|" * 7)
    print("| jour | " + " | ".join(fmt(med(skill_day(rs, n))) for n in (1, 4, 8, 12, 16, 20, 24)) + " |")
    print(f"\nPart des niveaux par mécano : {statistics.mean(x['staff_share'] for x in rs) * 100:.0f} % ; "
          f"mises à neuf de récompense : {statistics.mean(x['m_tok'] + x['a_tok'] for x in rs):.0f} sur la saison.")
    return out


def _s2(args):
    """Saison 2 : niveaux, places, étape et pièces remis à zéro, collection gardée.
    keep_rep : réputation et arbre gardés (sinon remis à zéro, succès compris).
    Renvoie le nombre de jours pour retrouver le revenu record de fin de S1."""
    key, seed, cfg, keep_rep = args
    g, daily = run(key, seed, cfg)
    target = daily[-1]["record"]
    g.coins = 0.0
    g.run_earnings = 0.0
    g.stage = 0
    g.slots = START_SLOTS
    for c in g.cars:
        c.reset()
    if not keep_rep:
        g.rep = g.rep_total = 0
        g.skills = set()
        g.claimed = set()
        g.lstats = {}
    g.invalidate()
    fx = g.fx()
    g.stage = min(int(fx["start_stage"]), 3)
    g.slots = START_SLOTS + int(fx["start_slots"])
    g.coins = fx["start_coins"]
    g.exhibited = sorted([c for c in g.cars if c.restored], key=lambda c: -c.b)[:g.slots]
    g.last_prestige = DAYS * 24.0
    g.tokens = g.free_per_day
    g.street.rng = g.rng = random.Random(seed + 7777)
    _, d2 = run(key, seed, cfg, days=40, game=g, t0=DAYS * 24.0)
    return next((row["day"] for row in d2 if row["record"] >= target), float("inf"))


def season2(key, runs, cfg, keep_rep=True):
    return pmap(_s2, [(key, 1000 + r, cfg, keep_rep) for r in range(runs)])


def section_s2(runs):
    print("\n## G. Rattrapage en saison 2 (jours pour retrouver le revenu record de fin de S1)\n")
    print("| Réglage | Profil | S2 garde réputation + arbre | S2 remet réputation + arbre à zéro |")
    print("|---|---|---|---|")
    for name, cfg in (("Actuel", {}), ("Proposition", PROPOSAL)):
        for key in ("gratuit", "rural", "gros_spotteur"):
            a = season2(key, runs, cfg, True)
            b = season2(key, runs, cfg, False)
            print(f"| {name} | {PROFILES[key]['label']} | {fmt(med(a))} j | {fmt(med(b))} j |")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=12)
    ap.add_argument("--quick", action="store_true", help="moins de tirages pour les variantes")
    ap.add_argument("--only", default="", help="sections séparées par des virgules : base,profils,sensib,variantes,proposition,s2")
    ap.add_argument("--csv", default="")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 1, help="processus en parallèle")
    a = ap.parse_args()
    global POOL
    if a.jobs > 1:
        import multiprocessing
        POOL = multiprocessing.Pool(a.jobs)
    issues = check_sources()
    if issues:
        print("ATTENTION : valeurs différentes du code du jeu : " + ", ".join(issues) + "\n")
    only = set(a.only.split(",")) if a.only else {"base", "profils", "sensib", "variantes", "proposition", "s2"}
    vr = max(4, a.runs // 2) if a.quick else a.runs
    print(f"# Progression longue : saison de {DAYS} jours, {a.runs} tirages (variantes : {vr}), médianes\n")
    nosys = collect("gratuit", vr, dict(prestige=False, skills=False, staff=False, series=False,
                                        missions=False, achievements=False))
    base = None
    if "base" in only:
        base, nosys_full, _ = section_base(a.runs)
        section_staff_rewards(a.runs, base)
        if a.csv:
            os.makedirs(a.csv, exist_ok=True)
            cols = [k for k in base[0]["daily"][0] if k != "day"]
            with open(os.path.join(a.csv, "progression_gratuit.csv"), "w", encoding="utf-8") as f:
                f.write("jour," + ",".join(cols) + "\n")
                for d in range(DAYS):
                    f.write(f"{d + 1}," + ",".join(f"{series_med(base, d + 1, c):.6g}" for c in cols) + "\n")
    if "profils" in only:
        print("\n## Profils, règles actuelles\n")
        profile_table(a.runs)
    if "sensib" in only:
        section_sensitivity(vr, nosys)
    if "variantes" in only:
        section_variants(vr, nosys)
    if "proposition" in only:
        section_proposal(a.runs, None)
    if "s2" in only:
        section_s2(max(4, vr // 2))


if __name__ == "__main__":
    main()
