extends RefCounted
## Centralized starting-balance data (tuning values, not measurements).

const ARENA_SIZE := Vector2(6000, 4200)
const ARENA_MARGIN := 160.0

const VESSELS := {
	"sloop": {
		"display_name": "Sloop",
		"description": "Fastest, tightest turns, light protection",
		"full_speed": 180.0, "turn_rate": 1.2,
		"hull": 100.0, "sails": 70.0, "crew": 60.0,
		"guns_per_side": 4, "base_reload": 7.0, "radius": 22.0,
	},
	"brig": {
		"display_name": "Brig",
		"description": "Balanced handling and protection",
		"full_speed": 145.0, "turn_rate": 0.85,
		"hull": 160.0, "sails": 100.0, "crew": 90.0,
		"guns_per_side": 6, "base_reload": 8.0, "radius": 28.0,
	},
	"frigate": {
		"display_name": "Frigate",
		"description": "Slow, wide turns, heavy protection",
		"full_speed": 110.0, "turn_rate": 0.6,
		"hull": 240.0, "sails": 140.0, "crew": 140.0,
		"guns_per_side": 8, "base_reload": 9.0, "radius": 34.0,
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
}


## Speed multiplier at 0/45/90/135/180 degrees off downwind; linear between knots.
const WIND_KNOTS: Array[float] = [0.8, 1.0, 0.95, 0.45, 0.12]
const REEF_SPEED_FACTOR := 0.65
const REEF_TURN_FACTOR := 1.4

## Each ammo type damages exactly one track. Speed in units/s, range in units.
const AMMO := {
	"round": {"display_name": "Round", "range": 900.0, "speed": 600.0, "damage": 8.0, "track": "hull"},
	"chain": {"display_name": "Chain", "range": 600.0, "speed": 500.0, "damage": 6.0, "track": "sails"},
	"grape": {"display_name": "Grape", "range": 300.0, "speed": 450.0, "damage": 5.0, "track": "crew"},
}
const AMMO_CYCLE: Array[String] = ["round", "chain", "grape"]
const SIDES: Array[String] = ["port", "starboard"]  # port = heading - PI/2, starboard = heading + PI/2
const ARC_HALF_ANGLE := 12.0 * PI / 180.0  # aim-assist cone around each broadside


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
