class_name MainMenu
extends Control

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background: ColorRect = ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.025, 0.045, 0.075, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var accent: ColorRect = ColorRect.new()
	accent.position = Vector2(0.0, 0.0)
	accent.size = Vector2(8.0, 900.0)
	accent.color = Color(0.0, 0.78, 0.78, 1.0)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(accent)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(380.0, 0.0)
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	var eyebrow: Label = Label.new()
	eyebrow.text = "NEON ARENA  /  SURVIVAL PROTOCOL"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_color_override("font_color", Color(0.0, 0.86, 0.84, 1.0))
	column.add_child(eyebrow)
	var title: Label = Label.new()
	title.text = "NEON\nOVERRIDE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0, 1.0))
	column.add_child(title)
	var subtitle: Label = Label.new()
	subtitle.text = "Survive the arena. Clear the wave."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.60, 0.70, 0.78, 1.0))
	column.add_child(subtitle)
	var results: Dictionary = get_node("/root/GameFlowManager").call("get_last_run_results") as Dictionary
	if bool(results.get("available", false)):
		var results_panel: PanelContainer = PanelContainer.new()
		var results_style: StyleBoxFlat = StyleBoxFlat.new()
		results_style.bg_color = Color(0.045, 0.075, 0.11, 0.98)
		results_style.border_color = Color(0.0, 0.72, 0.75, 0.85)
		results_style.set_border_width_all(1)
		results_style.set_corner_radius_all(8)
		results_style.content_margin_left = 20.0
		results_style.content_margin_right = 20.0
		results_style.content_margin_top = 14.0
		results_style.content_margin_bottom = 14.0
		results_panel.add_theme_stylebox_override("panel", results_style)
		column.add_child(results_panel)
		var results_column: VBoxContainer = VBoxContainer.new()
		results_column.add_theme_constant_override("separation", 6)
		results_panel.add_child(results_column)
		var results_title: Label = Label.new()
		results_title.text = "LAST RUN / RESULTS — %s" % str(results.get("result", ""))
		results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		results_title.add_theme_color_override("font_color", Color(0.0, 0.86, 0.84, 1.0))
		results_column.add_child(results_title)
		var points_label: Label = Label.new()
		points_label.text = "Points: %d" % int(results.get("points", 0))
		points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		results_column.add_child(points_label)
		var enemies_label: Label = Label.new()
		enemies_label.text = "Enemies defeated: %d" % int(results.get("enemies_defeated", 0))
		enemies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		results_column.add_child(enemies_label)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 14.0)
	column.add_child(spacer)
	var play_label: String = "PLAY AGAIN / RETRY" if bool(results.get("available", false)) else "PLAY"
	var play_button: Button = _make_button(play_label, true)
	play_button.pressed.connect(_on_play_pressed)
	column.add_child(play_button)
	var quit_button: Button = _make_button("QUIT", false)
	quit_button.pressed.connect(_on_quit_pressed)
	column.add_child(quit_button)
	var hint: Label = Label.new()
	hint.text = "WASD move   ·   F / LMB attack   ·   ESC pause"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.47, 0.56, 0.66, 1.0))
	column.add_child(hint)

func _make_button(label_text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(0.0, 54.0)
	button.add_theme_font_size_override("font_size", 20 if primary else 16)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.55, 0.59, 1.0) if primary else Color(0.10, 0.15, 0.21, 1.0)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.0, 0.72, 0.74, 1.0) if primary else Color(0.17, 0.24, 0.31, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button

func _on_play_pressed() -> void:
	get_node("/root/GameFlowManager").call("play_game")

func _on_quit_pressed() -> void:
	get_tree().quit()
