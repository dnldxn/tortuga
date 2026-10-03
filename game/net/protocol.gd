extends RefCounted
## Wire protocol shared by the dedicated server and clients (Phase 3 plan 02). All static.
## No RPCs: everything travels as send_bytes packets whose byte 0 is the kind.
## KIND_MESSAGE: var_to_bytes(Dictionary with a String "t"). KIND_SNAPSHOT: compact little-endian
## battle snapshot (see encode_snapshot). Decoders never allow object decoding.
##
## Reasons:
##   auth:               version_mismatch | wrong_password | server_full | bad_request
##   refused:            battle_cap | no_reentry | unknown_battle | already_in_battle | bad_request
##   connection_ended:   server_stopped | connection_lost | replaced
## A preset is valid when `preset_id is String and preset_id in Definitions.BATTLE_PRESETS`.

const Definitions := preload("res://sim/definitions.gd")

const DEFAULT_PORT := 24680
const CHANNEL_RELIABLE := 0
const CHANNEL_UNRELIABLE := 1
const KIND_MESSAGE := 0
const KIND_SNAPSHOT := 1
const SNAPSHOT_EVERY_TICKS := 3  # 20 Hz
const STEER_STALE_MS := 500
const HARBOR_REFRESH_TICKS := 60
const MAX_PEERS := 8  # room to refuse or replace
const TIMEOUT_LIMIT := 32
const TIMEOUT_MIN_MS := 2000
const TIMEOUT_MAX_MS := 4000  # set_timeout on every peer: a silent peer is gone in < 5 s
const CONNECT_TIMEOUT_MS := 5000
const NAME_MAX := 24
const CAPTAIN_ID_MAX := 64
const ACTION_QUEUE_MAX := 64
const ACTIONS: Array[String] = ["fire_port", "fire_starboard", "cycle_port", "cycle_starboard", "toggle_sails"]
const ROLES: Array[String] = ["ship", "practice_target"]
const VESSEL_IDS: Array[String] = ["sloop", "brig", "frigate", "galleon"]

const FLAG_REEFED := 1
const FLAG_ACTIVE := 2
const FLAG_LINGERING := 4
const FLAG_ESCAPE_ARMED := 8
const DEFEAT_REASONS: Array[String] = ["sunk", "sails", "crew"]  # bits 1, 2, 4
const SHIP_FIXED_BYTES := 4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 2 + 2 + 7 * 4
const PROJECTILE_BYTES := 4 + 4 + 1 + 4 + 4


static func build_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("res://version.cfg") != OK:
		return "dev"
	return str(cfg.get_value("build", "version", "dev"))


static func encode_message(msg: Dictionary) -> PackedByteArray:
	var bytes := PackedByteArray([KIND_MESSAGE])
	bytes.append_array(var_to_bytes(msg))
	return bytes


