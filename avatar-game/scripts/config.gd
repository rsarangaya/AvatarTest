extends RefCounted
## All gameplay tuning lives here. Units: metres and seconds.
## Edit a number, re-run the project, feel the difference.

const GRAVITY := 24.0
const TERMINAL_VELOCITY := 70.0
const TICK_RATE := 120

# ---- Body ----
const RADIUS := 0.4
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const EYE_STAND := 1.62
const EYE_CROUCH := 0.95
const STEP_HEIGHT := 0.5

# ---- Player vitals ----
const PLAYER_HP := 100.0
const HP_REGEN := 8.0
const HP_REGEN_DELAY := 4.0

# ---- Ground movement ----
const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const CROUCH_SPEED := 3.0
const GROUND_ACCEL := 10.0
const FRICTION := 7.0
const STOP_SPEED := 2.0
const BHOP_WINDOW := 0.04   # no friction right after landing, so chained jumps keep speed

# ---- Air / jump ----
const AIR_ACCEL := 16.0
const AIR_SPEED := 6.5
const JUMP_SPEED := 8.6
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const STICK_SPEED := 10.0       # above this speed you launch off crests instead of hugging ground
const LAUNCH_TOLERANCE := 0.08

# ---- Slide ----
const SLIDE_MIN_SPEED := 6.5
const SLIDE_BOOST := 1.12
const SLIDE_MAX_START := 14.0
const SLIDE_DECEL := 5.5
const SLIDE_SLOPE_GAIN := 1.3
const SLIDE_MAX_SPEED := 28.0
const SLIDE_END_SPEED := 3.0
const SLIDE_STEER := 1.6
const SLIDE_COOLDOWN := 0.35

# ---- Mantle ----
const MANTLE_REACH := 2.3
const MANTLE_MIN_HEIGHT := 0.6
const MANTLE_BASE := 0.28
const MANTLE_PER_METER := 0.07
const MANTLE_EXIT_SPEED := 4.5
const MANTLE_COOLDOWN := 0.25

# =====================================================================
# AIRBENDING
# =====================================================================
# Chi: energy for every move except the two ultimates.
const CHI_MAX := 100.0
const AIR_CHI_MAX := 160.0       # airbenders carry a bigger pool and refill faster
const AIR_CHI_REGEN := 45.0
const CHI_REGEN := 22.0          # per second, only while grounded and not channelling anything
const CHI_REGEN_DELAY := 0.5     # pause after spending chi

# ---- Gust Jump: press Jump in mid-air ----
const GUST_COST := 30.0
const GUST_UP := 13.0
const GUST_PUSH := 5.0
const GUST_SPEED_GAIN := 2.5
const GUST_MIN_SPEED := 6.0
const GUST_COOLDOWN := 0.25
const GUST_MIN_AIR_TIME := 0.18
const GUST_MIN_HEIGHT := 0.5

# ---- Glide: hold Jump while falling ----
const GLIDE_FALL := 2.6
const GLIDE_VERT_ACCEL := 40.0
const GLIDE_START_VY := -1.0
const GLIDE_DRAIN := 7.0
const GLIDE_ACCEL := 14.0
const GLIDE_SPEED_FLOOR := 11.0
const GLIDE_MIN_AIR_TIME := 0.2

# ---- Air Scooter: Q toggles ----
const SCOOTER_COST_START := 15.0
const SCOOTER_DRAIN := 10.0
const SCOOTER_SPEED := 15.0
const SCOOTER_ACCEL := 18.0              # m/s^2 up to cruise speed
const SCOOTER_TURN := 3.0                # rad/s the heading can swing while steering
const SCOOTER_OVERSPEED_DRAG := 0.8      # per second, bleeds speed above cruise (downhill gains)
const SCOOTER_FRICTION := 1.5            # coasting with no input
const SCOOTER_SLOPE_GAIN := 0.8
const SCOOTER_MAX_SPEED := 26.0
const SCOOTER_JUMP_MULT := 1.15

# ---- Left click: tap = Air Punch, hold = charge an Air Blast ----
const TAP_TIME := 0.22                   # held longer than this = charging
const PUNCH_COST := 11.0
const PUNCH_COOLDOWN := 0.2
const PUNCH_SPEED := 40.0                # a small fast gust
const PUNCH_LIFE := 0.28                 # ~11 m of range
const PUNCH_RADIUS := 0.5
const PUNCH_DAMAGE := 8.0
const PUNCH_KNOCKBACK := 7.0

