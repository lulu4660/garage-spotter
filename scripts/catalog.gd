## Catalogue provisoire de la phase 0 : noms de jeu tirés de la base de noms
## modifiés du GDD (le nom réel n'est jamais affiché). Remplacé par la vraie
## table côté serveur en phase 1.
extends RefCounted

const CARS: Array[Dictionary] = [
	# Communes
	{"id": "clia5", "brand": "Renolt", "name": "Clia 5", "rarity": 0, "body": "compacte", "color": "9a6b4f"},
	{"id": "peujo280", "brand": "Peujo", "name": "280", "rarity": 0, "body": "compacte", "color": "c9c9c9"},
	{"id": "gulf8", "brand": "Volkswagon", "name": "Gulf 8", "rarity": 0, "body": "compacte", "color": "5c5f66"},
	{"id": "citroan_c3", "brand": "Citroan", "name": "C-Trois", "rarity": 0, "body": "citadine", "color": "d8d2c4"},
	{"id": "yariz", "brand": "Toyata", "name": "Yariz", "rarity": 0, "body": "citadine", "color": "b8312f"},
	{"id": "sandaro", "brand": "Dacio", "name": "Sandaro", "rarity": 0, "body": "suv", "color": "7d7a70"},
	{"id": "peujo3080", "brand": "Peujo", "name": "3080", "rarity": 0, "body": "suv", "color": "2b2d33"},
	{"id": "octavio", "brand": "Skado", "name": "Octavio Break", "rarity": 0, "body": "break", "color": "8a8f96"},
	{"id": "kongo", "brand": "Renolt", "name": "Kongo", "rarity": 0, "body": "monospace", "color": "e8e4dc"},
	{"id": "transiz", "brand": "Fourd", "name": "Transiz", "rarity": 0, "body": "fourgon", "color": "e0781e"},
	# Peu communes
	{"id": "gulf_gti", "brand": "Volkswagon", "name": "Gulf GTJ", "rarity": 1, "body": "compacte", "color": "d23a2c"},
	{"id": "mimi_s", "brand": "Mimi", "name": "Coopar S", "rarity": 1, "body": "citadine", "color": "2f5d3a"},
	{"id": "megana_rs", "brand": "Renolt", "name": "Megana RS", "rarity": 1, "body": "sportback", "color": "f2a516"},
	{"id": "audy_s3", "brand": "Audy", "name": "S-Trois", "rarity": 1, "body": "berline", "color": "4a4d52"},
	{"id": "transpoter", "brand": "Volkswagon", "name": "Transpoter", "rarity": 1, "body": "combi", "color": "3f6f8f"},
	{"id": "hilox", "brand": "Toyata", "name": "Hilox", "rarity": 1, "body": "pickup", "color": "b9b6ae"},
	{"id": "mx6", "brand": "Mazdo", "name": "MX-6", "rarity": 1, "body": "roadster", "color": "a3161c"},
	# Rares
	{"id": "m3_e64", "brand": "BMV", "name": "M3 E64", "rarity": 2, "body": "coupe", "color": "8f9aa3"},
	{"id": "gtx_r35", "brand": "Nisan", "name": "GT-X R35", "rarity": 2, "body": "coupe", "color": "e6e6e2"},
	{"id": "119_carrera", "brand": "Porshe", "name": "119 Carrera", "rarity": 2, "body": "coupe", "color": "d9b44a"},
	{"id": "amg_c36", "brand": "Mercedez", "name": "C-36 AMJ", "rarity": 2, "body": "berline", "color": "2b2b2e"},
	{"id": "modele_s", "brand": "Teslo", "name": "Modèle Z", "rarity": 2, "body": "fastback", "color": "a8acb2"},
	{"id": "serie4c", "brand": "BMV", "name": "Série 4 Cabrio", "rarity": 2, "body": "cabriolet", "color": "1f3a5c"},
	{"id": "defendor", "brand": "Land Rouver", "name": "Defendor", "rarity": 2, "body": "4x4", "color": "4f5a3a"},
	# Épiques
	{"id": "119_gt3rs", "brand": "Porshe", "name": "119 GT3 RS", "rarity": 3, "body": "supercar", "color": "6fbf3f"},
	{"id": "huracon", "brand": "Lamborgino", "name": "Huracon", "rarity": 3, "body": "supercar", "color": "f28c1c"},
	{"id": "r9", "brand": "Audy", "name": "R9", "rarity": 3, "body": "supercar", "color": "b9bcc0"},
	# Légendaires
	{"id": "f04", "brand": "Ferari", "name": "F04", "rarity": 4, "body": "supercar", "color": "d01f1f"},
	{"id": "carrera_tg", "brand": "Porshe", "name": "Carrera TG", "rarity": 4, "body": "roadster", "color": "a7aaad"},
	{"id": "f2", "brand": "McLaran", "name": "F2", "rarity": 4, "body": "supercar", "color": "e3c84a"},
	# Mythiques
	{"id": "zondo", "brand": "Pagany", "name": "Zondo R", "rarity": 5, "body": "supercar", "color": "3b3f44"},
	{"id": "uno1", "brand": "Konigseg", "name": "Uno:1", "rarity": 5, "body": "supercar", "color": "f4f1ea"},
]


static func get_car(id: String) -> Dictionary:
	for c in CARS:
		if c["id"] == id:
			return c
	return {}


static func by_rarity(rarity: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in CARS:
		if int(c["rarity"]) == rarity:
			out.append(c)
	return out


static func display_name(id: String) -> String:
	var c := get_car(id)
	if c.is_empty():
		return "?"
	return "%s %s" % [c["brand"], c["name"]]
