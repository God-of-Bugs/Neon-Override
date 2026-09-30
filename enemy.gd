class_name Enemy
extends CharacterBody3D

const SPEED: float = 4.5
const MAX_HEALTH: int = 30
const ATTACK_DAMAGE: int = 5
const ATTACK_RANGE: float = 2.5
const ATTACK_COOLDOWN: float = 0.5
const REST_UPPER_ARM_DROP_ANGLE: float = 0.55
const REST_ELBOW_FLEX_ANGLE: float = 0.12
const IDLE_BREATH_SPEED: float = 1.8
const IDLE_CHEST_ANGLE: float = 0.055
const IDLE_SPINE_ANGLE: float = 0.025
const ATTACK_WINDUP_DURATION: float = 0.15
const ATTACK_STRIKE_DURATION: float = 0.10
const ATTACK_RECOVERY_DURATION: float = 0.25
const ATTACK_POSE_DURATION: float = ATTACK_WINDUP_DURATION + ATTACK_STRIKE_DURATION + ATTACK_RECOVERY_DURATION
const HIT_POSE_DURATION: float = 0.30
const DEATH_POSE_DURATION: float = 0.70
const HIT_RECOIL_ANGLE: float = 0.28
const DEATH_SPINE_ANGLE: float = 0.55
const DEATH_CHEST_ANGLE: float = 0.78
const DEATH_KNEE_FLEX_ANGLE: float = 0.85

enum ProceduralPoseState { IDLE, ATTACK, HIT, DEATH }

const ROUGE_SCENE: PackedScene = preload("res://materials/glb file/Rogue.glb")
const HIT_FEEDBACK: Script = preload("res://enemy_hit_feedback.gd")

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var hit_sparks: GPUParticles3D = $HitSparks
@onready var hit_sound: AudioStreamPlayer3D = $HitSound
@onready var attack_sound: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var health: int = MAX_HEALTH
var attack_damage: int = ATTACK_DAMAGE
var attack_cooldown: float = ATTACK_COOLDOWN
var time_since_last_attack: float = 0.0
var _player: Node3D = null
var procedural_skeleton: Skeleton3D = null
var pose_bone_indices: Dictionary = {}
var base_bone_rotations: Dictionary = {}
var procedural_pose_state: int = ProceduralPoseState.IDLE
var pose_elapsed: float = 0.0
var idle_elapsed: float = 0.0
var is_dead: bool = false

func _ready() -> void:
	HIT_FEEDBACK.configure_sparks(hit_sparks)
	attack_sound.stream = HIT_FEEDBACK.make_attack_sound()
	attack_sound.max_distance = 16.0
	attack_sound.unit_size = 4.0
	attack_sound.name = "AttackSound"
	add_child(attack_sound)
	hit_sound.stream = HIT_FEEDBACK.make_hit_sound()
	agent.velocity_computed.connect(_on_velocity_computed)
	await get_tree().physics_frame
	_acquire_player()
	call_deferred("_spawn_rogue_model")

func _spawn_rogue_model() -> void:
	if ROUGE_SCENE == null:
		push_error("Enemy: ROUGE_SCENE is null!")
		return
	var rogue_model: Node3D = ROUGE_SCENE.instantiate() as Node3D
	if rogue_model == null:
		push_error("Enemy: Rogue model could not be instantiated.")
		return
	add_child(rogue_model)
	rogue_model.scale = Vector3(1.75, 1.75, 1.75)
	rogue_model.position.y = 0.004
	_setup_procedural_bones(rogue_model)

