extends SceneTree
## Headless projectile clash tests. Run:
##   godot --headless --path . -s res://tests/projectile_clash_test.gd

const WorldScript = preload("res://scripts/world.gd")
const C = preload("res://scripts/config.gd")

const DT := 1.0 / 60.0
var failures := 0


func ok(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func has_clash(w) -> bool:
	for e in w.events:
		if e["type"] == "proj_clash":
			return true
	return false


# Two projectiles flying at each other high above the ground. Returns the world after `ticks` updates.
func duel(kind_a: String, team_a: String, kind_b: String, team_b: String, ticks := 30) -> Array:
	var w := WorldScript.new(1337)
	w.bots.clear()
	var y := 150.0
	var a = w.spawn_proj(kind_a, team_a, Vector3(0.0, y, 0.0), Vector3(30.0, 0.0, 0.0), 3.0, 0.5, 5.0, 1.0)
	var b = w.spawn_proj(kind_b, team_b, Vector3(20.0, y, 0.0), Vector3(-30.0, 0.0, 0.0), 3.0, 0.5, 5.0, 1.0)
	for i in range(ticks):
		w._update_projectiles(DT, null)
	return [w, a, b]


func alive(w, p) -> bool:
	return w.projectiles.has(p)


func _init() -> void:
	print("-- projectile clashes")
	var r := duel("rock", "player", "rock", "enemy")
	ok(not alive(r[0], r[1]) and not alive(r[0], r[2]), "opposing equal projectiles destroy each other")
	ok(has_clash(r[0]), "a clash event is emitted for the puff")

	r = duel("rock", "player", "bolt", "enemy")
	ok(alive(r[0], r[1]) and not alive(r[0], r[2]), "a rock survives a bot bolt")
	r = duel("wbullet", "player", "boulder", "enemy")
	ok(not alive(r[0], r[1]) and alive(r[0], r[2]), "a boulder is not wasted on a water bullet")
	r = duel("shard", "enemy", "disc", "player")
	ok(alive(r[0], r[2]) and not alive(r[0], r[1]), "an ice disc survives a shard")
	r = duel("boulder", "player", "slab", "enemy")
	ok(not alive(r[0], r[1]) and not alive(r[0], r[2]), "equal heavy projectiles destroy both")
	r = duel("punch", "enemy", "wbullet", "player")
	ok(not alive(r[0], r[1]) and not alive(r[0], r[2]), "bot punch vs water bullet: both gone")

	r = duel("rock", "player", "rock", "player")
	ok(alive(r[0], r[1]) and alive(r[0], r[2]), "same-owner projectiles never collide (player)")
	r = duel("bolt", "enemy", "rock", "enemy")
	ok(alive(r[0], r[1]) and alive(r[0], r[2]), "same-owner projectiles never collide (bots)")

	# an ultimate kind (anything not in the toughness table) is ignored both ways
	r = duel("tide_test_ult", "player", "rock", "enemy")
	ok(alive(r[0], r[1]) and alive(r[0], r[2]), "an ultimate projectile neither dies nor destroys")
	ok(not C.PROJ_TOUGHNESS.has("tide_test_ult"), "ult kinds are simply not in the toughness table")

	# far apart: nothing happens
	var w := WorldScript.new(1337)
	w.bots.clear()
	var a = w.spawn_proj("rock", "player", Vector3(0, 150, 0), Vector3(10, 0, 0), 3.0, 0.5, 5.0, 1.0)
	var b = w.spawn_proj("rock", "enemy", Vector3(0, 150, 30), Vector3(10, 0, 0), 3.0, 0.5, 5.0, 1.0)
	for i in range(30):
		w._update_projectiles(DT, null)
	ok(alive(w, a) and alive(w, b), "projectiles that do not touch are left alone")

	# fast bullets (80 m/s each, 2.7 m closing per tick) cannot tunnel through each other
	var fast := WorldScript.new(1337)
	fast.bots.clear()
	var fa = fast.spawn_proj("wbullet", "player", Vector3(0, 150, 0), Vector3(80, 0, 0), 3.0, 0.32, 5.0, 1.0)
	var fb = fast.spawn_proj("wbullet", "enemy", Vector3(10.37, 150, 0), Vector3(-80, 0, 0), 3.0, 0.32, 5.0, 1.0)
	for i in range(20):
		fast._update_projectiles(DT, null)
	ok(not alive(fast, fa) and not alive(fast, fb), "fast head-on bullets do not slip through each other")

	print("DONE, %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
