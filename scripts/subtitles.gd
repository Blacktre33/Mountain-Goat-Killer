class_name GoatSubtitles
extends CanvasLayer
## Small bottom-centre subtitle strip for spoken lines. GoatAudio creates and
## binds one; it shows the Herdkeeper's narration, Varkas' taunts (amber) and
## nearby warpack barks (steel), and can be switched off in the audio settings.

const LAYER := 90
const BARK_HEARING := 30.0
const STYLES := {
	"keeper": {"prefix": "", "color": Color("e8ebf0")},
	"varkas": {"prefix": "VARKAS  //  ", "color": Color("e9ad72")},
	"pack_a": {"prefix": "WOLVERINE  //  ", "color": Color("a9bfd4")},
	"pack_b": {"prefix": "WOLVERINE  //  ", "color": Color("a9bfd4")},
}

var enabled := true
var panel: PanelContainer
var label: Label
var active_id := ""

var _audio: GoatAudio
var _hide_at := 0.0
var _tween: Tween


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -430.0
	panel.offset_right = 430.0
	panel.offset_bottom = -34.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.045, 0.48)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	panel.add_child(label)
	panel.modulate.a = 0.0
	panel.visible = false
	add_child(panel)


func _process(_delta: float) -> void:
	if not active_id.is_empty() and Time.get_ticks_msec() * 0.001 > _hide_at:
		_hide()


func bind(voice: GoatVoice, audio: GoatAudio) -> void:
	_audio = audio
	enabled = audio.subtitles_enabled
	voice.line_started.connect(_on_line_started)
	voice.line_finished.connect(_on_line_finished)


func shutdown() -> void:
	set_process(false)
	if _tween:
		_tween.kill()
	active_id = ""


func _on_line_started(id: String, speaker: String, text: String, seconds: float, at: Vector3) -> void:
	if not enabled or text.is_empty():
		return
	var is_bark := speaker.begins_with("pack")
	if is_bark:
		if not active_id.is_empty():
			return
		var listener := _audio.listener_position() if _audio else Vector3.INF
		if at == Vector3.INF or listener == Vector3.INF or listener.distance_to(at) > BARK_HEARING:
			return
	var style: Dictionary = STYLES.get(speaker, STYLES.keeper)
	label.text = style.prefix + text
	label.add_theme_color_override("font_color", style.color)
	active_id = id
	_hide_at = Time.get_ticks_msec() * 0.001 + seconds + 0.6
	panel.visible = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(panel, "modulate:a", 1.0, 0.25)


func _on_line_finished(id: String) -> void:
	if id == active_id:
		_hide()


func _hide() -> void:
	active_id = ""
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(panel, "modulate:a", 0.0, 0.35)
	_tween.tween_callback(func(): panel.visible = false)
