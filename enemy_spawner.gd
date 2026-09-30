extends Node3D

@export var max_enemies: int = 5
@export var spawn_interval: float = 3.0
@export var spawn_area_size: Vector2 = Vector2(44.0, 40.0)
@export var minimum_spawn_separation: float = 5.0

const SPAWN_HEIGHT: float = 0.0
const MAX_SPAWN_ATTEMPTS: int = 30
const ENVIRONMENT_COLLISION_MASK: int = 1
const SPAWN_CLEARANCE_RADIUS: float = 0.42
const SPAWN_CLEARANCE_HEIGHT: float = 1.9

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
	call_deferred("_spawn_initial_enemy")
	var game_flow_manager: Node = get_node_or_null("/root/GameFlowManager")
	if game_flow_manager != null and game_flow_manager.has_method("register_wave"):
		game_flow_manager.call_deferred("register_wave", max_enemies)

func _spawn_initial_enemy() -> void:
	await get_tree().physics_frame
	if is_inside_tree() and enemies_spawned == 0:
		_spawn_enemy()

func _on_timer_timeout() -> void:
	if enemies_spawned >= max_enemies:
		timer.stop()
		print("Saare enemies aa chuke hain! Wave Complete.")
		var game_flow_manager: Node = get_node_or_null("/root/GameFlowManager")
		if game_flow_manager != null and game_flow_manager.has_method("wave_spawning_complete"):
			game_flow_manager.call("wave_spawning_complete")
		return
	_spawn_enemy()

func _spawn_enemy() -> void:
	var spawn_position: Vector3 = _find_spawn_position()
	if spawn_position == Vector3.INF:
		print("Enemy spawn skipped: no valid position available after ", MAX_SPAWN_ATTEMPTS, " attempts.")
		return
	var enemy: Node3D = load("res://Enemy.tscn").instantiate() as Node3D
	get_parent().add_child(enemy)
	enemy.global_position = spawn_position
	spawn_positions.append(spawn_position)
	enemies_spawned += 1
	var game_flow_manager: Node = get_node_or_null("/root/GameFlowManager")
	if game_flow_manager != null and game_flow_manager.has_method("register_enemy"):
		game_flow_manager.call_deferred("register_enemy", enemy)
	print("Naya Enemy Aaya! Total: ", enemies_spawned, " at ", spawn_position)

func _find_spawn_position() -> Vector3:
	for attempt: int in range(MAX_SPAWN_ATTEMPTS):
		var candidate: Vector3 = global_position + Vector3(
			randf_range(-spawn_area_size.x * 0.5, spawn_area_size.x * 0.5),
			SPAWN_HEIGHT,
			randf_range(-spawn_area_size.y * 0.5, spawn_area_size.y * 0.5)
		)
		if not _is_inside_spawn_bounds(candidate):
			continue
		if not _is_on_walkable_floor(candidate):
			continue
		if not _has_environment_clearance(candidate):
			continue
		if not _has_enemy_separation(candidate):
			continue
		return candidate
	return Vector3.INF

func _is_inside_spawn_bounds(candidate: Vector3) -> bool:
	var local_candidate: Vector3 = to_local(candidate)
	return absf(local_candidate.x) <= spawn_area_size.x * 0.5 and absf(local_candidate.z) <= spawn_area_size.y * 0.5

func _is_on_walkable_floor(candidate: Vector3) -> bool:
	var ray_from: Vector3 = candidate + Vector3.UP * 1.0
	var ray_to: Vector3 = candidate + Vector3.DOWN * 3.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to, ENVIRONMENT_COLLISION_MASK)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.get("collider", null) is CSGBox3D:
		return false
	var floor_body: CSGBox3D = hit.get("collider") as CSGBox3D
	return floor_body.name == "Floor" and absf(float(hit.get("normal", Vector3.ZERO).y)) > 0.7

func _has_environment_clearance(candidate: Vector3) -> bool:
	var clearance_shape: CapsuleShape3D = CapsuleShape3D.new()
	clearance_shape.radius = SPAWN_CLEARANCE_RADIUS
	clearance_shape.height = SPAWN_CLEARANCE_HEIGHT
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = clearance_shape
	query.transform = Transform3D(Basis.IDENTITY, candidate + Vector3.UP * SPAWN_CLEARANCE_HEIGHT * 0.5)
	query.collision_mask = ENVIRONMENT_COLLISION_MASK
	query.collide_with_bodies = true
	var overlaps: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(query, 16)
	return overlaps.is_empty()

func _has_enemy_separation(candidate: Vector3) -> bool:
	for existing: Vector3 in spawn_positions:
		if candidate.distance_to(existing) < minimum_spawn_separation:
			return false
	return true
