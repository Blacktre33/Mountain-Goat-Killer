extends SceneTree
## Regenerates default_bus_layout.tres from GoatAudio.configure_buses().
## Run: Godot --headless --path . --script res://tools/audio/build_bus_layout.gd
## (Delete the existing layout's extra buses first if you change the tree: the
## function only adds what is missing.)


func _init() -> void:
	# Start from a clean bus tree so the saved layout is exactly the code's.
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	while AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.remove_bus_effect(0, 0)
	GoatAudio.configure_buses()
	var layout := AudioServer.generate_bus_layout()
	var error := ResourceSaver.save(layout, "res://default_bus_layout.tres")
	print("Saved default_bus_layout.tres (%d buses): %s" % [AudioServer.bus_count, error_string(error)])
	quit(0 if error == OK else 1)
