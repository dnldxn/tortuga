extends RefCounted

const ShipView := preload("res://view/ship_3d_view.gd")
const Definitions := preload("res://sim/definitions.gd")


func run(t) -> bool:
	for vessel in ["sloop", "brig", "frigate"]:
		var view = ShipView.new()
		t.root.add_child(view)
		view.position = Vector2(310, -140)
		view.setup(vessel, Definitions.VESSELS[vessel]["radius"])
		var count: int = {"sloop": 4, "brig": 6, "frigate": 8}[vessel]
		for side in ["port", "starboard"]:
			t.check(view.muzzle_markers[side].size() == count, "%s %s exported gun count" % [vessel, side])
			var previous_x := INF
			for index in count:
				var marker: Node3D = view.muzzle_markers[side][index]
				t.check(marker != null and not marker is MeshInstance3D and marker.name == "Muzzle_%s_%d" % [side, index], "named lightweight muzzle survives batching")
				t.check(marker.position.x < previous_x and marker.position.z * (1 if side == "starboard" else -1) > 0, "muzzle index bow to stern on correct hull side")
				previous_x = marker.position.x
		for heading in [0.0, PI / 4.0, PI / 2.0, PI, -PI / 2.0, -PI / 4.0]:
			var full_positions := []
			for reefed in [false, true]:
				view.set_ship_state(heading, 0.7, 0.8, reefed, 1.0, 1.0)
				for side in ["port", "starboard"]:
					for index in count:
						var marker: Node3D = view.muzzle_markers[side][index]
						var projected: Vector2 = view.muzzle_position(side, index)
						# Independent orthographic projection from camera axes and world span.
						var relative: Vector3 = marker.global_position - view.model_camera.global_position
						var basis: Basis = view.model_camera.global_basis
						var pixels_per_unit: float = float(view.VIEWPORT_SIZE.y) / view.model_camera.size
						var expected: Vector2 = view.display_sprite.to_global(Vector2(relative.dot(basis.x), -relative.dot(basis.y)) * pixels_per_unit)
						t.check(projected.distance_to(expected) < 0.001, "%s %s %d heading %.2f reef %s projects barrel tip to arena" % [vessel, side, index, heading, reefed])
						if reefed:
							var flat_index: int = index + (count if side == "starboard" else 0)
							t.check(projected.distance_to(full_positions[flat_index]) < 0.001, "reefing preserves hull muzzle mapping")
						else:
							full_positions.append(projected)
		var before: Vector2 = view.muzzle_position("port", 0)
		view.advance_motion(0.37)
		t.check(view.muzzle_position("port", 0).distance_to(before) > 0.00001, "muzzle follows gentle motion")
		view.position += Vector2(51, 27)
		t.check(view.muzzle_position("port", 0).is_finite(), "muzzle remains finite after ship translation")
		t.check(view.muzzle_position("bad", 0) == view.global_position and view.muzzle_position("port", -1) == view.global_position and view.muzzle_position("starboard", count) == view.global_position, "invalid muzzle request falls back to ship position")
		view.free()
	return true
