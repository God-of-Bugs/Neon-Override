extends Node

const MAIN_MENU_PATH: String = "res://MainMenu.tscn"
const MAIN_WORLD_PATH: String = "res://MainWorld.tscn"
const PAUSE_MENU_SCENE: PackedScene = preload("res://PauseMenu.tscn")
const DEATH_RETURN_DELAY: float = 1.0
const VICTORY_DISPLAY_DURATION: float = 2.5
const POINTS_PER_ENEMY: int = 100
const VICTORY_SCREEN_SCENE: PackedScene = preload("res://VictoryScreen.tscn")

var _active_world: Node = null
var _pause_menu: CanvasLayer = null
var _gameplay_active: bool = false
var _run_points: int = 0
var _run_enemies_defeated: int = 0
var _last_run_points: int = 0
var _last_run_enemies_defeated: int = 0
var _last_run_result: String = ""
var _run_finished: bool = false
var _victory_triggered: bool = false
var _victory_popup: Control = null
var _return_to_menu_started: bool = false
var _required_enemy_count: int = 0
var _registered_enemy_ids: Dictionary = {}
var _expected_enemy_ids: Dictionary = {}
var _counted_enemy_ids: Dictionary = {}
var _wave_spawning_complete: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(_on_scene_changed)
	if _is_gameplay_scene(get_tree().current_scene):
		_begin_gameplay(get_tree().current_scene)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo() or not _gameplay_active:
		return
	if _is_game_over_visible():
		return
	if get_tree().paused:
		resume_game()
	else:
		_pause_game()
	get_viewport().set_input_as_handled()

func _pause_game() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_pause_menu = PAUSE_MENU_SCENE.instantiate() as CanvasLayer
	if _pause_menu == null:
		get_tree().paused = false
		push_error("GameFlowManager: PauseMenu scene root must be a CanvasLayer")
		return
	_pause_menu.name = "PauseMenu"
	get_tree().root.add_child(_pause_menu)

func _close_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null

func play_game() -> void:
	_start_fresh_run()

func _start_fresh_run() -> void:
	get_tree().paused = false
	_close_pause_menu()
	_run_points = 0
	_run_enemies_defeated = 0
	_run_finished = false
	_victory_triggered = false
	_victory_popup = null
	_return_to_menu_started = false
	_required_enemy_count = 0
	_registered_enemy_ids.clear()
	_expected_enemy_ids.clear()
	_counted_enemy_ids.clear()
	_wave_spawning_complete = false
	_change_scene(MAIN_WORLD_PATH)

func register_wave(required_enemy_count: int) -> void:
	if not _gameplay_active or _run_finished:
		return
	_required_enemy_count = maxi(required_enemy_count, 0)
	var expected_enemy_ids: Array = _expected_enemy_ids.keys()
	for enemy_id: Variant in expected_enemy_ids:
		var expected_ref: WeakRef = _expected_enemy_ids[enemy_id] as WeakRef
		var expected_enemy: Node = expected_ref.get_ref() as Node if expected_ref != null else null
		if expected_enemy == null or not is_instance_valid(expected_enemy):
			_expected_enemy_ids.erase(enemy_id)
			continue
		_register_enemy_instance(expected_enemy)
	_print_victory_debug("wave_registered", {"required_count": _required_enemy_count})
	_evaluate_victory()

func register_enemy(enemy: Node) -> void:
	if not _gameplay_active or _run_finished or enemy == null:
		return
	var enemy_id: int = enemy.get_instance_id()
	if _required_enemy_count <= 0:
		_expected_enemy_ids[enemy_id] = weakref(enemy)
		_print_victory_debug("enemy_registered_before_wave_count", {"enemy_instance": enemy.name, "enemy_id": enemy_id})
		return
	_register_enemy_instance(enemy)

func _register_enemy_instance(enemy: Node) -> void:
	var enemy_id: int = enemy.get_instance_id()
	if _registered_enemy_ids.has(enemy_id):
		return
	_registered_enemy_ids[enemy_id] = weakref(enemy)
	_print_victory_debug("enemy_registered", {"enemy_instance": enemy.name, "enemy_id": enemy_id})

func wave_spawning_complete() -> void:
	if not _gameplay_active or _run_finished:
		return
	_wave_spawning_complete = true
	_print_victory_debug("spawning_complete", {"spawned_count": _registered_enemy_ids.size(), "required_count": _required_enemy_count})
	_evaluate_victory()

func record_enemy_defeated(enemy: Node) -> void:
	if not _gameplay_active or _run_finished or enemy == null:
		return
	var enemy_id: int = enemy.get_instance_id()
	if _counted_enemy_ids.has(enemy_id):
		return
	_counted_enemy_ids[enemy_id] = true
	_run_enemies_defeated += 1
	_run_points += POINTS_PER_ENEMY
	var spawned_count: int = _registered_enemy_ids.size()
	var alive_count: int = _count_alive_registered_enemies()
	var is_final_defeat: bool = _wave_spawning_complete and alive_count == 0 and _required_enemy_count > 0 and spawned_count >= _required_enemy_count and _run_enemies_defeated >= _required_enemy_count
	print("[VICTORY DEBUG] enemy_defeated=%s enemy_id=%d counted=true spawned_count=%d alive_count=%d defeated_count=%d required_count=%d last_enemy_defeated=%s victory_condition=%s victory_triggered=%s popup_created=%s popup_visible=%s return_to_menu_started=%s" % [enemy.name, enemy_id, spawned_count, alive_count, _run_enemies_defeated, _required_enemy_count, is_final_defeat, is_final_defeat, _victory_triggered, _victory_popup != null, _victory_popup != null and is_instance_valid(_victory_popup) and _victory_popup.visible, _run_finished])
	_evaluate_victory()

