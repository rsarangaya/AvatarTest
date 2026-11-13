# TASKS

| id | task | agent | status | files |
|----|------|-------|--------|-------|
| F1 | Fire nation: config numbers, heat meter, all moves, ultimates (Dragon Rush, Lightning) in the sim | developer | review | scripts/config.gd, scripts/player_sim.gd |
| F2 | World: flame, ring, combustion job, lightning, burn, guard, freeze thaw, toughness entries | developer | review | scripts/world.gd, scripts/config.gd |
| F3 | Fire bots: duelist, grunts, telegraphed lightning, heat back-off | developer | review | scripts/bender_ai.gd |
| F4 | Menus, tutorial card, HUD row + heat bar, rig colours, settings labels | developer | review | scripts/session.gd, ui.gd, menu.gd, moveset.gd, main.gd, rig.gd, settings.gd |
| F5 | Effects with pooled particles and shared materials | developer | review | scripts/fx.gd |
| F6 | Tests: fire_test, hud_slot_test, menu_smoke, damage_table, sim_cost, perf_fire | developer | review | tests/*.gd |
| F7 | Docs: status.md fire section | developer | done | status.md |
| F8 | Tester: run sim_test and balance pass; reviewer pass | tester / reviewer | todo | |
| V1 | Visual round: tonemap/sky, terrain grain, earth flank jitter, rounded rigs, rock and ice meshes | developer | review | main.gd, terrain_view.gd, terrain.gd, rig.gd, fx.gd |
| V2 | Tidal wave ignores ring guard check | developer | review | tests/fire_test.gd |
| V3 | 3D main-menu backdrop (4 benders, poses, tiny fx, Low = static) | developer | review | scripts/menu_bg.gd, menu.gd, tests/menu_smoke.gd, tests/menu_bg_perf.gd |
| R1 | Round 2: heat visuals + cheap visuals for all nations, projectile node pool, combos (one per nation), kill momentum (per-mode table), burn, lightning chain + bolt duel, swept flame pellets | developer | review | scripts/config.gd, player_sim.gd, world.gd, bender_ai.gd, fx.gd, main.gd, moveset.gd, tests/combo_test.gd, tests/fire_test.gd |

| D1 | Duel difficulty (Normal = player parity, Hard = old boss): config table, menu row on the enemy screen, persisted in settings | developer | review | scripts/config.gd, world.gd, bender_ai.gd, main.gd, settings.gd, menu.gd, tests/difficulty_test.gd |

Status: todo | doing | review | done | blocked
| F8 | Fire rework: small/big fireball, flame burst, fire kick, shorter Dragon Rush, combustion/arcs/whip/jet/fire dash removed; air dash on Z; bots, text, tests | developer | review | scripts/config.gd, player_sim.gd, world.gd, fx.gd, bender_ai.gd, main.gd, moveset.gd, settings.gd, tests/*.gd |
