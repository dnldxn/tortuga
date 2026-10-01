class_name Ship3DView
extends Node2D
## A game-world Node2D backed by a transparent, fixed-camera 3D turntable.
## Navigation remains in the deterministic 2D simulation; only presentation lives here.

const Definitions := preload("res://sim/definitions.gd")
const MODEL_SCENES := {
	"sloop": preload("res://assets/ships/3d/sloop.glb"),
	"brig": preload("res://assets/ships/3d/brig.glb"),
	"frigate": preload("res://assets/ships/3d/frigate.glb"),
}
## Extra vertical framing prevents tall, wind-trimmed rigs from clipping during
## end-on turns and maximum rocking. Vertical camera size and pixels grow by the
## same 22/15 ratio; a little extra transparent width fits the sloop bowsprit.
const FIT_HEIGHT := {"sloop": 10.56, "brig": 13.3466667, "frigate": 15.84}
const CAMERA_TARGET_Y := {"sloop": 2.19, "brig": 2.84, "frigate": 3.18}
const TRIM_FACTORS := {
	"sloop": [1.0],
	"brig": [0.92, 1.0, 0.62],
	"frigate": [0.92, 1.0, 1.0],
}
const VIEWPORT_SIZE := Vector2i(208, 176)
const DISPLAY_REFERENCE_WIDTH := 192.0  # Horizontal padding must not shrink the model in game pixels.
const CAMERA_RISE := 8.1
const CAMERA_DISTANCE := 14.0  # atan(8.1 / 14) = 30 degrees above horizontal.
const FULL_SAIL_SCALE := Vector3.ONE
const REEFED_SAIL_SCALE := Vector3(0.72, 0.55, 0.72)
const SAIL_FULL := Color(0.96, 0.93, 0.84)
const SAIL_DAMAGED := Color(0.48, 0.42, 0.36)
const HULL_DAMAGED := Color(0.65, 0.5, 0.44)

var vessel_id := ""
var ship_viewport: SubViewport
var display_sprite: Sprite2D
var model_camera: Camera3D
var heading_pivot: Node3D
var motion_pivot: Node3D
var model_instance: Node3D
var sail_pivots: Array[Node3D] = []
var sail_surfaces: Array[MeshInstance3D] = []
var motion_phase := 0.0
var sail_trim := 0.0
var speed_ratio := 0.0

var _elapsed := 0.0
var _reefed := false
var _sail_base_scales: Array[Vector3] = []
var _sail_base_positions: Array[Vector3] = []
var _sail_top_local_y: Array[float] = []
var _sail_material := StandardMaterial3D.new()


func setup(id: String, radius: float) -> void:
	assert(MODEL_SCENES.has(id), "Unknown 3D vessel model: %s" % id)
	vessel_id = id
	set_meta("vessel_id", id)
	set_meta("ship_3d_view", true)
	_build_viewport()
	_build_model()
	_build_display(radius)
	_apply_sail_condition(1.0)


func _build_viewport() -> void:
	ship_viewport = SubViewport.new()
	ship_viewport.name = "ShipViewport"
	ship_viewport.size = VIEWPORT_SIZE
	ship_viewport.transparent_bg = true
	ship_viewport.own_world_3d = true
	ship_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	ship_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	ship_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(ship_viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.84, 0.88)
	environment.ambient_light_energy = 1.35
	var world_environment := WorldEnvironment.new()
	world_environment.name = "Environment"
	world_environment.environment = environment
	ship_viewport.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "WarmSun"
	sun.light_color = Color(1.0, 0.87, 0.67)
	sun.light_energy = 2.2
	sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	ship_viewport.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.name = "SeaRim"
	rim.light_color = Color(0.36, 0.77, 0.82)
	rim.light_energy = 0.8
	rim.rotation_degrees = Vector3(-22.0, 142.0, 0.0)
	ship_viewport.add_child(rim)

	model_camera = Camera3D.new()
	model_camera.name = "FixedCamera30Degrees"
	model_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	model_camera.size = FIT_HEIGHT[vessel_id]
	model_camera.near = 0.1
	model_camera.far = 60.0
	var target := Vector3(0.0, CAMERA_TARGET_Y[vessel_id], 0.0)
	model_camera.look_at_from_position(target + Vector3(0.0, CAMERA_RISE, CAMERA_DISTANCE), target, Vector3.UP)
	ship_viewport.add_child(model_camera)
	model_camera.current = true


func _build_model() -> void:
	heading_pivot = Node3D.new()
	heading_pivot.name = "HeadingPivot"
	ship_viewport.add_child(heading_pivot)
	motion_pivot = Node3D.new()
	motion_pivot.name = "GentleMotionPivot"
	heading_pivot.add_child(motion_pivot)
	model_instance = MODEL_SCENES[vessel_id].instantiate()
	model_instance.name = "Model"
	motion_pivot.add_child(model_instance)
	_collect_rig_nodes(model_instance)


