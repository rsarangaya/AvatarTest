extends RefCounted
## The move lists / tutorials shown on the nation screens and in the pause menu.
## An entry is [keys, text]. A key starting with "@" is a rebindable action (shown with whatever key it is bound to);
## anything else is shown as written (mouse buttons and so on).

const Settings = preload("res://scripts/settings.gd")
const C = preload("res://scripts/config.gd")

const COMMON := {
	"title": "MOVEMENT (everyone)",
	"entries": [
		[["@move_forward", "@move_left", "@move_back", "@move_right"], "Move.  Hold [@sprint] to sprint."],
		[["@crouch"], "Crouch. While sprinting it becomes a SLIDE: it keeps your speed and carries you down slopes."],
		[["@jump"], "Jump. Jump at a ledge to MANTLE up it. In water, hold it to swim up."],
		[["Mouse wheel"], "Also jumps."],
		[["Out of resources"], "Left click = 3-hit melee combo, right click = heavy strike."],
		[["Esc"], "Pause menu (restart, moves, options, quit)."],
	],
}

const NATIONS := {
	"air": {
		"title": "AIR NOMADS - light, fast and slippery",
		"blurb": "A bigger chi pool that refills fast, a higher jump, quicker steering in the air. Chi is spent by every move and refills while you stand on the ground.",
		"sections": [
			{"title": "Moves", "entries": [
				[["Left click"], "Tap: AIR PUNCH. Hold: charge an AIR BLAST, release to fire. Aim a charged blast at the ground by your feet to launch yourself."],
				[["Right click"], "AIR SLICE: a crescent that cuts through everything, even earth walls."],
				[["@ability_e"], "Hold: AIR SHIELD. It reflects enemy bolts back at whoever threw them."],
				[["@ability_f"], "Hold: AIR SUCTION. Pulls enemies toward you."],
				[["@ability_q"], "AIR SCOOTER on / off: ride a ball of air. Hit a steep wall at speed and you run straight up it; jump to kick off."],
				[["@jump", "(in mid-air)"], "GUST JUMP: a second jump out of thin air. Hold it while falling to GLIDE."],
			]},
			{"title": "Ultimate", "entries": [
				[["@ultimate"], "AIR BREATH on the ground: a huge stream of air that shoves everything away. 8 m or more up (jump off a hill): AIR BOMB, a dive that blasts a crater."],
			]},
			{"title": "Tips", "entries": [
				[["Tip"], "Stay moving. Your slice and scooter beat earth walls; your shield turns enemy bolts into your damage."],
			]},
		],
	},
	"earth": {
		"title": "EARTH KINGDOM - strong, patient and heavy",
		"blurb": "Hard-hitting moves that tear up the ground, armor and walls. You steal earth from the ground around you, and the land slowly heals itself afterwards.",
		"sections": [
			{"title": "Moves", "entries": [
				[["Left click"], "Tap: ROCK THROW. Hold: charge an EARTH WAVE, a line of earth that throws enemies into the air."],
				[["Right click"], "BOULDER: rips a boulder from the ground, a wall or a hill, then throws it."],
				[["@ability_z"], "STONE BARRAGE: a fan of seven rocks."],
				[["@ability_q"], "EARTH SKATE on / off: stride on rising chunks of earth. Steer with the mouse."],
				[["@jump", "(held at a tall wall)"], "EARTH ELEVATOR: ride a column of rock up a cliff. Hold forward to lean over the top."],
				[["@ability_e"], "EARTH WALL: big, permanent, blocks bolts."],
				[["@ability_g"], "GRAB the nearest wall to carry it as a shield, with the wall's own shape. Press again to plant the same wall. While you carry it, LEFT CLICK THROWS it: it flies, then breaks on what it hits and hurts everything around."],
				[["@ability_v"], "EARTH ARMOR on / off: soaks damage but slows you."],
				[["@ability_f"], "EARTH PILLAR (two charges, each comes back after 7 s) where you aim: hurts, throws enemies up (they take fall damage). Look at your feet to ride one. Aim at a cliff, wall or the side of a pillar and it grows out sideways instead, so you can chain bridges and stairs. It needs earth: not open water."],
			]},
			{"title": "Ultimate", "entries": [
				[["@ultimate"], "EARTH CLAP on the ground: two slabs rise either side of the target and slam together. 8 m or more up: EARTHQUAKE DIVE, land and the ground shakes."],
			]},
			{"title": "Tips", "entries": [
				[["Tip"], "Fight from behind walls and armor. Airbenders slice through your walls and cushion your pillars."],
			]},
		],
	},
	"fire": {
		"title": "FIRE NATION - fierce, fast and burning hot",
		"blurb": "No chi: your power is INNER FIRE, the heat bar. Every attack heats it, and above 70% you hit 20% harder and dash further. At 100% you OVERHEAT: no moves for 2 seconds and you are slow. Heat falls only while you are not attacking. Water cools you down fast (and soaked, you cannot use the ring or lightning). Kills cool you too. Short range, no healing, but you melt out of ice in half a second.",
		"sections": [
			{"title": "Moves", "entries": [
				[["Left click"], "Tap: FIRE PUNCH, a quick short-range fireball. Hold: FLAME JET, a 7 m cone that burns without stopping (heats fast)."],
				[["Right click"], "FIRE WHIP: a 6 m lash of flame."],
				[["@ability_q"], "FIRE DASH: a 12 m burst of speed where you are heading. One dash in the air per landing, a short cooldown on the ground."],
				[["@ability_f"], "FIRE RING: a 360 degree burst that burns and throws everything around you back, then a guard for 2 seconds: you take much less damage and every bolt, rock or boulder that flies into it burns up. Your main defense. Water puts it out."],
				[["@ability_z"], "FLAME ARCS: three crescents of fire (they beat bolts and punches)."],
				[["@ability_freeze"], "COMBUSTION BEAM: a fast beam, and where it lands the blast comes half a second later. Hurts a lot, melts ice walls."],
			]},
			{"title": "Ultimate", "entries": [
				[["@ultimate", "(tap)"], "DRAGON RUSH for {rush_time} seconds: fly as a jet of fire. Steer with the mouse. Everything near the flame burns. No other moves while it lasts."],
				[["@ultimate", "(hold)"], "LIGHTNING: hold to charge while you stand focused (slow and open to attack). Let go to fire the bolt where you aim: after 0.8 seconds it does half damage, after 2 seconds full damage (it fires by itself then). Let go sooner and nothing is spent. Stepping into water ends the charge. Earth walls and earth armor stop it; targets standing in water take extra. Nothing can clash with it, and the fire ring guard does not soften ultimates."],
			]},
			{"title": "Tips", "entries": [
				[["Tip"], "Get close and keep moving. Use the ring when you are hurt or surrounded. Watch the heat bar: stop attacking for a moment before it hits 100%."],
			]},
		],
	},
	"water": {
		"title": "WATER TRIBE - flowing, tricky and best near water",
		"blurb": "Your chi bar is the WATER POUCH. Near water or ice every move is free. Away from it the pouch is all you have: it refills slowly by itself, and much faster when you gather by hand.",
		"sections": [
			{"title": "Water and ice", "entries": [
				[["@ability_f"], "Hold: GATHER. Draw water into the pouch from water under you, close by, or where you are looking (up to 14 m). It never lowers the map's water."],
				[["Near water or ice"], "Everything costs nothing within a few metres of water or ice. Ice counts as water. Waterbenders also swim fast and run quickly on ice."],
				[["Used water"], "Water you spend falls on the ground as puddles (where a lash lands, where shards end, where the jet hits). Walk to a puddle and gather it again with [@ability_f], or just fight next to it: puddles count as water for free moves. They dry up after a few minutes."],
			]},
			{"title": "Moves", "entries": [
				[["Left click"], "Tap: WATER WHIP, a quick solid lash. Hold: WATER BULLETS, a quick stream of small fast bullets of water."],
				[["Space"], "HOLD in or just above water (or over ice) to PROPEL: a jet of water lifts you steadily, a few metres at most, with a little forward drift. Let go, or leave the water, and you fall. Short rest after each use."],
				[["Right click"], "HEAL yourself over a moment."],
				[["@ability_z"], "ICE SHARDS: a tight fan of seven pointed spikes. A close fan hits very hard."],
				[["@ability_q"], "ICE SKATE on / off. Needs water or ice nearby. You glide fast over ice and over open water (no swimming). It ends when no water or ice is left near you. It never freezes anything by itself."],
				[["@ability_freeze"], "FREEZE on / off. While on, the water around and ahead of you turns to ice as you move (skate over it, or walk on it). Press it again to turn it off and thaw the ice around you back into water."],
				[["@ability_e"], "ICE WALL: takes two hits to break. Used on an enemy about 6 ft in front of you it FREEZES them solid for 3 seconds. Then, standing close to your wall, press it again to throw an ICE DISC: one spinning disc flies from the wall where you aim and cuts through enemies. A wall gives four discs and shrinks with each one; once it has thrown a disc, hits no longer break it."],
			]},
			{"title": "Ultimate", "entries": [
				[["@ultimate", "(hold, near water)"], "TIDAL WAVE: pulls the water up into a huge rolling wave. Its size depends on how much water is around you (a puddle is small, a lake or the sea is huge). The water it leaves behind stays where it lands: freeze it with the ice skate and glide over it."],
				[["@ultimate", "(tap)"], "OCTOPUS FORM for {octo_time} seconds: two long water arms. Left click = left arm, right click = right arm, [@ability_e] = slam both arms down, [@ability_q] = grab an enemy (then press it again to throw them within 3 seconds)."],
			]},
			{"title": "Tips", "entries": [
				[["Tip"], "Fight at the water's edge: there are ponds all over the map. Or make your own: a tidal wave leaves wading-deep water everywhere it passed, so moves stay free there. Ice melts after 45 seconds."],
			]},
		],
	},
}


