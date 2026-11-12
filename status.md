# Avatar Game: Status

Godot 4.3 first-person Avatar: The Last Airbender fan game with Apex Legends-style movement. Native Windows build only (the browser/HTML export did not work for you, so it is dropped).

_Last updated: 2026-11-12_

## How to run and edit
- Double-click `play.bat`. It opens the **main menu** and runs the game straight from the source in `avatar-game/` using `godot/Godot_v4.3-stable_win64.exe`. No build or export step.
- `play_quick.bat` skips the menus and starts straight in a game (edit its last line: `--nation=`, `--mode=duel|bots`, `--enemy=`, `--bots=fighters|benders`, `--botnation=`). Good for fast iteration.
- To change something: edit a script in `avatar-game/scripts/` (all tuning numbers are in `config.gd`), close the game, run `play.bat` again.
- A real `.exe` is only needed to give the game to someone else. That needs the Godot 4.3 export templates (about 1 GB, not installed). Only export when asked ("build").

## Menus
- **3D menu backdrop** (`scripts/menu_bg.gd`): the four nations' benders in a loose group, each holding a signature pose with a slow sway and a small effect (air wisps, earth pebbles, water beads, flame flicker), slow camera drift, one dim light, plain ground. Low quality: static poses, no effects, no shadows. It hides and stops on the Options and Moves screens and is freed when a game starts. Menu frame time about 0.7-0.85 ms on all tiers (`tests/menu_bg_perf.gd`); node count after starting a game is back to the menu's own 12.
- **Main menu:** Start Game, Moves & Tutorial, Options, Exit (plus "Play again" with your last setup once you have played).
- **Start Game:** Duel or Bots. Then **choose your nation**: picking one shows its moveset on the right, then Confirm.
  - Duel: next choose the **enemy nation** (Air, Earth, Water, Fire or Opposite of me), then Confirm and Play.
  - Bots: choose **fighting dummies** (they punch) or **benders** (they use a nation's moves, you pick the nation).
- **Moves & Tutorial:** the same nation screens without playing. Also in the pause menu as **My moves**.
- **Pause menu (Esc):** Resume, Restart, My moves, Options, Quit to menu. Your nation is chosen in the menus now (no switching mid-game).
- **Options:** mouse sensitivity, field of view, **graphics quality** (Low / Medium / High) and **key rebinding** for every key (click a key, press the new one, Esc cancels, a taken key swaps with the other action). Saved between launches. Fixed: left/right click, mouse wheel, Esc, F10 quit, F11 fullscreen.
- The tutorial text is generated from the live key bindings, so it stays correct after rebinding.

## Hidden debug mode
Enter **Up Up Down Down Left Right Left Right B A** on the menus or in a game (enter it again to turn it off). Nothing in the game mentions it. While on: a "DEBUG MODE ON" banner flashes (and a small DEBUG tag stays), god mode, no cooldowns, an always-full ultimate (unlimited ults), and the **Y** key also fills the meter (G is the earth wall grab and T is freeze, so Y). The Y key is rebindable: a "Debug keys" row appears at the bottom of the Options screen only while debug is on. It resets every launch.

## Done

**Movement (all nations):** sprint, slide, crouch, mantle, double/gust jump, glide, air scooter (and wall run), swimming and wading.
**Airbending:** air punch / charged blast, air slice, shield, suction, scooter. Ultimates: Air Breath, Air Bomb.
**Earthbending:** rock throw / earth wave, boulder, stone barrage, earth wall (+ grab, plant and throw), pillar (2 charges, grows from any earth surface), armor, earth skate, elevator. Ultimates: Earth Clap, Earthquake dive.
**Waterbending:** whip, water bullets, heal, ice shards, ice wall + ice discs, ice skate, freeze toggle, propel (hold Space over water). Ultimates: Tidal Wave, Octopus Form.
**Firebending:** fire punch, flame jet, fire whip, fire dash, fire ring (guard), flame arcs, combustion beam, heat meter with overheat. Ultimates: Dragon Rush (tap X), Lightning (hold X). Fire duel enemy and fire bender bots.
**Melee:** out of chi / water, 3-hit combo on LMB, heavy strike on RMB.
**World:** 400 m map with sea and rivers, destructible terrain that slowly heals, bots (dummies, benders, a one-on-one duel enemy).

### Fire nation round (2026-11-12, newest)
- **Fire nation (BUILT 2026-11-12)** (`tests/fire_test.gd`, all numbers in `config.gd` under "Fire nation")
  - **Resource: Inner Fire heat meter** (shown in the chi bar, no chi, no melee fallback). Attacks add heat (punch 4, whip 10, dash 8, arcs 14, ring 18, beam 18, flame jet 14 per second) and damage dealt adds 0.04 per point. Above 70% you are HOT: +20% damage and dash distance. At 100% you OVERHEAT: no moves for 2 s and half speed, then heat 50. Heat falls (12 per second) only after 0.8 s without attacking. Standing in water (0.25 m deep) drops it 45 per second and soaks you for 3 s (no ring, no lightning, no flame jet). A kill lowers it by 25. Debug mode: no heat, no overheat, no cooldowns.
  - **LMB tap** fire punch: 12 damage, 0.28 s, 12 m, toughness 1 (about 43 DPS spam). **LMB hold** flame jet: 45 DPS (54 hot), 7 m cone, burns without stunning, burns up weak enemy bolts, melts ice walls (2 hits at once), overheats in about 7 s of holding.
  - **RMB** fire whip: 22 damage, 6 m, 0.9 s. **Q** fire dash: 12 m in 0.16 s (14.4 hot) in your heading, 2.5 s ground cooldown, ONE dash per airborne time (re-armed by landing), no gravity while dashing, exit speed capped at 11 m/s (well below airbender mobility).
  - **F** fire ring (the main defense): instant 360 degree burst, radius 6 m, 30 damage plus 3 s burn (5 per second) and 16 m/s knockback, burns up every enemy projectile in it, melts ice walls; then a 2.2 s GUARD (water puts it out, and it never softens ultimate damage): direct damage is cut to 30% and every non-ultimate projectile that flies within 3.6 m is burnt up. 6 s cooldown. Not usable while soaked.
  - **Z** flame arcs: 3 crescents of 16 (toughness 2), 4 s. **T** combustion beam: fast beam (toughness 3), the blast follows 0.55 s later where it hit: 45 damage in 4.5 m, 14 s. (T is the same key as the waterbender freeze.)
  - **X tap** Dragon Rush (ends if it touches water): 9 s of steerable fire-jet flight (26 m/s, turns 2.6 rad/s towards where you look, stays above the ground), burns everything within 3.2 m at 55 DPS (at most 495 per target), no other moves while it lasts, own hits do not refill the meter, heat is 0 during it. **X hold** Lightning: after the 0.28 s tap window the charge starts (you are slowed to 15%, defenseless). LET GO to fire: after 0.8 s (minimum) the bolt does 50% damage, scaling to 100% = 150 at 2 s, where it fires by itself. Let go before 0.8 s and nothing is spent. Stepping into water cancels the charge (meter kept). Hitscan (x1.3 on a target standing in water, 40 splash within 4 m). Blocked by the ground and earth walls; an earth-armored target soaks all of it. A soaked firebender cannot start it. Immune to clashes (not a projectile, not in `PROJ_TOUGHNESS`).
  - **Projectile toughness:** fire punch 1, flame arc 2, combustion beam 3.
  - **Matchups as built:** earth armor already cuts all damage to 30% (so fire is weak against it), earth walls stop the jet, whip, arcs, beam and lightning. Firebender bots thaw from freezes in 0.5 s (`freeze_bot`). The player cannot be frozen yet.
  - **Bots:** duel enemy "Fire" (450 hp): dashes in, flame jet in melee (30 DPS), whip, arcs, telegraphed combustion (0.9 s ring), ring when hurt and close, backs off at 90% heat, overheats (stunned 2 s) at 100%, lightning with a 2 s visible charge (bolt aimed at the start, dodgeable, 55 damage, earth armor absorbs it). Fire grunts throw fire punches and whip. Decisions at most every 0.2-0.4 s.
  - **Effects (cheap):** one pool of 56 flame puffs (fixed nodes and materials); the effect shaders and floating texts are warmed up in the first 3 frames of a game, and beams share one mesh, flame cone / guard dome / rush shell / lightning orb are fixed shared nodes, rings and domes are capped at 140 live, no per-frame allocations. Measured: sim 0.81 ms per tick with 36 fire bots and a firebender spamming everything (0.62 idle, water 0.69), frame time about 4-4.5 ms at 1280x720 on this PC with everything running, draw calls about 1100-1250 (no more than before).
  - **Not done / ideas:** no player freeze, no fire-specific sounds, soak only from standing in water (water attacks do not soak you yet), the ring does not stop enemy ultimates.

### Previous round (2026-11-11; the entries below are older rounds, kept for history)
- **Cooldown HUD slots** (`hud_slot.gd`): each move shows its cooldown in its HUD slot.
- **Projectile clashes:** toughness is bolt, punch, slice, water bullet and shard 1; rock 2; boulder, slab and disc 3. Ultimates are immune (see Projectile clashes).
- **Propel is a hold with a re-arm rule:** hold Space over water to lift (up to 7 m/s, about 5.5 m above the water at most). After a jet ends it only re-arms once you touch the ground or get within 0.3 m of the water (`PROPEL_REARM_HEIGHT`) with Space released, so you cannot hover or bob over water.

### Balance and moves round (2026-11-09; the entries below are older rounds, kept for history)
- **Rivers through the middle:** two guaranteed great rivers: a winding one west to east (south of the start meadow) and a tributary north to south, both opening into the sea at the ends. About 24% of the middle 240 m is water now. Duel start pads are now picked with water within about 15 m, so a waterbender can get going. Waterbenders can also leave a canyon with propel (now a hold, see Waterbending).
- **Ice discs are visible now:** bigger, bright and glowing with a streak, launched from the top of the wall towards where you aim (they used to start behind the wall where you could not see them).
- **Ice wall takes 2 hits to break** (first hit cracks it). Once it has thrown a disc, hits no longer break it: it stays until its 4 discs are used up or it melts.
- **Earth wall as a shield keeps the wall's proportions** (a smaller copy so it does not fill the screen); planting it back gives the same full wall again, however battered. **Left click while carrying throws it**: it breaks on impact, 70 damage (less if battered) plus 30 splash within 5.5 m, rubble and a crater.
- **Earth pillar has 2 charges** (HUD shows them), each comes back 7 s after use. Chi cost is still charged.
- **Water:** holding left click now fires **water bullets** (8.5 damage, a quick stream, 5 pouch each, free near water). The jet is gone for the player (the water duel enemy still uses its own jet). **Hold Space over water = propel** (changed later: a steady capped lift, not a jump; see Waterbending).
- **Octopus damage cut**: swipe 48 -> 16 (arms every 0.55 s), slam 95 -> 55, throw 40 -> 30. About 58 damage per second with both arms, was about 213.
- **Damage rebalance** (see `tests/damage_table.gd`, run it to print every move's damage per second): water bullets 11 -> 8.5, ice disc 40 -> 34, ice shards 19 -> 17 per spike, air slice 24 -> 21, earth rock throw 16 -> 13, boulder 45 -> 55. Target band for a basic spam is now about 40-55 damage per second; the training dummies and bolts are still very weak (about 6-7 per second), so they barely hurt you: left as they are.
- Screenshot helper: `tests/shot_disc.gd`.

### Visual round (2026-11-12): less blocky, same cost
- **Look:** filmic tonemap, slight contrast/saturation, sun disc, fog sun scatter and aerial perspective (main.gd). Fog was checked on screen (fog on vs off, same camera): it renders in Compatibility. Glow was skipped: Godot 4.3 Compatibility does not render it.
- **Ground:** fine colour grain (+-8%), lighter high up, darker on steep faces (terrain_view.gd, only at chunk rebuild). Raised earth gets a noise jitter of at least 0.3 m on its flanks (`FLANK_JITTER` in terrain.gd feeds the existing roughness term; flat tops and CELL unchanged).
- **Characters:** rig parts are shared unit meshes (capsule limbs/torso, ellipsoid head/hands/feet): same part count, same draw calls (rig.gd).
- **Rocks:** debris, boulder, charge rock and thrown rocks use shared lumpy meshes (faceted chunk, smooth 12x8 boulder) and one shared material (fx.gd). Ice chunks and the freeze block are chamfered crystals with a shared rim-light/emission ice shader (warmed up in fx._warm_up).
- Perf check (High, 1600x900, alternating A/B, 2 runs each): every visual item toggled off one at a time and all off together both land at 5.8-6.9 ms avg, the same as everything on (5.9-6.5 ms). No item costs a measurable amount; the earlier +10-15% was machine drift (the same code swings about +-0.5 ms between runs). Draw calls unchanged (Low ~812, Medium ~1260, High ~2090).
- Skipped: soft unshaded quads (item 7, no clear gain).
- Fix: a tidal wave ignores the ring guard (check added to fire_test.gd).

### Performance round (2026-11-09)
- **Graphics quality in Options** (Low / Medium / High, takes effect at once, also mid-game, saved). **Medium is the default.**
  - High = the old look: 2x anti-aliasing, 4-split shadows to 130 m, everything drawn.
  - Medium: no anti-aliasing, one shadow split to 75 m, ground drawn to 340 m, bots to 140 m.
  - Low: no shadows, ground to 230 m, bots to 85 m (bots beyond that are not drawn or animated). Low also looks a bit darker, because there are no shadows.
- Measured on this PC with vsync off (1600x900), which is a fast PC, so the gain is bigger on weaker ones. Draw calls per frame (steady numbers): High about 2200, Medium about 1300, Low about 700. Frame time moved between runs: High about 5.5-6 ms, Medium 3.8-6.5 ms, Low 2.7-3 ms.
- Terrain edits (earthbending, craters) rebuild chunks within a time budget (about 2.5 ms per frame) instead of a fixed 3 per frame, and the shared chunk index list is built once.
- A long hitch can no longer make the simulation run a long catch-up burst (frame time is capped at 50 ms).
- The simulation itself was already cheap (about 1.2 ms per frame with all 36 bots), so the game's lag was drawing, not game logic.
- Tools: `tests/perf_probe.gd` (frame times, needs a window; `PERF_Q=0|1|2`), `tests/sim_cost.gd`, `tests/chunk_cost.gd`.

### Changes in the previous round (2026-11-09, latest)
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
- **LMB tap:** water whip, a quick solid lash (a thick opaque flick, left and right alternating). **LMB hold:** water bullets (8.5 damage each, a quick stream, 5 pouch each, free near water). **Hold Space with water or ice under your feet (within 3.5 m below):** propel, a jet lifts you steadily (max 7 m/s up, about 5 m over the water at most, slow forward drift, 0.6 s rest after release; free near water, drains the pouch otherwise). Release or lose the water below and you just fall. Much weaker than air mobility (gust jump +13 m/s, chainable, glide, scooter).
- **RMB:** heal. **Z:** ice shards (seven pointed ice spikes, 12 damage each).
- **Q:** ice skate. **Only works with water or ice within 4 m**, and ends 0.5 s after the last of it is behind you. It does not freeze anything (that is T). Ice and water are the same speed for a waterbender: about 1.4x faster than on land. Ice melts after 45 s.
- **E:** ice wall (2 hits to break, melts after 25 s). On an enemy about 6 ft in front: freezes them for 3 s. **E again within 8 m of your wall:** throws an ice disc (34 damage, goes through enemies, launched from the top of the wall towards your aim). 4 discs per wall, it shrinks with each, and after the first disc hits no longer break it.
- **X hold near water:** Tidal Wave. **Its size depends on how much water is around you** (measured within 24 m, counting surface area, ice included): a puddle makes a small wave (about 14 m wide, 28 m long), a lake or the sea a huge one (up to 40 m wide, 62 m long, more damage, deeper wake). The HUD shows the wave's size percent when the ultimate is ready. The water it leaves stays where it lands.
- **X tap:** Octopus Form for 9 s: two long water arms with **16 m reach** (grab range 16 m, slam 8 m ahead with 8.5 m radius). Damage: swipe 12, slam 55, throw 30. LMB left arm, RMB right arm, E slam, Q grab then Q throw (3 s window).
- Waterbenders swim 1.5x faster, are not slowed by wading, and walk 15% faster on ice.
- Everyone else is about 15% slower on ice.

### Ultimate meter (all nations)
No free charging: it fills only from damage you deal (about 500 damage), and an ultimate's own hits do not refill it. The duel enemy's ultimate fills from damage it deals to you (160). Ultimates start empty every duel round.

### Water bots
Water now works for the duel enemy and for bender bots. The water duelist uses: ice shards (fan of 5 and single), whip, jet, ice wall (when hurt), heal (when below half health), a speed boost, and octopus form as its ultimate (long arms that lash you for 8 s). Water grunts throw single shards and whip when close. The player cannot be frozen yet.

### Projectile clashes
Projectiles of opposite sides (player vs enemy/bots) that touch destroy each other with a small puff. Same-side never clash. Toughness (`PROJ_TOUGHNESS` in config.gd): bolt, punch, slice, water bullet, ice shard = 1; rock = 2; boulder, thrown earth wall, ice disc = 3. Heavier survives, equal destroys both. Kinds not in the table (ultimates) are ignored. Test: `tests/projectile_clash_test.gd`.

## Tests (run with `godot/Godot_v4.3-stable_win64_console.exe --headless --path avatar-game -s res://tests/<name>.gd`)
All suites passed on the final run (2026-11-12, fire round): fire_test, water_test, menu_smoke 49, input_smoke 35, hud_slot_test 28, projectile_clash_test 13 (sim_test not re-run by the developer: the tester runs it).
- `water_test.gd` (185): water kit plus ice discs, earth wall slab, pillar charges, propel, rivers and ponds, debug flags.
- `menu_smoke.gd` (46): menu flow (duel, bots, tutorials, options, rebinding, debug code, water bots in a game).
- `input_smoke.gd` (35): real input through the game scene, pause menu, rebinding, debug code, graphics quality.
- `sim_test.gd` (230 checks, about 10 min, air + earth + shared), `world_smoke.gd`, `nav_test.gd`.
- `hud_slot_test.gd` (21): cooldown HUD slots.
- `projectile_clash_test.gd` (13): projectile clashes and toughness.
- `fire_test.gd`: every fire move, heat / hot / overheat / soak / kill rules, ring guard, lightning charge / cancel / earth wall / armor block, rush, freeze thaw, dash limits, debug mode, fire bots.
- `perf_fire.gd` (needs a window): frame times with the fire effects; `sim_cost.gd` now also measures fire.
- Helpers: `damage_table.gd` (every move's damage per second), `probe_water.gd` (water share and duel pads), `perf_probe.gd`, `sim_cost.gd`, `chunk_cost.gd`.
- `shot_waterbending.gd`, `shot_menus.gd`, `shot_sky_ponds.gd`, `shot_disc.gd`: open a window and save screenshots (set `SHOT_OUT` to a folder).
- Tests never touch your saved settings (`Settings.persist = false`).

## Not yet checked
- Nobody has played the new menus, rebinding or water kit by hand yet. Tuning numbers are first guesses in `config.gd`.
- The player cannot be frozen by a water enemy yet (firebender bots already thaw in 0.5 s).
- The ice shard spike looks like small diamonds from behind; check it from the side in play.

## Plan / ideas
- Player freeze (so the water enemy can use the E freeze on you).
- Optional: tune the pouch costs once you have played it.
- Optional: split the .exe into under-25 MB parts for direct repo upload, or attach it to a GitHub Release.
- GitHub: this folder is not a git repo itself. The game was pushed to rsarangaya/AvatarTest (main) from a temporary clone, last at commit fefbd08 (previous 3fa69d0). The pushed commit includes the performance, balance, cooldown HUD, propel hold and projectile clash rounds.
