extends SceneTree
## Duel difficulty: Normal = player parity, Hard = the original boss numbers, the choice persists, every nation starts. Run:
##   godot --headless --path . -s res://tests/difficulty_test.gd

const Settings = preload("res://scripts/settings.gd")
const Session = preload("res://scripts/session.gd")
const WorldScript = preload("res://scripts/world.gd")
const C = preload("res://scripts/config.gd")

var failures := 0


func ok(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	Settings.persist = false
	Settings.ensure_loaded()
	ok(Settings.duel_difficulty == "normal", "default difficulty is normal")
	ok(C.DUEL_NORMAL["hp"] == C.PLAYER_HP and C.DUEL_NORMAL["heal_amount"] == C.HEAL_AMOUNT
			and C.DUEL_NORMAL["heal_cd"] == C.HEAL_COOLDOWN and is_equal_approx(C.DUEL_NORMAL["ult_damage"], C.ULT_MAX / C.ULT_PER_DAMAGE),
			"normal table matches the player (hp, heal, ult meter)")
	ok(C.DUEL_HARD["hp"] == 450.0 and C.DUEL_HARD["heal_amount"] == 80.0 and C.DUEL_HARD["heal_cd"] == 14.0
			and C.DUEL_HARD["ult_damage"] == 160.0, "hard table is the original boss (450 hp, +80 / 14s, 160 ult)")

	for el in Session.NATIONS:
		for diff in ["normal", "hard"]:
			var w = WorldScript.new(1337)
			w.duel_nation = el
			w.duel_difficulty = diff
			w.set_bot_mode("duel", "air")
			var b = w.bots[0]
			var want: float = 100.0 if diff == "normal" else 450.0
			ok(w.bots.size() == 1 and b.boss and b.nation == el and b.max_hp == want and b.hp == want,
					"%s duel (%s): starts, enemy hp %.0f" % [el, diff, b.hp])

	# persistence: a real save/reload round trip; the player's own settings file is backed up and restored
	var had := FileAccess.file_exists(Settings.SAVE_PATH)
	var backup := FileAccess.get_file_as_bytes(Settings.SAVE_PATH) if had else PackedByteArray()
	Settings.persist = true
	var keep := Settings.duel_difficulty
	Settings.duel_difficulty = "hard"
	Settings.save()
	Settings.duel_difficulty = "normal"
	Settings._loaded = false
	Settings.ensure_loaded()
	ok(Settings.duel_difficulty == "hard", "hard persists across a reload")
	Settings.duel_difficulty = "normal"
	Settings.save()
	Settings._loaded = false
	Settings.ensure_loaded()
	ok(Settings.duel_difficulty == "normal", "normal persists across a reload")
	Settings.duel_difficulty = keep
	Settings.persist = false
	if had:
		var f := FileAccess.open(Settings.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.SAVE_PATH))

	print("")
	print("ALL PASSED" if failures == 0 else "%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)