func _setup_procedural_bones(model_root: Node) -> void:
	procedural_skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if procedural_skeleton == null:
		push_error("Enemy: Rogue model has no Skeleton3D for procedural animation.")
		return
	for bone_name: String in ["hips", "spine", "chest", "head", "upperarm.l", "lowerarm.l", "upperarm.r", "lowerarm.r", "upperleg.l", "lowerleg.l", "upperleg.r", "lowerleg.r"]:
		var bone_index: int = procedural_skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var base_rotation: Quaternion = procedural_skeleton.get_bone_pose_rotation(bone_index)
		if bone_name == "upperarm.l" or bone_name == "upperarm.r":
			base_rotation = base_rotation * Quaternion(Vector3.RIGHT, -REST_UPPER_ARM_DROP_ANGLE)
		elif bone_name == "lowerarm.l":
			base_rotation = base_rotation * Quaternion(Vector3.FORWARD, REST_ELBOW_FLEX_ANGLE)
		elif bone_name == "lowerarm.r":
			base_rotation = base_rotation * Quaternion(Vector3.FORWARD, -REST_ELBOW_FLEX_ANGLE)
		pose_bone_indices[bone_name] = bone_index
		base_bone_rotations[bone_name] = base_rotation
		procedural_skeleton.set_bone_pose_rotation(bone_index, base_rotation)
	_apply_idle_pose()

func _process(delta: float) -> void:
	idle_elapsed += delta
	_update_procedural_pose(delta)
	if is_dead:
		return
	time_since_last_attack += delta
	if _player == null:
		return
	if time_since_last_attack < attack_cooldown:
		return

	# Symmetric melee check: nearby player, any angle, with wall blocking.
	var origin: Vector3 = global_position + Vector3(0, 1.0, 0)
	if not _is_embedded_in_obstacle() and _find_melee_player(origin):
		_attack_player()

func _update_procedural_pose(delta: float) -> void:
	match procedural_pose_state:
		ProceduralPoseState.IDLE:
			_apply_idle_pose()
		ProceduralPoseState.ATTACK:
			pose_elapsed += delta
			if pose_elapsed >= ATTACK_POSE_DURATION:
				procedural_pose_state = ProceduralPoseState.IDLE
				pose_elapsed = 0.0
				_apply_idle_pose()
			else:
				_apply_attack_pose(pose_elapsed)
		ProceduralPoseState.HIT:
			pose_elapsed += delta
			if pose_elapsed >= HIT_POSE_DURATION:
				procedural_pose_state = ProceduralPoseState.IDLE
				pose_elapsed = 0.0
				_apply_idle_pose()
			else:
				_apply_hit_pose(pose_elapsed)
		ProceduralPoseState.DEATH:
			pose_elapsed += delta
			_apply_death_pose(clampf(pose_elapsed / DEATH_POSE_DURATION, 0.0, 1.0))
			if pose_elapsed >= DEATH_POSE_DURATION:
				queue_free()

func _apply_idle_pose() -> void:
	var breath: float = sin(idle_elapsed * IDLE_BREATH_SPEED)
	var slow_sway: float = sin(idle_elapsed * 0.65 + 0.3)
	_apply_bone_offset("hips", Quaternion(Vector3.RIGHT, breath * 0.008))
	_apply_bone_offset("spine", Quaternion(Vector3.RIGHT, breath * IDLE_SPINE_ANGLE))
	_apply_bone_offset("chest", Quaternion(Vector3.RIGHT, breath * IDLE_CHEST_ANGLE))
	_apply_bone_offset("head", Quaternion(Vector3.UP, slow_sway * 0.025) * Quaternion(Vector3.RIGHT, breath * 0.012))
	_apply_bone_offset("upperarm.l", Quaternion(Vector3.RIGHT, slow_sway * 0.025))
	_apply_bone_offset("upperarm.r", Quaternion(Vector3.RIGHT, -slow_sway * 0.025))