# The whole move list for a nation as BBCode for a RichTextLabel.
static func rich_text(nation: String) -> String:
	var n: Dictionary = NATIONS.get(nation, {})
	if n.is_empty():
		return ""
	var out := "[b][color=#ffe08a]%s[/color][/b]\n[i]%s[/i]\n\n" % [n["title"], n["blurb"]]
	for sec in n["sections"]:
		out += "[b][color=#9fd4ff]%s[/color][/b]\n" % sec["title"]
		out += _entries(sec["entries"])
		out += "\n"
	out += "[b][color=#9fd4ff]%s[/color][/b]\n" % COMMON["title"]
	out += _entries(COMMON["entries"])
	out += "\n[color=#aab]The ultimate meter fills only when you hit enemies (about 500 damage). It never charges by itself.[/color]"
	return out


static func _entries(entries: Array) -> String:
	var s := ""
	for e in entries:
		var names: Array[String] = []
		for k in e[0]:
			names.append(_key_text(String(k)))
		s += "[color=#ffd86b]%s[/color]   %s\n" % [" ".join(names), _text(String(e[1]))]
	return s


static func _key_text(k: String) -> String:
	if k.begins_with("@"):
		return "[lb]%s[rb]" % Settings.key_name(k.substr(1))
	return k


# Inside a description, [@action] becomes the key that action is bound to.
static func _text(t: String) -> String:
	var out := t.replace("{octo_time}", "%d" % int(C.OCTO_TIME)).replace("{rush_time}", "%d" % int(C.RUSH_TIME))
	for a in Settings.ACTIONS:
		out = out.replace("[@%s]" % a["id"], "[color=#ffd86b][lb]%s[rb][/color]" % Settings.key_name(String(a["id"])))
	return out