const CHARGE_TIME := 1.1                 # seconds from first charge to full
const CHARGE_DRAIN := 28.0               # chi per second while charging (full charge ~ 31 chi)
# Blast values run from "tap-sized" to "fully charged" (world.apply_blast lerps between them).
const BLAST_RANGE := 14.0
const BLAST_RANGE_FULL := 32.0
const BLAST_CONE_COS := 0.92             # uncharged: narrow cone
const BLAST_CONE_COS_FULL := 0.80        # fully charged: wide cone
const BLAST_IMPULSE := 12.0
const BLAST_IMPULSE_FULL := 32.0
const BLAST_DAMAGE := 14.0
const BLAST_DAMAGE_FULL := 62.0
# Aim a charged blast at the ground near your feet to launch yourself.
const BLAST_BOOST_RANGE := 4.5
const BLAST_BOOST_LOOK_Y := -0.45
const BLAST_SELF_PUSH := 12.0            # x (0.5 + charge)
const BLAST_MAX_H_SPEED := 30.0

# ---- Right click: Air Slice (crescent projectile that pierces) ----
const SLICE_COST := 18.0
const SLICE_COOLDOWN := 0.45
const SLICE_SPEED := 48.0
const SLICE_LIFE := 1.0
const SLICE_RADIUS := 1.5
const SLICE_DAMAGE := 21.0
const SLICE_KNOCKBACK := 10.0

# ---- E (hold): Air Shield. Reflects enemy bolts back at whoever fired them. ----
const SHIELD_MIN_CHI := 10.0
const SHIELD_DRAIN := 12.0
const SHIELD_RADIUS := 1.9
const SHIELD_REFLECT_MULT := 1.5         # reflected bolts hit this much harder
const SHIELD_MOVE_MULT := 0.7

# ---- F (hold): Air Suction ----
const SUCTION_MIN_CHI := 8.0
const SUCTION_DRAIN := 14.0
const SUCTION_RANGE := 18.0
const SUCTION_CONE_COS := 0.80
const SUCTION_PULL_SPEED := 16.0
const SUCTION_HOLD_DIST := 2.8

# ---- X: Ultimate (context sensitive). Both need a full ultimate meter. ----
const ULT_MAX := 100.0
const ULT_PER_DAMAGE := 0.2              # per point of damage you deal: about 500 damage fills the meter (no free charging)
const BOT_ULT_DAMAGE := 160.0            # damage the duel enemy must deal to you for a full ultimate

# Air Breath: a huge, channelled stream of pure air
const BREATH_DURATION := 2.4
const BREATH_RANGE := 34.0
const BREATH_CONE_COS := 0.88            # ~28 degree half-angle: 36 m wide at full range
const BREATH_DAMAGE_PER_SEC := 85.0
const BREATH_PUSH := 38.0                # m/s^2 pushed onto targets
const BREATH_RECOIL := 9.0               # m/s^2 pushed back onto you
const BREATH_MOVE_MULT := 0.6

# Air Bomb: only when airborne at least this high above the ground below.
# The Air Temple tower (about 26 m) is the easy way up there.
const BOMB_MIN_HEIGHT := 8.0
const BOMB_WINDUP := 0.35
const BOMB_DIVE_SPEED := 48.0
const BOMB_STEER := 14.0
const BOMB_STEER_MAX := 7.0
const BOMB_RADIUS := 16.0                # scales 70-100% with how high you were
const BOMB_DAMAGE := 110.0
const BOMB_KNOCKBACK := 26.0

# ---- Dummy bots (they wander near home; set BOT_ATTACKS false for pure target dummies) ----
const BOT_HP := 100.0
const BOT_RESPAWN := 4.0
const BOT_RADIUS := 0.45
const BOT_WANDER_SPEED := 2.2
const BOT_ATTACKS := true
const BOT_SIGHT := 30.0
const BOT_FIRE_MIN := 2.5
const BOT_FIRE_MAX := 4.5
const BOT_BOLT_SPEED := 15.0
const BOT_BOLT_LIFE := 3.0
const BOT_BOLT_RADIUS := 0.35
const BOT_BOLT_DAMAGE := 6.0


# =====================================================================
# TERRAIN
# =====================================================================
const MAX_WALK_SLOPE := 1.4              # rise/run. Steeper ground cannot be climbed on foot (about 54 degrees)
const STEEP_SLIDE_ACCEL := 20.0          # you slip down slopes steeper than that

# =====================================================================
# EARTHBENDING  (press 2 for earth, 1 for air. Same chi bar, same ultimate meter.)
# =====================================================================
# ---- Left click: tap = Rock Throw, hold = charge an Earth Wave ----
const ROCK_COST := 8.0
const ROCK_COOLDOWN := 0.35
const ROCK_SPEED := 36.0
const ROCK_LIFE := 2.2
const ROCK_GRAVITY := 13.0
const ROCK_RADIUS := 0.6
const ROCK_DAMAGE := 11.0
const ROCK_KNOCKBACK := 9.0
const ROCK_SPLASH := 2.8
const ROCK_SPLASH_DAMAGE := 12.0
const ROCK_CRATER_RADIUS := 2.3
const ROCK_CRATER_DEPTH := 1.1

