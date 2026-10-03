extends RefCounted
## Centralized starting-balance data (tuning values, not measurements).

const ARENA_SIZE := Vector2(6000, 4200)
const ARENA_MARGIN := 160.0

## Reef Glass presentation tuning; never used by simulation movement or contacts.
const PRESENTATION := {
	"zoom_multiplier": 2.0, "zoom_min": 1.5, "zoom_max": 2.2,
	"ship_near_angle": 70.0, "ship_far_angle": 30.0, "ship_angle_distance": 800.0,
	"ui_margin": 12.0, "top_reserved": 160.0, "bottom_reserved": 160.0,
	"combat_inset": 24.0, "side_reserved": 32.0,
	"art_padding": 24.0, "player_padding": 80.0, "readiness_spacing": 9.0,
	"readiness_radius": 3.0, "readiness_offset": 12.0,
	"readiness_font": 18,
	"arc_height": 12.0, "arc_close": 35.0, "arc_full": 180.0,
	"arc_default_range": .45, "muzzle_blend_distance": 45.0, "muzzle_max_correction": 32.0,
	"smoke_ticks": 60, "smoke_radius": 10.0, "smoke_drift": 12.0,
	# Four Galleons plus opposition: both batteries, impacts and fading smoke.
	"cue_capacity": 512, "cannon_voices": 64,
	"cannon_db": -40.0, "cannon_pitch_variation": .025,
	"cannon_level_variation": .6, "chain_rotation_per_unit": .10,
	"audio_pan_extent": .55, "audio_distance": 1400.0, "audio_far_gain": .65,
}

const WATER := {
	"animation_speed": 0.75,
	"drift_speed": 0.1,
	"world_scale": 144.0,  # World pixels per shader unit; independent of camera/viewport.
	"shallow_fade": 600.0,
	"swell_weights": Vector3(0.34, 0.16, 0.060),
	"texture_weight": 0.12,
	"whitecap_lifetime": Vector2(4.0, 8.0),  # Animation seconds, before speed scaling.
}

const VESSELS := {
	"sloop": {
		"display_name": "Sloop",
		"description": "Fastest, tightest turns, light protection",
		"full_speed": 116.64, "turn_rate": 1.2,
		"hull": 100.0, "sails": 70.0, "crew": 60.0,
		"guns_per_side": 4, "base_reload": 7.0, "radius": 27.5,
	},
	"brig": {
		"display_name": "Brig",
		"description": "Balanced handling and protection",
		"full_speed": 93.96, "turn_rate": 0.85,
		"hull": 160.0, "sails": 100.0, "crew": 90.0,
		"guns_per_side": 6, "base_reload": 8.0, "radius": 35.0,
	},
	"frigate": {
		"display_name": "Frigate",
		"description": "Slow, wide turns, heavy protection",
		"full_speed": 71.28, "turn_rate": 0.6,
		"hull": 240.0, "sails": 140.0, "crew": 140.0,
		"guns_per_side": 8, "base_reload": 9.0, "radius": 42.5,
	},
	"galleon": {
		"display_name": "Galleon",
		"description": "Largest hull, two gun decks, slowest turns",
		"full_speed": 55.08, "turn_rate": 0.45,
		"hull": 360.0, "sails": 190.0, "crew": 220.0,
		"guns_per_side": 16, "guns_per_row": 8, "base_reload": 11.0, "radius": 55.25,
	},
}