func _count_alive_registered_enemies() -> int:
	var alive_count: int = 0
	for enemy_id: Variant in _registered_enemy_ids:
		if _counted_enemy_ids.has(enemy_id):
			continue
		var weak_enemy: WeakRef = _registered_enemy_ids[enemy_id] as WeakRef
		var enemy: Node3D = weak_enemy.get_ref() as Node3D if weak_enemy != null else null
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead:
			alive_count += 1
	return alive_count

func _evaluate_victory() -> void:
	if not _gameplay_active or _run_finished or _victory_triggered:
		return
	var spawned_count: int = _registered_enemy_ids.size()
	var alive_count: int = _count_alive_registered_enemies()
	var victory_condition: bool = _wave_spawning_complete and _required_enemy_count > 0 and spawned_count >= _required_enemy_count and _run_enemies_defeated >= _required_enemy_count and alive_count == 0
	if victory_condition:
		print("[VICTORY DEBUG] LAST ENEMY DEFEATED alive_count=0 victory_condition=true victory_triggered=false")
		_trigger_victory()

func _trigger_victory() -> void:
	if _victory_triggered or _run_finished:
		return
	_victory_triggered = true
	print("[VICTORY DEBUG] victory_triggered=true")
	_victory_popup = VICTORY_SCREEN_SCENE.instantiate() as Control
	if _victory_popup == null:
		push_error("GameFlowManager: VictoryScreen root must be a Control")
		return
	_victory_popup.name = "VictoryScreen"
	get_tree().root.add_child(_victory_popup)
	print("[VICTORY DEBUG] victory_popup_created=true victory_popup_visible=%s" % str(_victory_popup.visible))
	finish_run("VICTORY")
	await get_tree().create_timer(VICTORY_DISPLAY_DURATION, true, false, true).timeout
	if not is_inside_tree() or not _victory_triggered:
		return
	_return_to_menu_started = true
	print("[VICTORY DEBUG] return_to_menu_started=true")
	if _victory_popup != null and is_instance_valid(_victory_popup):
		_victory_popup.queue_free()
	_victory_popup = null
	get_tree().paused = false
	_change_scene(MAIN_MENU_PATH)

func _print_victory_debug(event_name: String, details: Dictionary = {}) -> void:
	var goal_spawned: bool = _wave_spawning_complete and _required_enemy_count > 0 and _registered_enemy_ids.size() >= _required_enemy_count
	print("[VICTORY DEBUG] event=%s details=%s spawned_count=%d alive_count=%d defeated_count=%d required_count=%d victory_condition=%s victory_triggered=%s popup_created=%s popup_visible=%s return_to_menu_started=%s" % [event_name, str(details), _registered_enemy_ids.size(), _count_alive_registered_enemies(), _run_enemies_defeated, _required_enemy_count, goal_spawned and _count_alive_registered_enemies() == 0 and _run_enemies_defeated >= _required_enemy_count, _victory_triggered, _victory_popup != null, _victory_popup != null and is_instance_valid(_victory_popup) and _victory_popup.visible, _return_to_menu_started])

func finish_run(result: String) -> void:
	if _run_finished:
		return
	_run_finished = true
	_last_run_points = _run_points
	_last_run_enemies_defeated = _run_enemies_defeated
	_last_run_result = result
	_close_pause_menu()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if result == "VICTORY":
		get_tree().paused = true
		return
	get_tree().paused = true
	_finish_run_after_delay()

func _finish_run_after_delay() -> void:
	await get_tree().create_timer(DEATH_RETURN_DELAY, true, false, true).timeout
	if not is_inside_tree() or _last_run_result == "VICTORY":
		return
	get_tree().paused = false
	_change_scene(MAIN_MENU_PATH)

func get_last_run_results() -> Dictionary:
	return {
		"points": _last_run_points,
		"enemies_defeated": _last_run_enemies_defeated,
		"result": _last_run_result,
		"available": _last_run_result != ""
	}

func get_current_run_results() -> Dictionary:
	return {
		"points": _run_points,
		"enemies_defeated": _run_enemies_defeated
	}

func restart_game() -> void:
	_start_fresh_run()

func return_to_main_menu() -> void:
	get_tree().paused = false
	_close_pause_menu()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_change_scene(MAIN_MENU_PATH)

func resume_game() -> void:
	if not _gameplay_active:
		return
	get_tree().paused = false
	_close_pause_menu()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_scene_changed() -> void:
	get_tree().paused = false
	_close_pause_menu()
	var current_scene: Node = get_tree().current_scene
	if _is_gameplay_scene(current_scene):
		_begin_gameplay(current_scene)
	else:
		_gameplay_active = false
		_active_world = null
		if _victory_popup != null and is_instance_valid(_victory_popup):
			_victory_popup.queue_free()
		_victory_popup = null
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _begin_gameplay(world: Node) -> void:
	_active_world = world
	_gameplay_active = true
	_run_finished = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _is_gameplay_scene(scene: Node) -> bool:
	return scene != null and scene.scene_file_path == MAIN_WORLD_PATH

func _is_game_over_visible() -> bool:
	if _active_world == null or not is_instance_valid(_active_world):
		return false
	var ui_manager: Node = _active_world.get_node_or_null("UIManager")
	if ui_manager == null:
		return false
	var panel: Control = ui_manager.get_node_or_null("GameOverPanel") as Control
	return panel != null and panel.visible

func _change_scene(scene_path: String) -> void:
	var change_error: Error = get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		push_error("GameFlowManager: Could not load %s: %s" % [scene_path, error_string(change_error)])