## {} unless kind 0 carrying a Dictionary with a String "t".
static func decode_message(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 2 or bytes[0] != KIND_MESSAGE:
		return {}
	var value = bytes_to_var(bytes.slice(1))
	if not (value is Dictionary) or not (value.get("t") is String):
		return {}
	return value


static func _load_byte(load_value: float) -> int:
	return 255 if load_value == 1.0 else mini(254, floori(load_value * 255.0))


static func _load_value(b: int) -> float:
	return 1.0 if b == 255 else b / 255.0


## Header, ships (ascending id), projectiles (ascending id). Returns an empty array (after a
## push_error) if a role, vessel or ammo is unknown.
static func encode_snapshot(battle_id: int, sim, tick: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(KIND_SNAPSHOT)
	buf.put_u32(battle_id)
	buf.put_u32(tick)
	buf.put_float(sim.elapsed)
	buf.put_float(sim.wind_heading)
	var preset: PackedByteArray = sim.preset_id.to_utf8_buffer()
	buf.put_u8(preset.size())
	buf.put_data(preset)
	var ids: Array = sim.ships.keys()
	ids.sort()
	buf.put_u8(ids.size())
	for id in ids:
		var ship: Dictionary = sim.ships[id]
		var role := ROLES.find(ship["role"])
		var vessel := VESSEL_IDS.find(ship["vessel_id"])
		var port_ammo := Definitions.AMMO_CYCLE.find(ship["weapons"]["port"]["ammo"])
		var starboard_ammo := Definitions.AMMO_CYCLE.find(ship["weapons"]["starboard"]["ammo"])
		if role < 0 or vessel < 0 or port_ammo < 0 or starboard_ammo < 0:
			push_error("encode_snapshot: unknown role/vessel/ammo on ship %d" % id)
			return PackedByteArray()
		var flags := 0
		flags |= FLAG_REEFED if ship["reefed"] else 0
		flags |= FLAG_ACTIVE if ship["active"] else 0
		flags |= FLAG_LINGERING if ship["lingering"] else 0
		flags |= FLAG_ESCAPE_ARMED if ship["escape_armed"] else 0
		var defeat := 0
		for i in DEFEAT_REASONS.size():
			if DEFEAT_REASONS[i] in ship["defeat_reasons"]:
				defeat |= 1 << i
		buf.put_32(id)
		buf.put_u8(ship["team"])
		buf.put_u8(role)
		buf.put_u8(vessel)
		buf.put_u8(flags)
		buf.put_u8(defeat)
		buf.put_u8(port_ammo)
		buf.put_u8(starboard_ammo)
		buf.put_u16(clampi(ship["escape_clear_ticks"], 0, 65535))
		buf.put_u16(clampi(ship["linger_ticks"], 0, 65535))
		var position: Vector2 = ship["position"]
		buf.put_float(position.x)
		buf.put_float(position.y)
		buf.put_float(ship["heading"])
		buf.put_float(ship["speed"])
		buf.put_float(ship["hull"])
		buf.put_float(ship["sails"])
		buf.put_float(ship["crew"])
		for side in Definitions.SIDES:
			for load_value in ship["weapons"][side]["loads"]:
				buf.put_u8(_load_byte(load_value))
	var shots: Array = sim.projectiles.duplicate()
	shots.sort_custom(func(a, b): return a["id"] < b["id"])
	buf.put_u16(shots.size())
	for shot in shots:
		var ammo := Definitions.AMMO_CYCLE.find(shot["ammo"])
		if ammo < 0:
			push_error("encode_snapshot: unknown ammo on projectile %d" % shot["id"])
			return PackedByteArray()
		var position: Vector2 = shot["position"]
		buf.put_u32(shot["id"])
		buf.put_32(shot["owner_id"])
		buf.put_u8(ammo)
		buf.put_float(position.x)
		buf.put_float(position.y)
	return buf.data_array


static func _left(buf: StreamPeerBuffer) -> int:
	return buf.get_size() - buf.get_position()


## {} if the kind is wrong, the bytes are short, malformed or have trailing bytes.
static func decode_snapshot(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 1 + 4 + 4 + 4 + 4 + 1 + 1 + 2 or bytes[0] != KIND_SNAPSHOT:
		return {}
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	buf.get_u8()
	var snap := {"battle_id": buf.get_u32(), "tick": buf.get_u32(), "elapsed": buf.get_float(),
		"wind_heading": buf.get_float()}
	var preset_len := buf.get_u8()
	if _left(buf) < preset_len + 1:
		return {}
	snap["preset_id"] = buf.get_data(preset_len)[1].get_string_from_utf8()
	var ship_count := buf.get_u8()
	var ships := {}
	for _i in ship_count:
		if _left(buf) < SHIP_FIXED_BYTES:
			return {}
		var id := buf.get_32()
		var team := buf.get_u8()
		var role := buf.get_u8()
		var vessel := buf.get_u8()
		var flags := buf.get_u8()
		var defeat := buf.get_u8()
		var port_ammo := buf.get_u8()
		var starboard_ammo := buf.get_u8()
		if role >= ROLES.size() or vessel >= VESSEL_IDS.size() \
				or port_ammo >= Definitions.AMMO_CYCLE.size() or starboard_ammo >= Definitions.AMMO_CYCLE.size():
			push_error("decode_snapshot: unknown role/vessel/ammo index")
			return {}
		var escape_clear_ticks := buf.get_u16()
		var linger_ticks := buf.get_u16()
		var position := Vector2(buf.get_float(), buf.get_float())
		var heading := buf.get_float()
		var speed := buf.get_float()
		var hull := buf.get_float()
		var sails := buf.get_float()
		var crew := buf.get_float()
		var vessel_id := VESSEL_IDS[vessel]
		var guns: int = Definitions.VESSELS[vessel_id]["guns_per_side"]
		if _left(buf) < guns * 2:
			return {}
		var reasons := []
		for i in DEFEAT_REASONS.size():
			if defeat & (1 << i):
				reasons.append(DEFEAT_REASONS[i])
		var weapons := {}
		var ammo_ids := [port_ammo, starboard_ammo]
		for s in Definitions.SIDES.size():
			var loads := []
			for _g in guns:
				loads.append(_load_value(buf.get_u8()))
			weapons[Definitions.SIDES[s]] = {"ammo": Definitions.AMMO_CYCLE[ammo_ids[s]], "loads": loads}
		ships[id] = {
			"id": id, "team": team, "role": ROLES[role], "vessel_id": vessel_id,
			"position": position, "heading": heading, "speed": speed,
			"reefed": flags & FLAG_REEFED != 0, "hull": hull, "sails": sails, "crew": crew,
			"active": flags & FLAG_ACTIVE != 0, "defeat_reasons": reasons, "weapons": weapons,
			"escape_armed": flags & FLAG_ESCAPE_ARMED != 0, "escape_clear_ticks": escape_clear_ticks,
			"lingering": flags & FLAG_LINGERING != 0, "linger_ticks": linger_ticks,
		}
	snap["ships"] = ships
	if _left(buf) < 2:
		return {}
	var shot_count := buf.get_u16()
	if _left(buf) != shot_count * PROJECTILE_BYTES:
		return {}
	var projectiles := []
	for _i in shot_count:
		var shot_id := buf.get_u32()
		var owner_id := buf.get_32()
		var ammo := buf.get_u8()
		if ammo >= Definitions.AMMO_CYCLE.size():
			push_error("decode_snapshot: unknown ammo index")
			return {}
		projectiles.append({"id": shot_id, "owner_id": owner_id, "ammo": Definitions.AMMO_CYCLE[ammo],
			"position": Vector2(buf.get_float(), buf.get_float())})
	snap["projectiles"] = projectiles
	return snap


## The turn command to apply: clamped to -1..1, 0 once older than STEER_STALE_MS.
static func steer_turn(turn: int, received_ms: int, now_ms: int) -> int:
	if now_ms - received_ms > STEER_STALE_MS:
		return 0
	return clampi(turn, -1, 1)


## "--k v" -> {k: "v"}; a bare "--k" (last, or followed by another option) -> {k: true}.
static func parse_cli(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg.begins_with("--") and arg.length() > 2:
			var key := arg.substr(2)
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				out[key] = args[i + 1]
				i += 1
			else:
				out[key] = true
		i += 1
	return out


static func result_hash(result: Dictionary) -> String:
	return JSON.stringify(result, "", true).sha256_text()