## Heading 0 = east, positive = clockwise. Wind heading is the direction the wind travels.
const PRESETS := {
	"practice": {
		"player_position": Vector2(2500, 2100),
		"player_heading": 0.0,
		"wind_heading": 0.0,
		## Non-player ships built by reset. team 1 = opposition. A practice_target never
		## sails or acts on commands, but takes damage and is pushed by contact.
		"opposition": [
			{"id": 2, "team": 1, "vessel_id": "brig", "position": Vector2(3000, 2100), "heading": 0.0, "role": "practice_target"},
		],
	},
	## Fixed AI duels (plan 03): one team-1 opponent that sails, steers and fights
	## like the player (role "ship", never practice_target).
	"duel_sloop": {
		"label": "Sloop duel",
		"player_position": Vector2(2500, 2100),
		"player_heading": 0.0,
		"wind_heading": 0.0,
		"opposition": [
			{"id": 2, "team": 1, "vessel_id": "sloop", "position": Vector2(3500, 2100), "heading": PI, "role": "ship"},
		],
	},
	"duel_brig": {
		"label": "Brig duel",
		"player_position": Vector2(3000, 1500),
		"player_heading": PI / 2.0,
		"wind_heading": 0.0,
		"opposition": [
			{"id": 2, "team": 1, "vessel_id": "brig", "position": Vector2(3000, 2500), "heading": -PI / 2.0, "role": "ship"},
		],
	},
	"duel_frigate": {
		"label": "Frigate duel",
		"player_position": Vector2(2500, 2100),
		"player_heading": 0.0,
		"wind_heading": PI / 4.0,
		"opposition": [
			{"id": 2, "team": 1, "vessel_id": "frigate", "position": Vector2(3500, 2100), "heading": PI, "role": "ship"},
		],
	},
	"two_sloops": {
		"label": "Two-ship encounter",
		"player_position": Vector2(2400, 2100),
		"player_heading": 0.0,
		"wind_heading": 0.0,
		"opposition": [
			{"id": 2, "team": 1, "vessel_id": "sloop", "position": Vector2(3400, 1700), "heading": PI, "role": "ship"},
			{"id": 3, "team": 1, "vessel_id": "sloop", "position": Vector2(3400, 2500), "heading": PI, "role": "ship"},
		],
	},
	## Group presets (Phase 3): multiplayer only, never in the offline menu. Beam wind, AI ships
	## 600-1000 apart; player_position/heading is the first captain's spot, beyond ESCAPE_DISTANCE.
	"brig_squadron": {
		"label": "Brig squadron",
		"multiplayer_only": true,
		"player_position": Vector2(2200, 2100),
		"player_heading": 0.0,
		"wind_heading": PI / 2.0,
		"opposition": [
			{"id": 2, "team": 1, "vessel_id": "brig", "position": Vector2(3900, 1500), "heading": PI, "role": "ship"},
			{"id": 3, "team": 1, "vessel_id": "brig", "position": Vector2(3900, 2100), "heading": PI, "role": "ship"},
			{"id": 4, "team": 1, "vessel_id": "brig", "position": Vector2(3900, 2700), "heading": PI, "role": "ship"},
		],
	},
	"frigate_escort": {
		"label": "Frigate escort",
		"multiplayer_only": true,
		"player_position": Vector2(2200, 2100),
		"player_heading": 0.0,
		"wind_heading": -PI / 2.0,
		"opposition": [
			{"id": 2, "team": 1, "vessel_id": "frigate", "position": Vector2(4100, 2100), "heading": PI, "role": "ship"},
			{"id": 3, "team": 1, "vessel_id": "sloop", "position": Vector2(3700, 1600), "heading": PI, "role": "ship"},
			{"id": 4, "team": 1, "vessel_id": "sloop", "position": Vector2(3700, 2600), "heading": PI, "role": "ship"},
		],
	},
}

## Multiplayer battles (Phase 3): presets a battle may use (never "practice").
const BATTLE_PRESETS: Array[String] = ["duel_sloop", "duel_brig", "duel_frigate", "two_sloops", "brig_squadron", "frigate_escort"]
const MAX_CAPTAINS := 4  # per server; Plan 02 enforces both caps
const MAX_BATTLES := 4  # concurrent battles per server
const LINGER_SECONDS := 30.0  # battle-time grace for a left/dropped captain's ship
const DROP_IN := {"margin": 200.0}  # spawn this far beyond the longest gun range (~2 s of a closing brig)