const WAVE_LEN := 12.0                   # tap-sized .. fully charged
const WAVE_LEN_FULL := 30.0
const WAVE_SPEED := 55.0
const WAVE_RISE := 1.6
const WAVE_RISE_FULL := 3.4
const WAVE_DAMAGE := 14.0
const WAVE_DAMAGE_FULL := 46.0
const WAVE_LAUNCH := 8.0
const WAVE_LAUNCH_FULL := 15.0
const WAVE_HIT_RADIUS := 2.2

# ---- E: Earth Wall (permanent until destroyed). G grabs it as a mobile shield, G again plants it ----
const WALL_COST := 24.0
const WALL_COOLDOWN := 1.5
const WALL_DIST := 5.5
const WALL_HALF_WIDTH := 6.5
const WALL_HEIGHT := 5.5
const WALL_DUR := 0.3
const WALL_W_TOP := 1.1
const WALL_W_FLANK := 1.3
const WALL_GRAB_RANGE := 8.0             # how close you must be to a wall to grab it
const HELD_HALF_WIDTH := 2.6             # the carried slab
const HELD_HEIGHT := 1.45
const HELD_MAX_HALF_WIDTH := 4.0          # a carried slab is a small copy of its wall with the same proportions (planted, the wall is full size again)
const HELD_MAX_HEIGHT := 1.7
const HELD_DIST := 2.4
const HELD_HP := 160.0
const HELD_MOVE_MULT := 0.8
# Throwing the carried slab (left click): it flies, then breaks on whatever it hits and hurts what is around
const SLAB_SPEED := 46.0
const SLAB_GRAVITY := 10.0
const SLAB_LIFE := 2.5
const SLAB_DAMAGE := 70.0                # scaled down for a battered slab
const SLAB_SPLASH := 5.5
const SLAB_SPLASH_DAMAGE := 30.0

# ---- F: Earth Pillar (aim at ground, or at your feet to ride it) ----
const PILLAR_COST := 24.0
const PILLAR_COOLDOWN := 0.5              # between two pillars
const PILLAR_CHARGES := 2                 # you hold this many pillars; each one comes back after PILLAR_RECHARGE seconds
const PILLAR_RECHARGE := 7.0
const PILLAR_RANGE := 30.0
const PILLAR_HEIGHT := 6.5
const PILLAR_DUR := 0.3
const PILLAR_R_TOP := 1.7
const PILLAR_R_FLANK := 2.4
const PILLAR_SIDE_MIN_NY := 0.8           # aimed at ground steeper than this (a cliff, wall or pillar flank) the pillar grows sideways
const PILLAR_SIDE_LEN := 11.0             # length of a sideways pillar
const PILLAR_SIDE_RISE := 1.2             # its flat top sits this far above the point you aimed at
const PILLAR_SIDE_DUR := 0.5
const PILLAR_BOT_LAUNCH := 13.0
const PILLAR_BOT_DAMAGE := 55.0
const LIFT_LAUNCH_RATE := 8.0            # ground rising faster than this (m/s) throws you instead of carrying you
const LIFT_LAUNCH_MAX := 17.0

# ---- X (airborne, earth): Earthquake. Dive from high up; landing starts the quake ----
const QUAKE_DURATION := 3.2
const QUAKE_RADIUS := 17.0
const QUAKE_DPS := 42.0
const QUAKE_AMOUNT := 2.6
const QUAKE_MOVE_MULT := 0.6
const QUAKE_STEP := 0.075                # seconds between terrain updates

# =====================================================================
# DESTRUCTION (craters have a floor: the ground never goes more than a few metres below its natural level)
# =====================================================================
const BOMB_CRATER_RADIUS := 9.5
const BOMB_CRATER_DEPTH := 4.6
const BLAST_CRATER_RANGE := 40.0
const BLAST_CRATER_MIN_CHARGE := 0.3
const BLAST_CRATER_RADIUS := 1.6         # + 3.2 x charge
const BLAST_CRATER_DEPTH := 0.7          # + 2.0 x charge
const SLICE_CUT_WIDTH := 0.9
const SLICE_CUT_DEPTH := 1.5
const SLICE_CUT_LENGTH := 3.0
const BREATH_ERODE_RADIUS := 4.5
const BREATH_ERODE_DEPTH := 0.3
const BREATH_ERODE_STEP := 0.08


static func ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# --- Earth offence: Boulder (right click) and Stone Barrage (Z)
const BOULDER_COST := 26.0
const BOULDER_COOLDOWN := 2.2
const BOULDER_SPEED := 26.0
const BOULDER_LIFE := 3.2
const BOULDER_GRAVITY := 8.0
const BOULDER_RADIUS := 1.2
const BOULDER_DAMAGE := 55.0
const BOULDER_KNOCKBACK := 16.0
const BOULDER_SPLASH := 6.5
const BOULDER_SPLASH_DAMAGE := 40.0
const BOULDER_CRATER_RADIUS := 5.0
const BOULDER_CRATER_DEPTH := 2.4
const BARRAGE_COST := 30.0
const BARRAGE_COOLDOWN := 3.5
const BARRAGE_COUNT := 7
const BARRAGE_SPEED := 42.0
const BARRAGE_SPREAD := 0.11              # radians between rocks
const BARRAGE_DAMAGE := 10.0
const BARRAGE_SPLASH_DAMAGE := 6.0


