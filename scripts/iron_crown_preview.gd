extends Node3D


@onready var reveal_camera: Camera3D = $RevealCamera


func _ready() -> void:
	reveal_camera.look_at(Vector3(0.0, 18.0, -48.0), Vector3.UP)
	if "--capture-iron-crown" in OS.get_cmdline_user_args():
		capture_after_render()


func capture_after_render() -> void:
	# Let the imported model, Forward+ lighting, and temporal effects settle.
	for _frame in range(12):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://art_direction/iron_crown/iron-crown-godot-preview-v1.png")
	if error != OK:
		push_error("Could not save Iron Crown preview: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("Saved live Godot preview")
	get_tree().quit()