## Speed multiplier at 0/45/90/135/180 degrees off downwind; linear between knots.
const WIND_KNOTS: Array[float] = [0.8, 1.0, 0.95, 0.45, 0.12]
const REEF_SPEED_FACTOR := 0.65
const REEF_TURN_FACTOR := 1.4

## Each ammo type damages exactly one track. Speed in units/s, range in units.
const AMMO := {
	"round": {"display_name": "Round", "range": 900.0, "speed": 345.6, "damage": 8.0, "track": "hull"},
	"chain": {"display_name": "Chain", "range": 600.0, "speed": 288.0, "damage": 6.0, "track": "sails"},
	"grape": {"display_name": "Grape", "range": 300.0, "speed": 259.2, "damage": 5.0, "track": "crew"},
}
const AMMO_CYCLE: Array[String] = ["round", "chain", "grape"]

## Deliberate escape (plan 04), ship-center distances. Arm at <= ARM of ANY active enemy;
## escape after ESCAPE_SECONDS continuously > ESCAPE_DISTANCE from EVERY active enemy.
## ESCAPE_DISTANCE must exceed the longest AMMO range.
const ESCAPE_ARM_DISTANCE := 900.0
const ESCAPE_DISTANCE := 1400.0
const ESCAPE_SECONDS := 8.0
const SIDES: Array[String] = ["port", "starboard"]  # port = heading - PI/2, starboard = heading + PI/2
## Guns fire straight off the beam (no aim assist), spaced evenly along the keel over
## +/- GUN_SPREAD * radius from the ship center; gun 0 is nearest the bow.
const GUN_SPREAD := 0.7

## Opposition AI tuning: initial, unmeasured values. Radii/angles in world units/radians.
const AI := {
	"orbit_radius": {"round": 520.0, "chain": 380.0, "grape": 190.0},
	"radial_gain": 160.0,
	"radial_clamp": 2.0,
	"turn_dead": 3.0 * PI / 180.0,
	"turn_gain": 0.35,
	"reef_error": 35.0 * PI / 180.0,
	"full_sail_error": 15.0 * PI / 180.0,
	"candidate_stable_s": 1.0,
	"switch_cooldown_s": 10.0,
	"ammo_range_factor": 0.9,
	"grape_crew_fraction": 0.65,
	"chain_sail_fraction": 0.65,
	"speed_ratio": 1.15,
	"chain_healthy_sail_fraction": 0.45,
	"fire_bearing": 4.0 * PI / 180.0,  # no aim assist: fire only when the target is near the beam
	# Avoidance/recovery tuning (plan 03 task 4; shared extension point for plan 05).
	"look_ahead_s": 0.75,
	"ship_clearance": 60.0,
	"boundary_inset": 50.0,
	"contact_margin": 6.0,
	"progress_window_s": 1.0,
	"stuck_displacement": 8.0,
	"stuck_min_speed": 20.0,
	"recovery_minimum_s": 1.5,
	"recovery_exit_separation": 100.0,
	"recovery_inset": 150.0,
	"avoid_bias": 0.5,
	# Targeting: keep the current target unless another enemy is closer than ratio x its distance.
	"retarget_ratio": 0.7,
}


## Wraps an angle into [-PI, PI).
static func wrap_angle(angle: float) -> float:
	return fposmod(angle + PI, TAU) - PI


static func wind_multiplier(heading: float, wind_heading: float) -> float:
	var off_wind := absf(wrap_angle(heading - wind_heading))  # 0 = downwind, PI = upwind
	var pos := off_wind / (PI / 4.0)
	var i := mini(int(pos), WIND_KNOTS.size() - 2)
	return lerpf(WIND_KNOTS[i], WIND_KNOTS[i + 1], pos - i)


## Allowed ship-center area for a ship of the given radius.
static func safe_bounds(radius: float) -> Rect2:
	var inset := ARENA_MARGIN + radius
	return Rect2(Vector2(inset, inset), ARENA_SIZE - Vector2(inset, inset) * 2.0)