# --- The land heals: edited ground slowly returns to the shape the level was built with
const HEAL_DELAY_DUG := 9.0               # seconds a crater sits untouched before it starts filling in
const HEAL_DELAY_RAISED := 16.0           # raised earth (walls, ramps, pillars) lasts a bit longer before sinking
const HEAL_MIN_RATE := 0.05               # m/s even for tiny differences
const HEAL_FRAC := 0.07                   # extra fraction of the remaining difference per second


# ---- X (grounded, earth): Earth Clap. Two slabs rise either side of the target and slam together ----
const CLAP_RANGE := 34.0
const CLAP_MIN_DIST := 7.0
const CLAP_SNAP := 9.0                   # snaps onto a bot this close to where you aim
const CLAP_HALF_LEN := 8.0               # slab half length along the line of sight
const CLAP_GAP := 6.0                    # slab centre line distance from the target when open
const CLAP_CLOSED := 1.1                 # ... and when closed
const CLAP_HEIGHT := 8.0
const CLAP_RISE := 0.5
const CLAP_HOLD := 0.35
const CLAP_SLAM := 0.28
const CLAP_W_TOP := 1.2
const CLAP_W_FLANK := 1.0
const CLAP_RISE_DAMAGE := 15.0
const CLAP_DAMAGE := 150.0
const CLAP_KNOCK_UP := 8.0
const QUAKE_LAND_RADIUS := 8.0           # shockwave when the earthquake dive lands
const QUAKE_LAND_DAMAGE := 35.0

# ---- Earth Elevator: hold Space against a wall (W to push forward) ----
const ELEV_SPEED := 9.0
const ELEV_ACCEL := 70.0
const ELEV_FORWARD := 3.2
const ELEV_DRAIN := 12.0
const ELEV_MIN_CHI := 6.0
const ELEV_LIP_FWD := 5.5
const ELEV_LIP_UP := 5.0

# ---- Q: Earth Skate (ride a slab over the ground, Toph-style) ----
const SKATE_COST_START := 8.0
const SKATE_DRAIN := 5.0
const SKATE_SPEED := 17.0
const SKATE_MAX_SPEED := 30.0
const SKATE_ACCEL := 26.0
const SKATE_TURN := 3.4                  # rad/s heading swing
const SKATE_FRICTION := 0.9
const SKATE_SLOPE_GAIN := 0.9
const SKATE_OVERSPEED_DRAG := 0.35

# ---- V: Earth Armor ----
const ARMOR_COST := 20.0
const ARMOR_HP := 120.0
const ARMOR_SOAK := 0.7                  # share of each hit the armor takes
const ARMOR_MOVE_MULT := 0.7
const ARMOR_REGEN := 5.0                 # armor hp per second while it is off
const ARMOR_TOGGLE_CD := 0.8

# ---- Bots thrown by earth take landing damage; airbender bots cushion the fall ----
const FALL_SAFE_SPEED := 9.0
const FALL_DAMAGE_PER_MS := 4.0
const FALL_DAMAGE_MAX := 70.0
const CUSHION_HEIGHT := 5.0
const CUSHION_COOLDOWN := 7.0

# ---- water
const SWIM_DEPTH := 1.35
const WADE_MULT := 0.72
const SWIM_SPEED := 5.5
const SWIM_SPRINT := 8.5
const SWIM_ACCEL := 22.0
const SWIM_FLOAT := 1.15      # eye-ish: feet this far below the surface
const SWIM_DIVE := 5.0
const SWIM_RISE := 5.0
const SWIM_HOP := 8.5

# =====================================================================
# WATERBENDING  (Water Tribe in the pause menu)
# The pouch is the chi bar: it never refills by itself. Hold F near water to gather. Gathering never drains the map's water.
# =====================================================================
const WATER_MAX := 120.0
const WATER_PASSIVE := 4.0               # the pouch slowly refills by itself (per second) ...
const WATER_PASSIVE_DELAY := 1.5         # ... a moment after you last spent from it
const WATER_FREE_RADIUS := 3.5           # in or this close to water or ice, waterbending costs nothing
const WATER_SWIM_MULT := 1.5             # waterbenders swim faster, and do not wade slowly
const ICE_WALK_WATER_MULT := 1.15        # a waterbender on foot is a little quicker on ice
const ICE_SLOW_MULT := 0.85              # everyone else is a little slower on ice
const GATHER_RATE := 40.0                # pouch per second while gathering by hand (much faster than the passive refill)
const GATHER_REACH := 14.0               # how far along your sight line water can be pulled from
const GATHER_NEAR := 3.5                 # ... or standing this close to / in it
const GATHER_STEP := 0.14                # seconds between visual streams

