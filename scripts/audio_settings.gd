class_name GoatAudioSettings
extends VBoxContainer
## Volume sliders and the subtitle switch for the pause menu. One line wires it:
##     pause_overlay.add_child(GoatAudioSettings.create(audio))
## Changes apply immediately and persist in user://audio.cfg.

const LABELS := {"master": "MASTER", "music": "MUSIC", "sfx": "EFFECTS", "ambience": "AMBIENCE", "voice": "VOICE", "ui": "INTERFACE"}
const TEXT_COLOR := Color("d9dde3")

var audio: GoatAudio
var sliders := {}
var subtitle_toggle: CheckBox


static func create(target: GoatAudio) -> GoatAudioSettings:
	var panel := GoatAudioSettings.new()
	panel.audio = target
	return panel


func _ready() -> void:
	name = "AudioSettings"
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -190.0
	offset_right = 190.0
	offset_top = -290.0
	offset_bottom = -40.0
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "AUDIO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	add_child(title)
	for channel in GoatAudio.CHANNELS:
		add_child(_row(channel))
	subtitle_toggle = CheckBox.new()
	subtitle_toggle.text = "SUBTITLES"
	subtitle_toggle.button_pressed = audio.subtitles_enabled
	subtitle_toggle.focus_mode = Control.FOCUS_NONE
	subtitle_toggle.add_theme_color_override("font_color", TEXT_COLOR)
	subtitle_toggle.toggled.connect(func(on: bool) -> void: audio.set_subtitles_enabled(on))
	add_child(subtitle_toggle)


func _row(channel: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = LABELS[channel]
	name_label.custom_minimum_size = Vector2(100.0, 0.0)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = audio.get_bus_volume(channel)
	slider.custom_minimum_size = Vector2(190.0, 22.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float) -> void: audio.set_bus_volume(channel, value))
	row.add_child(slider)
	sliders[channel] = slider
	return row
