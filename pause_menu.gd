class_name PauseMenu
extends CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var overlay: ColorRect = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.015, 0.025, 0.045, 0.84)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360.0, 0.0)
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.075, 0.11, 0.98)
	panel_style.border_color = Color(0.0, 0.72, 0.75, 0.85)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 34.0
	panel_style.content_margin_right = 34.0
	panel_style.content_margin_top = 30.0
	panel_style.content_margin_bottom = 30.0
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var title: Label = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.0, 0.88, 0.86, 1.0))
	column.add_child(title)
	var resume_button: Button = _make_button("RESUME")
	resume_button.pressed.connect(func() -> void: get_node("/root/GameFlowManager").call("resume_game"))
	column.add_child(resume_button)
	var restart_button: Button = _make_button("RESTART")
	restart_button.pressed.connect(func() -> void: get_node("/root/GameFlowManager").call("restart_game"))
	column.add_child(restart_button)
	var menu_button: Button = _make_button("MAIN MENU")
	menu_button.pressed.connect(func() -> void: get_node("/root/GameFlowManager").call("return_to_main_menu"))
	column.add_child(menu_button)
	resume_button.grab_focus()

func _make_button(label_text: String) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(280.0, 48.0)
	button.add_theme_font_size_override("font_size", 17)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.18, 0.24, 1.0)
	normal.set_corner_radius_all(5)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.0, 0.48, 0.54, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button