# ---- Left click: tap = Water Whip, hold = Water Jet ----
const WHIP_VIS_TIME := 0.24              # the lash is a quick solid flick: out, crack, back
const WHIP_COST := 6.0
const WHIP_COOLDOWN := 0.34
const WHIP_REACH := 9.0
const WHIP_WIDTH := 1.1                  # how far from the lash a body can be and still get hit
const WHIP_DAMAGE := 15.0
const WHIP_KNOCKBACK := 6.0
# Water bullet (hold left click): a quick stream of small, fast bullets of water
const BULLET_COST := 5.0                  # pouch per bullet (free near water, as everything is)
const BULLET_COOLDOWN := 0.18
const BULLET_SPEED := 80.0
const BULLET_LIFE := 1.1
const BULLET_RADIUS := 0.32
const BULLET_DAMAGE := 8.5
const BULLET_KNOCKBACK := 3.0
# Water propel (hold Space): while water or ice is under your feet (within PROPEL_REACH below you) a jet lifts you
# steadily, like riding a rising column. Let go or lose the water below and it stops (you simply fall, no burst).
# Deliberately weaker than airbending mobility: air jump is about 1.7 m, a gust jump adds 13 m/s up (about 3.5 m) and
# can be chained, glide and scooter keep going; propel tops out at about 5 m over the water (reach + a short coast) and drifts slowly.
const PROPEL_VY := 7.0                    # m/s upward speed cap while the jet is on
const PROPEL_ACCEL := 30.0                # m/s^2 towards that speed (it builds up, no burst)
const PROPEL_REACH := 3.5                 # m: the jet only lifts while your feet are at most this high above the water/ice
const PROPEL_SPEED := 7.0                 # m/s: sideways speed cap while lifting (modest forward carry, about a walk/sprint)
const PROPEL_AIR_ACCEL := 10.0            # m/s^2 of steering while lifting
const PROPEL_DRAG := 1.0                  # per second, bleeds extra sideways speed while lifting
const PROPEL_REARM_HEIGHT := 0.3          # m: after a jet ends, touching the ground or getting this close to the water, with Space released, re-arms it (no bobbing)
const PROPEL_COOLDOWN := 0.6              # s of rest after you let go or run out of water
const PROPEL_DRAIN := 12.0                # pouch per second while held (free near water, as every water move is)
const PROPEL_MIN := 6.0                   # pouch needed to start (free near water)
const JET_DRAIN := 20.0
const JET_MIN := 4.0
const JET_RANGE := 17.0
const JET_CONE_COS := 0.93
const JET_DPS := 26.0
const JET_PUSH := 46.0                   # m/s^2 pushed onto targets: the jet shoves enemies back
const JET_RECOIL := 3.0
const JET_MOVE_MULT := 0.75

# ---- Right click: heal ----
const HEAL_COST := 24.0
const HEAL_AMOUNT := 28.0
const HEAL_TIME := 1.3
const HEAL_COOLDOWN := 2.6

# ---- Z: Ice Shards ----
const SHARD_COST := 26.0
const SHARD_COOLDOWN := 1.9
const SHARD_COUNT := 7
const SHARD_SPEED := 64.0
const SHARD_LIFE := 1.3
const SHARD_RADIUS := 0.45
const SHARD_SPREAD := 0.035
const SHARD_DAMAGE := 12.0              # per spike: a close fan of seven can do well over 100
const SHARD_KNOCKBACK := 6.0

# ---- T: freeze / unfreeze (a toggle). While on, the water around and ahead of you freezes as you move; press again to
# turn it off and thaw the ice around you back into water. Q is the ice skate only and never freezes anything.
const FREEZE_THAW_RADIUS := 9.0
const FREEZE_DRY_GRACE := 1.5            # the freeze switches itself off this long after the last water or ice is behind you

const POND_COUNT := 24                # ponds and small lakes carved into the level (the middle of the map included)

# ---- Water you spend lands on the ground as puddles you can gather again (and that count as water for free moves)
const PUDDLE_LIFE := 180.0               # seconds before a puddle dries up (natural water never does)
const PUDDLE_MIN_AMOUNT := 3.0           # spending less than this leaves nothing behind

# ---- Q: Ice Skate (toggle). Freezes the water you glide over; faster on ice and water than on dry land ----
const ICE_SKATE_COST := 6.0
const ICE_SKATE_DRAIN := 2.5
const ICE_SKATE_ICE_MULT := 1.4          # same on ice and on water: they are the same thing to a waterbender
const ICE_SKATE_LAND_MULT := 0.55
const ICE_SKATE_WATER_RANGE := 4.0       # the skate only works with water or ice this close ...
const ICE_SKATE_DRY_GRACE := 0.5         # ... and ends this long after the last of it is behind you
const ICE_FREEZE_RADIUS := 3.2           # ice appears this far around a point just ahead of you
const ICE_FREEZE_AHEAD := 2.0
const ICE_FREEZE_STEP := 0.1
const ICE_MELT := 45.0                   # seconds a sheet of ice lasts before the water comes back

