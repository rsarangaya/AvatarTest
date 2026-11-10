# Avatar Game: Status

Godot 4.3 first-person Avatar: The Last Airbender fan game with Apex Legends-style movement. Native Windows build only (the browser/HTML export did not work for you, so it is dropped).

_Last updated: 2026-11-09_

## How to run and edit
- Double-click `play.bat`. It opens the **main menu** and runs the game straight from the source in `avatar-game/` using `godot/Godot_v4.3-stable_win64.exe`. No build or export step.
- `play_quick.bat` skips the menus and starts straight in a game (edit its last line: `--nation=`, `--mode=duel|bots`, `--enemy=`, `--bots=fighters|benders`, `--botnation=`). Good for fast iteration.
- To change something: edit a script in `avatar-game/scripts/` (all tuning numbers are in `config.gd`), close the game, run `play.bat` again.
- A real `.exe` is only needed to give the game to someone else. That needs the Godot 4.3 export templates (about 1 GB, not installed). Only export when asked ("build").

## Menus
- **Main menu:** Start Game, Moves & Tutorial, Options, Exit (plus "Play again" with your last setup once you have played).
- **Start Game:** Duel or Bots. Then **choose your nation**: picking one shows its moveset on the right, then Confirm.
  - Duel: next choose the **enemy nation** (Air, Earth, Water or Opposite of me), then Confirm and Play.
  - Bots: choose **fighting dummies** (they punch) or **benders** (they use a nation's moves, you pick the nation).
- **Moves & Tutorial:** the same nation screens without playing. Also in the pause menu as **My moves**.
- **Pause menu (Esc):** Resume, Restart, My moves, Options, Quit to menu. Your nation is chosen in the menus now (no switching mid-game).
- **Options:** mouse sensitivity, field of view and **key rebinding** for every key (click a key, press the new one, Esc cancels, a taken key swaps with the other action). Saved between launches. Fixed: left/right click, mouse wheel, Esc, F10 quit, F11 fullscreen.
- The tutorial text is generated from the live key bindings, so it stays correct after rebinding.

## Hidden debug mode
Enter **Up Up Down Down Left Right Left Right B A** on the menus or in a game (enter it again to turn it off). Nothing in the game mentions it. While on: god mode, no cooldowns, and the **Y** key fills the ultimate meter (G is the earth wall grab and T is freeze, so Y). The Y key is rebindable: a "Debug keys" row appears at the bottom of the Options screen only while debug is on. It resets every launch.

## Done

**Movement (all nations):** sprint, slide, crouch, mantle, double/gust jump, glide, air scooter (and wall run), swimming and wading.
**Airbending:** air punch / charged blast, air slice, shield, suction, scooter. Ultimates: Air Breath, Air Bomb.
**Earthbending:** rock throw / earth wave, boulder, stone barrage, earth wall (+ grab and plant), pillar, armor, earth skate, elevator. Ultimates: Earth Clap, Earthquake dive.
**Melee:** out of chi / water, 3-hit combo on LMB, heavy strike on RMB.
**World:** 400 m map with sea and rivers, destructible terrain that slowly heals, bots (dummies, benders, a one-on-one duel enemy).

### Changes in the newest round (2026-11-09, latest)
- **Ice discs (offensive):** press **E** close to your own standing ice wall (within 8 m) and it throws **one spinning ice disc** where you aim (40 damage, goes through enemies, free near ice). A wall gives **4 discs** and **shrinks with every one** (3/4, 2/3, 1/2 of its height, then the 4th uses it up). An enemy right in front still gets frozen instead.
- **Earth pillar, any surface:** aim at level ground and it grows up as before; aim at a cliff, a wall or the side of another pillar and it grows **out sideways** (11 m flat-topped arm, walkable; chain them into bridges and stairs). It needs earth: open water fizzles ("NEEDS EARTH"). Ground has no overhangs, so a sideways arm fills down to the ground beneath it.
- **More water in the middle:** a second, finer stream network plus more ponds. About 17-20% of the middle 240 m is water now (was about 13%). The outer map is unchanged.
- **Debug mode:** the ultimate now stays full while it is on (unlimited ults) and god mode keeps health full. A banner shows when it switches on or off and a small DEBUG tag stays while it is on. Cause of "did nothing" for you was not found: if no banner shows when you type the code, tell me where you typed it.

### Changes in the previous round (2026-11-09, later)
- **Ice shards much stronger:** 7 spikes of 19 damage in a tight fan (a close fan does 100+), faster cooldown, faster spikes.
- **Q is the ice skate only.** It never freezes anything. You glide fast over ice and over open water (no swimming). It still needs water or ice within 4 m.
- **T is a new freeze / unfreeze toggle** (rebindable): while on, water around and ahead of you turns to ice as you move; press again to turn it off and thaw the ice around you (9 m). The debug ult key moved to **Y** (G and T are taken). Old saved key files are fixed up automatically if they clash.
- **Spent water lands on the ground as puddles** (where a whip lands, where shards end, where the jet hits, at your feet for a heal). Gather them again with F; they count as water for free moves; they dry up after 3 minutes (natural water never does).
- **14 ponds across the map**, middle areas included, never on the start meadow or the duel pads. Pond floors count as natural ground for digging limits.
- **The sky darkens during every ultimate** (yours or the duel enemy's: breath, bomb, quake, clap, tidal wave, octopus), fading in over about half a second and back over a second.
- Not built yet, on purpose: more offensive waterbending moves (suggestions: water lance, whirlpool, ice spikes from the ground, freeze burst, mist cloud, wave surf).

### Waterbending
The pouch is the chi bar. Near water or ice (within about 3.5 m, in it, or on ice: ice counts as water) **every move is free**. Away from water the pouch is the limit: it refills slowly by itself (4/s after a 1.5 s delay), and hold **F** to gather by hand, which is ten times faster (40/s). Gathering never lowers the map's water.
- **LMB tap:** water whip, a quick solid lash (a thick opaque flick, left and right alternating). **LMB hold:** water jet, pushes enemies and bolts back.
- **RMB:** heal. **Z:** ice shards (five pointed ice spikes).
- **Q:** ice skate. **Only works with water or ice within 4 m**, and ends 0.5 s after the last of it is behind you. It does not freeze anything (that is T). Ice and water are the same speed for a waterbender: about 1.4x faster than on land. Ice melts after 45 s.
- **E:** ice wall (breaks after one hit, melts after 25 s). On an enemy about 6 ft in front: freezes them for 3 s.
- **X hold near water:** Tidal Wave. **Its size depends on how much water is around you** (measured within 24 m, counting surface area, ice included): a puddle makes a small wave (about 14 m wide, 28 m long), a lake or the sea a huge one (up to 40 m wide, 62 m long, more damage, deeper wake). The HUD shows the wave's size percent when the ultimate is ready. The water it leaves stays where it lands.
- **X tap:** Octopus Form for 16 s: two long water arms with **16 m reach** (grab range 16 m, slam 8 m ahead with 8.5 m radius). LMB left arm, RMB right arm, E slam, Q grab then Q throw (3 s window).
- Waterbenders swim 1.5x faster, are not slowed by wading, and walk 15% faster on ice.
- Everyone else is about 15% slower on ice.

### Ultimate meter (all nations)
No free charging: it fills only from damage you deal (about 500 damage), and an ultimate's own hits do not refill it. The duel enemy's ultimate fills from damage it deals to you (160). Ultimates start empty every duel round.

### Water bots
Water now works for the duel enemy and for bender bots. The water duelist uses: ice shards (fan of 5 and single), whip, jet, ice wall (when hurt), heal (when below half health), a speed boost, and octopus form as its ultimate (long arms that lash you for 8 s). Water grunts throw single shards and whip when close. The player cannot be frozen yet.

## Tests (run with `godot/Godot_v4.3-stable_win64_console.exe --headless --path avatar-game -s res://tests/<name>.gd`)
All pass as of the last run (2026-11-09):
- `water_test.gd`, 106 checks: water kit (free near water, passive refill, skate needs water, ice and swim speeds, tide size, octopus 15 m reach...).
- `menu_smoke.gd`, 36 checks: menu flow (duel, bots, tutorials, options, rebinding, debug code, water bots in a game).
- `input_smoke.gd`, 32 checks: real input through the game scene, pause menu, rebinding, debug code.
- `sim_test.gd`, 230 checks (about 10 min, air + earth + shared), `world_smoke.gd`, `nav_test.gd`.
- `shot_waterbending.gd`, `shot_menus.gd`: open a window and save screenshots (set `SHOT_OUT` to a folder).
- Tests never touch your saved settings (`Settings.persist = false`).

## Not yet checked
- Nobody has played the new menus, rebinding or water kit by hand yet. Tuning numbers are first guesses in `config.gd`.
- The player cannot be frozen by a water enemy yet (and firebenders, a future nation, should be able to escape freezes).
- The ice shard spike looks like small diamonds from behind; check it from the side in play.

## Plan / ideas
- **Firebenders (future nation):** firebenders can escape the waterbender's freeze (and the E-on-enemy freeze). Add this when the nation is built.
- Player freeze (so the water enemy can use the E freeze on you).
- Optional: tune the pouch costs once you have played it.
- Optional: split the .exe into under-25 MB parts for direct repo upload, or attach it to a GitHub Release.
- This folder is not linked to GitHub yet (the repo is rsarangaya/AvatarTest).