func _apply_attack_pose(elapsed: float) -> void:
	var attack_drive: float = _get_attack_drive(elapsed)
	var windup_weight: float = clampf(-attack_drive, 0.0, 1.0)
	_apply_bone_offset("chest", Quaternion(Vector3.RIGHT, -attack_drive * 0.10))
	_apply_bone_offset("head", Quaternion(Vector3.RIGHT, -attack_drive * 0.045))
	_apply_bone_offset("upperarm.r", Quaternion(Vector3.RIGHT, -attack_drive * 1.05) * Quaternion(Vector3.FORWARD, -attack_drive * 0.22))
	_apply_bone_offset("lowerarm.r", Quaternion(Vector3.FORWARD, -attack_drive * 0.35) * Quaternion(Vector3.RIGHT, windup_weight * 0.8))
	_apply_bone_offset("upperarm.l", Quaternion(Vector3.RIGHT, attack_drive * 0.18))
	_apply_bone_offset("lowerarm.l", Quaternion(Vector3.FORWARD, windup_weight * 0.12))

func _apply_hit_pose(elapsed: float) -> void:
	var progress: float = clampf(elapsed / HIT_POSE_DURATION, 0.0, 1.0)
	var recoil: float = sin(progress * PI)
	_apply_bone_offset("spine", Quaternion(Vector3.RIGHT, HIT_RECOIL_ANGLE * recoil * 0.45))
	_apply_bone_offset("chest", Quaternion(Vector3.RIGHT, HIT_RECOIL_ANGLE * recoil))
	_apply_bone_offset("head", Quaternion(Vector3.RIGHT, -HIT_RECOIL_ANGLE * recoil * 0.55))
	_apply_bone_offset("upperarm.l", Quaternion(Vector3.RIGHT, recoil * 0.28))
	_apply_bone_offset("upperarm.r", Quaternion(Vector3.RIGHT, -recoil * 0.28))
	_apply_bone_offset("lowerarm.l", Quaternion(Vector3.FORWARD, recoil * 0.18))
	_apply_bone_offset("lowerarm.r", Quaternion(Vector3.FORWARD, -recoil * 0.18))

func _apply_death_pose(progress: float) -> void:
	var fall: float = _ease_progress(progress)
	_apply_bone_offset("hips", Quaternion(Vector3.RIGHT, -fall * 0.22))
	_apply_bone_offset("spine", Quaternion(Vector3.RIGHT, -fall * DEATH_SPINE_ANGLE))
	_apply_bone_offset("chest", Quaternion(Vector3.RIGHT, -fall * DEATH_CHEST_ANGLE))
	_apply_bone_offset("head", Quaternion(Vector3.RIGHT, fall * 0.18))
	_apply_bone_offset("upperarm.l", Quaternion(Vector3.RIGHT, -fall * 0.22))
	_apply_bone_offset("upperarm.r", Quaternion(Vector3.RIGHT, -fall * 0.35))
	_apply_bone_offset("lowerarm.l", Quaternion(Vector3.FORWARD, fall * 0.45))
	_apply_bone_offset("lowerarm.r", Quaternion(Vector3.FORWARD, -fall * 0.45))
	_apply_bone_offset("lowerleg.l", Quaternion(Vector3.RIGHT, fall * DEATH_KNEE_FLEX_ANGLE))
	_apply_bone_offset("lowerleg.r", Quaternion(Vector3.RIGHT, fall * DEATH_KNEE_FLEX_ANGLE))

func _apply_bone_offset(bone_name: String, offset: Quaternion) -> void:
	if procedural_skeleton == null or not pose_bone_indices.has(bone_name):
		return
	var bone_index: int = pose_bone_indices[bone_name]
	var base_rotation: Quaternion = base_bone_rotations[bone_name]
	procedural_skeleton.set_bone_pose_rotation(bone_index, base_rotation * offset)

func _get_attack_drive(elapsed: float) -> float:
	if elapsed < ATTACK_WINDUP_DURATION:
		return -_ease_progress(elapsed / ATTACK_WINDUP_DURATION)
	var strike_elapsed: float = elapsed - ATTACK_WINDUP_DURATION
	if strike_elapsed < ATTACK_STRIKE_DURATION:
		var strike_progress: float = strike_elapsed / ATTACK_STRIKE_DURATION
		return lerpf(-1.0, 1.0, _ease_progress(strike_progress))
	var recovery_elapsed: float = strike_elapsed - ATTACK_STRIKE_DURATION
	return 1.0 - _ease_progress(recovery_elapsed / ATTACK_RECOVERY_DURATION)