# ---- E: Ice Wall (breaks after one hit). Used on an enemy in front of you it freezes them solid ----
const ICE_WALL_COST := 22.0
const ICE_WALL_COOLDOWN := 1.6
const ICE_WALL_HITS := 2                  # hits it takes to break (a wall that has thrown a disc is no longer hurt by hits)
const ICE_WALL_DIST := 3.6
const ICE_WALL_HALF_WIDTH := 3.4
const ICE_WALL_HEIGHT := 3.4
const ICE_WALL_DUR := 0.2
# Ice discs: press E close to your own standing ice wall and it throws spinning discs of ice (Katara against Pakku)
const DISC_NEAR := 8.0                    # how close you must be to the wall (metres to its nearest point)
const DISC_COST := 7.0                    # one disc per press
const DISC_COOLDOWN := 0.45
const DISC_SHOTS := 4                     # a wall gives this many discs; it shrinks with every one and is gone after the last
const DISC_SPEED := 50.0
const DISC_LIFE := 1.5
const DISC_RADIUS := 0.95
const DISC_DAMAGE := 28.0
const DISC_KNOCKBACK := 9.0
const ICE_WALL_LIFE := 25.0             # an untouched ice wall melts away after this long
const ICE_FREEZE_RANGE := 1.9            # about 6 ft
const ICE_FREEZE_COS := 0.55
const ICE_FREEZE_TIME := 3.0

# ---- X (ultimate): hold near water = Tidal Wave, tap = Octopus Form ----
const ULT_HOLD_TIME := 0.28
const TIDE_WATER_RANGE := 16.0           # water must be this close to pull a Tidal Wave
const TIDE_SPEED := 26.0
const TIDE_KNOCK := 14.0
# The wave's size depends on how much water is around you: a puddle gives the small values, a lake or the sea the big ones.
const TIDE_SOURCE_RADIUS := 24.0         # water is measured this far around you (a water cell counts by its surface area)
const TIDE_SOURCE_FULL := 700.0          # m^2 of water that makes a full-size wave
const TIDE_MIN_STRENGTH := 0.3
const TIDE_HALF_MIN := 7.0               # half width of the wave (it is 2 x this wide)
const TIDE_HALF_MAX := 20.0
const TIDE_LEN_MIN := 28.0
const TIDE_LEN_MAX := 62.0
const TIDE_DAMAGE_MIN := 30.0
const TIDE_DAMAGE_MAX := 80.0
const TIDE_COOLDOWN := 5.0               # nominal seconds per wave, only used by the damage table (the real gate is the ult meter)
const TIDE_FLOOD_MIN := 0.5              # the water left behind (wading depth: freeze it with Q and slide)
const TIDE_FLOOD_MAX := 1.1
const TIDE_FLOOD_END := 0.55             # share of that depth left at the far end of the wave
const TIDE_BARREL_MIN := 1.3             # height of the rolling wave
const TIDE_BARREL_MAX := 3.2

const OCTO_TIME := 9.0
const OCTO_REACH := 16.0
const OCTO_WIDTH := 1.9
const OCTO_SWIPE_DAMAGE := 12.0
const OCTO_SWIPE_COOLDOWN := 0.55
const OCTO_SWIPE_KNOCK := 12.0
const OCTO_SLAM_DAMAGE := 55.0
const OCTO_SLAM_RADIUS := 8.5
const OCTO_SLAM_DIST := 8.0
const OCTO_SLAM_COOLDOWN := 2.6
const OCTO_GRAB_RANGE := 16.0
const OCTO_GRAB_COS := 0.8
const OCTO_GRAB_TIME := 3.0
const OCTO_HOLD_DIST := 3.4
const OCTO_THROW_SPEED := 30.0
const OCTO_THROW_DAMAGE := 30.0
const OCTO_GRAB_COOLDOWN := 1.0

const BOULDER_PULL_TIME := 0.5
const BOULDER_PULL_RADIUS := 2.4
const BOULDER_PULL_DEPTH := 1.4
const BOULDER_REACH := 16.0
const BOULDER_HOLD_DIST := 2.2

# airbenders are naturally a little lighter and faster
const AIR_SPEED_MULT := 1.07
const AIR_GRAVITY_MULT := 0.9

# airbenders: light on their feet (snappier starts and air steering, longer coyote, higher hop, slower glide fall)
const AIR_GROUND_ACCEL_MULT := 1.5
const AIR_AIRCTL_MULT := 1.4
const AIR_JUMP_MULT := 1.06
const AIR_COYOTE_MULT := 1.6
const AIR_GLIDE_FALL_MULT := 0.8

