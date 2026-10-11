extends Node

const DB = preload("res://scripts/core/relic_db.gd")

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var db = DB.new()
	db.load_files()
	assert(db.implemented().size() == 262, "Review must cover all implemented relics (docs/57: all 262)")
	assert(db.get_relic("79").rarity == "稀有", "Global damage +20% is rare")
	assert(db.get_relic("89").rarity == "核心", "Global SP +30% is core")
	assert(db.price("79") == 14, "Default price follows resolved rarity")
	assert(db.price("89") == 20, "Default price follows resolved rarity")
	assert(db.get_relic("118").rarity == "稀有")
	assert(db.get_relic("199").rarity == "基础", "Extra shield capacity requires the shield engine")
	for r in db.implemented():
		assert(db.effect_category_names.has(r.effect_category), "Missing effect classification: " + r.id)
		assert(db.price(r.id) == maxi(1, DB.PRICE[r.rarity]), "Rarity and price drift: " + r.id)
	var rng = RandomNumberGenerator.new()
	rng.seed = 133
	for stage in range(3):
		assert(db.roll_shop(stage, [], null, rng).size() == 3)
	assert(db.roll_chest([], null, rng).size() == 3)
	var boss = db.roll_boss(1, [], null, rng)
	assert(boss.size() == 3)
	for r in boss:
		assert(r.rarity == "升华", "Ascension pool should remain viable")
	assert(db.get_relic("221").source == "event")
	assert(db.get_relic("216").rarity == "遭诅古物")
	print("RELIC_RECLASSIFICATION_OK %d reviewed; categories, prices and reward pools checked" % db.implemented().size())
	get_tree().quit()
