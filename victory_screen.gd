class_name VictoryScreen
extends Control

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background: ColorRect = ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.018, 0.045, 0.07, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(430.0, 0.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.09, 0.13, 0.98)
	style.border_color = Color(0.0, 0.82, 0.76, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 40.0
	style.content_margin_right = 40.0
	style.content_margin_top = 36.0
	style.content_margin_bottom = 36.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var title: Label = Label.new()
	title.text = "YAHHH! YOU WIN!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.79, 1.0))
	column.add_child(title)
	var subtitle: Label = Label.new()
	subtitle.text = "RETURNING TO MAIN MENU..."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.67, 0.82, 0.86, 1.0))
	column.add_child(subtitle)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	column.add_child(spacer)
	var replay_button: Button = _make_button("REPLAY", true)
	replay_button.pressed.connect(_on_replay_pressed)
	column.add_child(replay_button)
	var menu_button: Button = _make_button("MAIN MENU", false)
	menu_button.pressed.connect(_on_menu_pressed)
	column.add_child(menu_button)
	replay_button.grab_focus()

func _make_button(label_text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(0.0, 50.0)
	button.add_theme_font_size_override("font_size", 18 if primary else 16)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.54, 0.55, 1.0) if primary else Color(0.11, 0.18, 0.23, 1.0)
	normal.set_corner_radius_all(5)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.0, 0.72, 0.68, 1.0) if primary else Color(0.18, 0.28, 0.33, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button

func _on_replay_pressed() -> void:
	get_node("/root/GameFlowManager").call("restart_game")

func _on_menu_pressed() -> void:
	get_node("/root/GameFlowManager").call("return_to_main_menu")