# Air Scooter wall climbing: enough speed carries you up steep ground
const SCOOTER_CLIMB_MIN := 13.0
const SCOOTER_CLIMB_KEEP := 5.0
const SCOOTER_CLIMB_DECAY := 7.0

# Earth Clap "book": the pages hinge at a spine through the target, open a little, then slam shut and stand upright
const CLAP_SPINE := 1.6
const CLAP_OPEN_DEG := 32.0
const CLAP_PAGE := 8.0

# Air Scooter wall run: hit a steep wall fast enough and the scooter's momentum carries you straight up it
const WALLRUN_MIN := 12.0         # horizontal speed needed to take a wall
const WALLRUN_DECAY := 8.0        # speed spent per second while climbing
const WALLRUN_CLIMB := 0.95       # climb speed as a fraction of the remaining speed
const WALLRUN_END := 3.0          # below this the climb gives out

# ---- Melee: left/right click with too little chi for the bending move ----
const MELEE_RANGE := 2.5
const MELEE_HEAVY_RANGE := 3.0
const MELEE_COS := 0.45
const MELEE_WINDOW := 0.6           # chain the next strike inside this
const MELEE_LUNGE := 4.0
const MELEE_CHI_PER_HIT := 4.0
const MELEE_AIR_DMG := [7.0, 7.0, 12.0]
const MELEE_EARTH_DMG := [10.0, 10.0, 18.0]
const MELEE_KNOCK := [3.0, 3.0, 9.0]
const MELEE_AIR_CD := 0.28
const MELEE_EARTH_CD := 0.38
const MELEE_AIR_HEAVY := 18.0
const MELEE_EARTH_HEAVY := 26.0
const MELEE_HEAVY_KNOCK := 14.0
const MELEE_HEAVY_CD := 0.85

# ---- Bot fighters ----
const BOT_CHASE_RANGE := 9.0
const BOT_CHASE_SPEED := 3.8
const BOT_LEASH := 14.0
const BOT_MELEE_RANGE := 2.3
const BOT_MELEE_HIT_RANGE := 2.9
const BOT_MELEE_WINDUP := 0.38
const BOT_MELEE_COOLDOWN := 1.3
const BOT_MELEE_DAMAGE := 9.0
const BOT_MELEE_PUSH := 5.0


# ---- Projectile clashes ----
# Two projectiles of opposite sides (player vs enemy/bot) that touch destroy each other, unless one is tougher: the
# heavier one survives (a light one is wasted on it), equal toughness destroys both. Same-side projectiles never clash.
# A kind that is NOT in this table is an ultimate (or anything an ultimate spawns) and is ignored by clashes: it
# neither gets destroyed nor destroys others. (Tidal wave, air bomb, air breath, earth clap, earthquake and octopus arms
# are not projectiles at all, so they are untouched by construction.)
const PROJ_TOUGHNESS := {
	"bolt": 1,       # bot bolt
	"punch": 1,      # air punch / charged blast
	"slice": 1,      # air slice
	"wbullet": 1,    # water bullet
	"shard": 1,      # ice shard (also the enemy's)
	"rock": 2,       # rock throw / stone barrage
	"boulder": 3,
	"slab": 3,       # thrown earth wall
	"disc": 3,       # ice disc (still passes through enemies)
	"fpunch": 1,     # fire punch
	"farc": 2,       # flame arc
	"cbeam": 3,      # combustion beam (its blast comes later)
}
const CLASH_PAD := 0.1                    # m added to the two radii when testing a touch


