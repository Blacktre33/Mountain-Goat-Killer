extends SceneTree
## The moon is part of the sky (no sprite), points where the Moonlight arrives
## from, and biome changes tween the atmosphere instead of popping.


func _init() -> void:
	call_deferred("run_test")


func fail(message: String) -> void:
	push_error(message)
	quit(1)


func run_test() -> void:
	var main_scene: Node = load("res://main.tscn").instantiate()
	root.add_child(main_scene)
	await process_frame
	var world: WorldBuilder.Built = main_scene.world

	if world.root.find_child("MoonDisc", true, false) != null:
		fail("A billboard moon sprite is back; the moon must live in the sky shader")
		return
	var sky_direction: Vector3 = world.sky_shader.get_shader_parameter("moon_dir")
	var light_direction: Vector3 = world.moon.global_transform.basis.z
	if sky_direction.dot(light_direction) < 0.999:
		fail("Sky moon direction %s disagrees with the Moonlight %s" % [sky_direction, light_direction])
		return
	if world.environment.sky == null or world.sky_shader.shader == null:
		fail("Environment lost its sky shader")
		return

	WorldBuilder.set_biome(world, "whitewood", true)
	var start_fog: Color = world.environment.fog_light_color
	var target_fog: Color = WorldBuilder.ATMOSPHERES["carrion_cut"]["fog_color"]
	WorldBuilder.set_biome(world, "carrion_cut")
	if world.environment.fog_light_color != start_fog:
		fail("Biome change popped instead of tweening")
		return
	await create_timer(WorldBuilder.BIOME_BLEND_SECONDS * 0.5).timeout
	var halfway: Color = world.environment.fog_light_color
	if halfway.is_equal_approx(start_fog) or halfway.is_equal_approx(target_fog):
		fail("Biome tween has no intermediate state: %s" % halfway)
		return
	await create_timer(WorldBuilder.BIOME_BLEND_SECONDS * 0.6).timeout
	if not world.environment.fog_light_color.is_equal_approx(target_fog):
		fail("Biome tween did not settle on the Carrion Cut fog")
		return
	if world.ash.amount_ratio < 0.7:
		fail("Carrion Cut has no ash drift")
		return

	# Interrupting a blend must continue from the current mix, never restart.
	WorldBuilder.set_biome(world, "iron_crown")
	await create_timer(0.5).timeout
	WorldBuilder.set_biome(world, "whitewood", true)
	if not world.environment.fog_light_color.is_equal_approx(WorldBuilder.ATMOSPHERES["whitewood"]["fog_color"]):
		fail("Instant biome set did not apply exactly")
		return
	print("Sky atmosphere test passed")
	main_scene.audio.shutdown()
	await create_timer(0.2).timeout
	quit()
