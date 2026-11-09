# Avatar Game (Godot 4.3)

First-person Avatar: The Last Airbender fan game with Apex Legends-style movement.
Airbending, earthbending and waterbending kits, a 400 m map with water, destructible and self-healing terrain,
bots (fighters / benders / a one-on-one duel enemy with a full kit).

## Run
Open the folder in Godot 4.3 (GL Compatibility renderer) and press F5, or:

    godot --path .

## Menus and controls
The game opens on a main menu: Start Game (Duel or Bots, then nations, each with its moveset and a Confirm),
Moves & Tutorial, Options (key rebinding, mouse sensitivity, FOV) and Exit. Esc in a game opens the pause menu.
Skip the menus with `godot --path . -- --quick --nation=water --mode=duel --enemy=earth` (see `play_quick.bat`).
A hidden debug mode exists (god mode, no cooldowns, fill the ultimate). It is not documented in the game.

## Tests
    godot --headless --path . -s res://tests/sim_test.gd      # long (~10 min)
    godot --headless --path . -s res://tests/input_smoke.gd
    godot --headless --path . -s res://tests/world_smoke.gd
    godot --headless --path . -s res://tests/nav_test.gd      # duel enemy crosses the map
    godot --headless --path . -s res://tests/water_test.gd    # waterbending kit
    godot --headless --path . -s res://tests/menu_smoke.gd    # menus, rebinding, debug code, water bots

`tests/shot_*.gd` are screenshot scripts (need a display; on Windows just run them normally,
`shot_waterbending.gd` saves into the folder named by the `SHOT_OUT` environment variable).

## Export
Windows: install the 4.3 export templates, then
`godot --headless --path . --export-release "Windows Desktop" build/AvatarGame.exe`.

## Layout
- `scripts/player_sim.gd` – 120 Hz player simulation (movement, bending, melee)
- `scripts/world.gd` – terrain queries, projectiles, bots, duel mode
- `scripts/bender_ai.gd`, `scripts/nav.gd` – bot brains and route planner
- `scripts/fx.gd`, `scripts/rig.gd`, `scripts/terrain_view.gd` – visuals
- `scripts/terrain.gd` – deformable, healing heightfield with water (also flooding and ice for waterbending)
- `scripts/main.gd` – game scene: input, HUD, pause menu, rounds
- `scripts/menu.gd`, `ui.gd`, `options_ui.gd`, `tutorial_view.gd` – main menu, shared UI, options / rebinding, move lists
- `scripts/settings.gd`, `session.gd`, `moveset.gd` – saved settings and key bindings, menu picks, tutorial text