func _collect_rig_nodes(node: Node) -> void:
	if node is Node3D and node.name.begins_with("SailPivot_"):
		sail_pivots.append(node)
	if node is MeshInstance3D and node.name.begins_with("SailSurface_"):
		sail_surfaces.append(node)
		_sail_base_scales.append(node.scale)
		_sail_base_positions.append(node.position)
		var sail_bounds: AABB = node.get_aabb()
		_sail_top_local_y.append(sail_bounds.position.y + sail_bounds.size.y)
		node.material_override = _sail_material
	for child in node.get_children():
		_collect_rig_nodes(child)


func _build_display(radius: float) -> void:
	display_sprite = Sprite2D.new()
	display_sprite.name = "RenderedShip"
	display_sprite.texture = ship_viewport.get_texture()
	var display_scale := 2.0 * radius / DISPLAY_REFERENCE_WIDTH
	display_sprite.scale = Vector2.ONE * display_scale
	# The camera frames the complete rig above the waterline. Offset the rendered
	# rectangle so the hull origin, rather than the mast center, sits on sim.position.
	var camera_up_y := CAMERA_DISTANCE / sqrt(CAMERA_DISTANCE * CAMERA_DISTANCE + CAMERA_RISE * CAMERA_RISE)
	var origin_offset_pixels: float = CAMERA_TARGET_Y[vessel_id] * camera_up_y * float(VIEWPORT_SIZE.y) / FIT_HEIGHT[vessel_id]
	display_sprite.position.y = -origin_offset_pixels * display_scale
	add_child(display_sprite)


func set_ship_state(heading: float, wind_heading: float, normalized_speed: float,
		is_reefed: bool, hull_fraction: float, sail_fraction: float) -> void:
	var model_heading := visual_yaw_for_heading(heading)
	heading_pivot.rotation.y = -model_heading
	speed_ratio = clampf(normalized_speed, 0.0, 1.0)
	sail_trim = _sail_trim(Definitions.wrap_angle(wind_heading - heading))
	for index in sail_pivots.size():
		var factor: float = TRIM_FACTORS[vessel_id][mini(index, TRIM_FACTORS[vessel_id].size() - 1)]
		var sail_heading := visual_yaw_for_heading(heading + sail_trim * factor)
		sail_pivots[index].rotation.y = -Definitions.wrap_angle(sail_heading - model_heading)
	if _reefed != is_reefed:
		_reefed = is_reefed
		for index in sail_surfaces.size():
			var sail_scale: Vector3 = _sail_base_scales[index] * (REEFED_SAIL_SCALE if _reefed else FULL_SAIL_SCALE)
			sail_surfaces[index].scale = sail_scale
			sail_surfaces[index].position = _sail_base_positions[index]
			# Reef upward from the foot while the head remains tied to its yard,
			# gaff, or stay. Child seam/reef lines follow the cloth transform.
			sail_surfaces[index].position.y += _sail_top_local_y[index] * (
				_sail_base_scales[index].y - sail_scale.y)
	display_sprite.modulate = Color.WHITE.lerp(HULL_DAMAGED, 1.0 - clampf(hull_fraction, 0.0, 1.0))
	_apply_sail_condition(sail_fraction)


func set_ship_active(active: bool) -> void:
	visible = active
	ship_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if active else SubViewport.UPDATE_DISABLED


func advance_motion(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	var amplitude := deg_to_rad(0.09 + speed_ratio * 0.58)
	var rate := 0.24 + speed_ratio * 0.25
	var wave := _elapsed * rate * TAU + motion_phase
	motion_pivot.rotation.x = sin(wave) * amplitude
	motion_pivot.rotation.z = sin(wave * 0.58 + 0.8) * amplitude * 0.38
	motion_pivot.position.y = sin(wave * 0.54) * (0.008 + speed_ratio * 0.038)


func _apply_sail_condition(fraction: float) -> void:
	_sail_material.albedo_color = SAIL_FULL.lerp(SAIL_DAMAGED, 1.0 - clampf(fraction, 0.0, 1.0))
	_sail_material.roughness = 0.94
	_sail_material.cull_mode = BaseMaterial3D.CULL_DISABLED


## Relative wind folds around headwind and caps the boom/yard angle at 68 degrees.
func _sail_trim(relative_wind: float) -> float:
	var sign_value := 1.0 if is_zero_approx(relative_wind) else signf(relative_wind)
	var folded := minf(absf(relative_wind), PI - absf(relative_wind))
	return sign_value * minf(deg_to_rad(68.0), folded * 0.68)


## The oblique camera halves depth on screen. This inverse projection keeps the
## rendered bow aligned with the 2D velocity vector at every compass heading.
func visual_yaw_for_heading(heading: float) -> float:
	var depth_projection := CAMERA_RISE / sqrt(CAMERA_DISTANCE * CAMERA_DISTANCE + CAMERA_RISE * CAMERA_RISE)
	return atan2(sin(heading) / depth_projection, cos(heading))
