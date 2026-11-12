extends RefCounted
## What was picked in the menus, read by the game scene when it starts. Static, so it survives the scene change.
## The defaults match how the game used to open: an airbender among fighting dummies.

const NATIONS := ["air", "earth", "water", "fire"]
const NATION_NAMES := {"air": "AIR NOMADS", "earth": "EARTH KINGDOM", "water": "WATER TRIBE", "fire": "FIRE NATION"}

static var mode := "bots"            # "duel" (one enemy bender) or "bots" (training bots)
static var player_nation := "air"
static var enemy_nation := "auto"    # duel: "auto" = the opposite of the player's nation, or a nation
static var bot_kind := "fighters"    # bots: "fighters" (chase and punch) or "benders" (use their nation's moves)
static var bot_nation := "earth"     # bots: the nation the benders belong to
static var has_played := false       # a game has been started this launch (the menu then offers "play again")


# The bot mode the world is told to use.
static func world_mode() -> String:
	return "duel" if mode == "duel" else bot_kind


static func nation_name(n: String) -> String:
	return String(NATION_NAMES.get(n, n.to_upper()))