func _ease_progress(progress: float) -> float:
	var clamped_progress: float = clampf(progress, 0.0, 1.0)
	return clamped_progress * clamped_progress * (3.0 - 2.0 * clamped_progress)

func _is_embedded_in_obstacle() -> bool:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = 1
	query.exclude = [self.get_rid()]
	var overlaps: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(query, 8)
	for overlap: Dictionary in overlaps:
		var collider: Object = overlap.get("collider", null) as Object
		if collider is CSGBox3D and (collider as CSGBox3D).name != "Floor":
			return true
	return false

func _find_melee_player(origin: Vector3) -> bool:
	if _player == null:
		return false
	var attack_shape: SphereShape3D = SphereShape3D.new()
	attack_shape.radius = ATTACK_RANGE
	var shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	shape_query.shape = attack_shape
	shape_query.collision_mask = 2
	shape_query.transform = Transform3D(Basis.IDENTITY, origin)
	shape_query.exclude = [self.get_rid()]
	var results: Array = get_world_3d().direct_space_state.intersect_shape(shape_query, 8)
	var horizontal_distance: float = Vector2(global_position.x, global_position.z).distance_to(Vector2(_player.global_position.x, _player.global_position.z))
	if horizontal_distance > ATTACK_RANGE:
		return false
	for result: Dictionary in results:
		if result.get("collider", null) == _player and _melee_has_line_of_sight(origin, _player):
			return true
	return false

func _melee_has_line_of_sight(origin: Vector3, target: Node3D) -> bool:
	var target_point: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target_point, 7)
	query.exclude = [self.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return hit.get("collider", null) == target

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if _player == null:
		_acquire_player()

	var intended_velocity: Vector3 = Vector3.ZERO

	if is_on_floor():
		intended_velocity.y = 0.0
	else:
		intended_velocity.y = velocity.y + get_gravity().y * delta

	# Enemies remain at their assigned spawn positions. They only attack when the player approaches.

	if agent.avoidance_enabled:
		agent.set_velocity(intended_velocity)
	else:
		_on_velocity_computed(intended_velocity)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if is_dead:
		return
	velocity = safe_velocity
	move_and_slide()

func take_damage(amount: int) -> void:
	if is_dead:
		return
	health -= amount
	if hit_sparks:
		hit_sparks.emitting = true
		hit_sparks.restart()
	if hit_sound:
		hit_sound.play()
	if health <= 0:
		is_dead = true
		var game_flow_manager: Node = get_node_or_null("/root/GameFlowManager")
		if game_flow_manager != null and game_flow_manager.has_method("record_enemy_defeated"):
			game_flow_manager.call("record_enemy_defeated", self)
		procedural_pose_state = ProceduralPoseState.DEATH
		pose_elapsed = 0.0
		velocity = Vector3.ZERO
		collision_shape.set_deferred("disabled", true)
		set_physics_process(false)
		return
	procedural_pose_state = ProceduralPoseState.HIT
	pose_elapsed = 0.0

func _attack_player() -> void:
	time_since_last_attack = 0.0
	if procedural_pose_state != ProceduralPoseState.HIT:
		procedural_pose_state = ProceduralPoseState.ATTACK
		pose_elapsed = 0.0
	if _player != null and is_instance_valid(_player) and _player.has_method("take_damage"):
		_player.call("take_damage", attack_damage)
		if is_instance_valid(attack_sound):
			attack_sound.play()

func _acquire_player() -> void:
	var found: Node = get_tree().get_first_node_in_group("player")
	_player = found as Node3D
	if _player != null:
		agent.target_position = _player.global_position
