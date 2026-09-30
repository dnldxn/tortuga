extends Node2D
## World-anchored, read-only water presentation. ArenaView supplies fixed ticks and wind.
## Explicit time/drift uniforms freeze with gameplay; shader TIME would keep running.

const Definitions := preload("res://sim/definitions.gd")
const WATER_SHADER := preload("res://view/reef_glass.gdshader")

var animation_time := 0.0
var drift := Vector2.ZERO
var water_material := ShaderMaterial.new()


func _ready() -> void:
	show_behind_parent = true
	water_material.shader = WATER_SHADER
	material = water_material
	for parameter in ["world_scale", "shallow_fade", "swell_weights", "texture_weight", "whitecap_lifetime"]:
		water_material.set_shader_parameter(parameter, Definitions.WATER[parameter])
	water_material.set_shader_parameter("arena_size", Definitions.ARENA_SIZE)
	reset(0.0)


func set_wind(heading: float) -> void:
	water_material.set_shader_parameter("wind_direction", Vector2.from_angle(heading))


func advance(dt: float, heading: float) -> void:
	var elapsed: float = dt * Definitions.WATER["animation_speed"]
	animation_time += elapsed
	drift += Vector2.from_angle(heading) * elapsed * Definitions.WATER["drift_speed"]
	set_wind(heading)
	_sync_animation()


func reset(heading: float) -> void:
	animation_time = 0.0
	drift = Vector2.ZERO
	set_wind(heading)
	_sync_animation()


func _sync_animation() -> void:
	water_material.set_shader_parameter("animation_time", animation_time)
	water_material.set_shader_parameter("surface_drift", drift)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Definitions.ARENA_SIZE), Color.WHITE)
