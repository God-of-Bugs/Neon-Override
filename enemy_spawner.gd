extends Node3D

@export var max_enemies: int = 5
@export var spawn_interval: float = 3.0
@export var spawn_area_size: Vector2 = Vector2(44.0, 40.0)
@export var minimum_spawn_separation: float = 5.0

const SPAWN_HEIGHT: float = 0.5
const MAX_SPAWN_ATTEMPTS: int = 30

var enemies_spawned: int = 0
var timer: Timer
var spawn_positions: Array[Vector3] = []

func _ready() -> void:
	timer = get_node_or_null("Timer") as Timer
	if timer == null:
		timer = Timer.new()
		timer.name = "Timer"
		add_child(timer)
	timer.wait_time = spawn_interval
	timer.autostart = true
	if not timer.timeout.is_connected(_on_timer_timeout):
		timer.timeout.connect(_on_timer_timeout)
	timer.start()
	_spawn_enemy()

func _on_timer_timeout() -> void:
	if enemies_spawned >= max_enemies:
		timer.stop()
		print("Saare enemies aa chuke hain! Wave Complete.")
		return
	_spawn_enemy()

func _spawn_enemy() -> void:
	var spawn_position: Vector3 = _find_spawn_position()
	if spawn_position == Vector3.INF:
		print("Enemy spawn skipped: no separated position available after ", MAX_SPAWN_ATTEMPTS, " attempts.")
		return
	var enemy: Node3D = load("res://Enemy.tscn").instantiate() as Node3D
	spawn_positions.append(spawn_position)
	get_tree().current_scene.call_deferred("add_child", enemy)
	enemy.call_deferred("set_global_position", spawn_position)
	enemies_spawned += 1
	print("Naya Enemy Aaya! Total: ", enemies_spawned, " at ", spawn_position)

func _find_spawn_position() -> Vector3:
	for attempt: int in range(MAX_SPAWN_ATTEMPTS):
		var candidate: Vector3 = global_position + Vector3(
			randf_range(-spawn_area_size.x * 0.5, spawn_area_size.x * 0.5),
			SPAWN_HEIGHT,
			randf_range(-spawn_area_size.y * 0.5, spawn_area_size.y * 0.5)
		)
		var separated: bool = true
		for existing: Vector3 in spawn_positions:
			if candidate.distance_to(existing) < minimum_spawn_separation:
				separated = false
				break
		if separated:
			return candidate
	return Vector3.INF
