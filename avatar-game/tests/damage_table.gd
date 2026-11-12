extends SceneTree
## Prints every move's damage from the numbers in config.gd: damage per use, uses per second, damage per second if you
## spam it, and how many seconds it takes to kill a 100 hp target with it. Run (headless):
##   godot --headless --path . -s res://tests/damage_table.gd

const C = preload("res://scripts/config.gd")


func _init() -> void:
	var rows: Array = []
	# [nation, move, damage per use, seconds between uses, note]
	rows.append(["air", "air punch", C.PUNCH_DAMAGE, C.PUNCH_COOLDOWN, "chi-limited"])
	rows.append(["air", "air blast (charged)", C.BLAST_DAMAGE_FULL, 1.2, "needs a charge"])
	rows.append(["air", "air slice", C.SLICE_DAMAGE, C.SLICE_COOLDOWN, "pierces"])
	rows.append(["air", "breath (ult, per s)", C.BREATH_DAMAGE_PER_SEC, 1.0, "ult, a few seconds"])
	rows.append(["air", "air bomb (ult)", C.BOMB_DAMAGE, 5.0, "ult"])
	rows.append(["earth", "rock throw", C.ROCK_DAMAGE + C.ROCK_SPLASH_DAMAGE * 0.5, C.ROCK_COOLDOWN, "with half the splash"])
	rows.append(["earth", "earth wave (charged)", C.WAVE_DAMAGE_FULL, 1.5, "needs a charge"])
	rows.append(["earth", "boulder", C.BOULDER_DAMAGE, C.BOULDER_COOLDOWN, "splash on top"])
	rows.append(["earth", "pillar", C.PILLAR_BOT_DAMAGE, C.PILLAR_RECHARGE / float(C.PILLAR_CHARGES), "2 charges, each back after 7 s"])
	rows.append(["earth", "thrown wall", C.SLAB_DAMAGE, 6.0, "single, splash on top"])
	rows.append(["earth", "earth clap (ult)", C.CLAP_DAMAGE, 5.0, "ult"])
	rows.append(["water", "water whip", C.WHIP_DAMAGE, C.WHIP_COOLDOWN, ""])
	rows.append(["water", "water bullets (hold)", C.BULLET_DAMAGE, C.BULLET_COOLDOWN, "small and fast"])
	rows.append(["water", "ice shards (7 spikes)", C.SHARD_DAMAGE * float(C.SHARD_COUNT), C.SHARD_COOLDOWN, "close range, all spikes"])
	rows.append(["water", "ice disc", C.DISC_DAMAGE, C.DISC_COOLDOWN, "4 per wall only"])
	rows.append(["water", "octopus swipe x2 arms", C.OCTO_SWIPE_DAMAGE * 2.0, C.OCTO_SWIPE_COOLDOWN, "ult, 9 s"])
	rows.append(["water", "octopus slam", C.OCTO_SLAM_DAMAGE, C.OCTO_SLAM_COOLDOWN, "ult"])
	rows.append(["water", "tidal wave (ult)", C.TIDE_DAMAGE_MAX, C.TIDE_COOLDOWN, "ult, biggest wave"])
	rows.append(["fire", "fire punch (spam)", C.FPUNCH_DAMAGE, C.FPUNCH_COOLDOWN, "heat +%d per punch" % int(C.FPUNCH_HEAT)])
	rows.append(["fire", "flame jet (hold)", C.FLAME_DPS, 1.0, "7 m cone, heat +%d/s: overheats in about %.0f s" % [int(C.FLAME_HEAT), C.HEAT_MAX / C.FLAME_HEAT]])
	rows.append(["fire", "fire whip", C.FWHIP_DAMAGE, C.FWHIP_COOLDOWN, "6 m"])
	rows.append(["fire", "flame arcs (3)", C.FARC_DAMAGE * float(C.FARC_COUNT), C.FARC_COOLDOWN, "all three hit"])
	rows.append(["fire", "fire ring", C.RING_DAMAGE, C.RING_COOLDOWN, "360 burst + burn, then a guard"])
	rows.append(["fire", "combustion beam", C.COMBUST_DAMAGE, C.COMBUST_COOLDOWN, "delayed blast"])
	rows.append(["fire", "dragon rush (ult)", C.RUSH_DPS, 1.0, "ult, %.0f s: at most %.0f" % [C.RUSH_TIME, C.RUSH_DPS * C.RUSH_TIME]])
	rows.append(["fire", "lightning (ult)", C.LIGHT_DAMAGE, 5.0, "ult, 2 s wind-up, single bolt"])
	rows.append(["melee", "combo hit 3 (earth)", C.MELEE_EARTH_DMG[2], 0.5, "no chi needed"])
	rows.append(["bot", "bot melee", C.BOT_MELEE_DAMAGE, C.BOT_MELEE_COOLDOWN, "training dummy"])
	rows.append(["bot", "bot bolt", C.BOT_BOLT_DAMAGE, 1.0, ""])
	print("%-6s %-24s %7s %7s %7s %8s  %s" % ["nation", "move", "dmg", "per s", "dps", "ttk(s)", "note"])
	for r in rows:
		var per_s: float = 1.0 / float(r[3])
		var dps: float = float(r[2]) * per_s
		print("%-6s %-24s %7.1f %7.2f %7.1f %8.1f  %s" % [r[0], r[1], float(r[2]), per_s, dps, 100.0 / dps, r[4]])
	quit(0)
