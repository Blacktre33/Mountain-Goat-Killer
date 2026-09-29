extends SceneTree
## Tiles the PNGs of one audit folder into 2x3 contact sheets so a whole route
## pass can be reviewed at a glance. Usage:
##   Godot --headless --path . --script res://tools/contact_sheet.gd -- <folder> [per_sheet]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var folder: String = args[0]
	var per_sheet := 6
	if args.size() > 1:
		per_sheet = int(args[1])
	var names: Array = []
	for file in DirAccess.get_files_at(folder):
		if (file.ends_with(".png") or file.ends_with(".jpg")) and not file.begins_with("sheet_"):
			names.append(file)
	names.sort()
	var tile := Vector2i(640, 360)
	var sheet_index := 0
	var i := 0
	while i < names.size():
		var sheet := Image.create(tile.x * 2, tile.y * 3, false, Image.FORMAT_RGB8)
		for slot in per_sheet:
			if i >= names.size():
				break
			var image := Image.load_from_file(folder + "/" + names[i])
			image.convert(Image.FORMAT_RGB8)
			image.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, tile), Vector2i((slot % 2) * tile.x, (slot / 2) * tile.y))
			print("sheet_%02d slot %d = %s" % [sheet_index, slot, names[i]])
			i += 1
		sheet.save_png(folder + "/sheet_%02d.png" % sheet_index)
		sheet_index += 1
	quit()