# ---- Fire nation (firebender). Resource: the INNER FIRE heat meter (0..100), shown in the chi bar. No chi, no melee fallback.
# Spam DPS target 40-55 (see tests/damage_table.gd). Heat rises with every attack and a little with damage dealt; it only
# falls when you have not attacked for HEAT_IDLE seconds. Above HEAT_HOT you are HOT (+20% damage and dash distance).
const HEAT_MAX := 100.0
const HEAT_HOT := 70.0
const HOT_MULT := 1.2
const HEAT_IDLE := 0.8                   # seconds without attacking before the heat starts to fall
const HEAT_DECAY := 12.0                 # per second
const HEAT_PER_DAMAGE := 0.04            # heat per point of damage dealt (ultimate hits excluded)
const HEAT_KILL_DROP := 25.0             # a kill cools you down
const HEAT_SOAK_DROP := 45.0             # per second while standing in water
const SOAK_TIME := 3.0                   # seconds you stay "soaked" after leaving water: no ring, no lightning
const SOAK_DEPTH := 0.25                 # water this deep soaks you
const OVERHEAT_TIME := 2.0               # at 100% heat: no moves for this long, and slow
const OVERHEAT_MOVE_MULT := 0.5
const OVERHEAT_RESET := 50.0             # heat after an overheat ends
const FIRE_THAW_TIME := 0.5              # a firebender frozen solid thaws in this long
# LMB tap: fire punch (a short, quick fireball)
const FPUNCH_DAMAGE := 12.0
const FPUNCH_COOLDOWN := 0.28
const FPUNCH_SPEED := 38.0
const FPUNCH_LIFE := 0.32                # about 12 m
const FPUNCH_RADIUS := 0.5
const FPUNCH_KNOCK := 4.0
const FPUNCH_HEAT := 4.0
# LMB hold: flame jet (about 45 DPS, 7 m cone)
const FLAME_DPS := 45.0
const FLAME_RANGE := 7.0
const FLAME_CONE_COS := 0.88
const FLAME_PUSH := 3.0                  # gentle shove (m/s) so it does not pin anyone
const FLAME_HEAT := 14.0                 # per second
const FLAME_MOVE_MULT := 0.7
const FLAME_ICE_STEP := 0.4              # seconds between hits on an ice wall (ice melts: it breaks fast)
# RMB: fire whip
const FWHIP_DAMAGE := 22.0
const FWHIP_REACH := 6.0
const FWHIP_WIDTH := 0.9
const FWHIP_COOLDOWN := 0.9
const FWHIP_KNOCK := 7.0
const FWHIP_HEAT := 10.0
# Q: fire dash (burst of 12 m; one in the air per landing; ground cooldown)
const FDASH_DIST := 12.0
const FDASH_TIME := 0.16
const FDASH_COOLDOWN := 2.5
const FDASH_EXIT_SPEED := 11.0
const FDASH_HEAT := 8.0
# F: fire ring (the main defense): 360 degree burn + knockback, then a guard that destroys incoming projectiles
const RING_RADIUS := 6.0
const RING_DAMAGE := 30.0
const RING_KNOCK := 16.0
const RING_BURN_DPS := 5.0
const RING_BURN_TIME := 3.0
const RING_COOLDOWN := 6.0
const RING_HEAT := 18.0
const RING_GUARD_TIME := 2.2             # seconds of guard after the burst
const RING_GUARD_RADIUS := 3.6           # incoming (non-ultimate) projectiles inside this are burnt up
const RING_GUARD_TAKE := 0.3             # direct damage taken while the guard is up
# Z: flame arcs (3 crescents, toughness 2)
const FARC_DAMAGE := 16.0
const FARC_COUNT := 3
const FARC_SPREAD := 0.16
const FARC_SPEED := 30.0
const FARC_LIFE := 0.8
const FARC_RADIUS := 0.7
const FARC_KNOCK := 5.0
const FARC_COOLDOWN := 4.0
const FARC_HEAT := 14.0
# T: combustion beam: a fast beam, the blast comes COMBUST_DELAY later where it hit
const CBEAM_SPEED := 80.0
const CBEAM_LIFE := 0.55
const CBEAM_RADIUS := 0.35
const COMBUST_DELAY := 0.55
const COMBUST_RADIUS := 4.5
const COMBUST_DAMAGE := 45.0
const COMBUST_KNOCK := 12.0
const COMBUST_COOLDOWN := 14.0
const COMBUST_HEAT := 18.0
# X tap: Dragon Rush (steerable fire-jet flight, about 55 DPS to everything near the flame, 9 s)
const RUSH_TIME := 9.0
const RUSH_SPEED := 26.0
const RUSH_TURN := 2.6                   # rad/s the flight direction swings towards where you look
const RUSH_RADIUS := 3.2
const RUSH_DPS := 55.0
const RUSH_PUSH := 6.0
const RUSH_MIN_CLEARANCE := 1.2          # stays this far above the ground
# X hold: Lightning (about 2 s standing still and focused, then a bolt). Blocked by earth walls and earth armor.
const LIGHT_CHARGE := 2.0
const LIGHT_MIN_CHARGE := 0.8           # release after this and the bolt fires, scaled by the charge; earlier and it fizzles (meter kept)
const LIGHT_MIN_FRAC := 0.5              # damage at the minimum charge (100% at the full LIGHT_CHARGE)
const LIGHT_MOVE_MULT := 0.15
const LIGHT_RANGE := 90.0
const LIGHT_DAMAGE := 150.0
const LIGHT_SPLASH := 40.0
const LIGHT_SPLASH_RADIUS := 4.0
const LIGHT_WIDTH := 1.8                 # how close to the line a target must be
const LIGHT_WET_MULT := 1.3              # a target standing in water conducts: more damage
const LIGHT_ARMOR_COST := 40.0           # earth armor soaks the whole bolt and loses this much
# bots
const BOT_FIRE_BACKOFF_HEAT := 90.0
const BOT_FLAME_DPS := 30.0
const BOT_RING_DAMAGE := 20.0
const BOT_LIGHT_DAMAGE := 55.0
const BOT_BURN_FX_STEP := 0.1            # seconds between flame effect events from a bot's jet
const BOT_AI_FIRE_STEP := 0.2            # a fire duelist decides at most this often
