extends CharacterBody3D
class_name Player

signal health_changed(value: int)

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 4.5
const MAX_HEALTH: int = 100
const ATTACK_DAMAGE: int = 15
const ATTACK_RANGE: float = 2.5
const ATTACK_HIT_RADIUS: float = 1.0
const ATTACK_COOLDOWN: float = 0.5
const CAMERA_SENSITIVITY: float = 0.001 # CAMERA FIX: Speed aadhi kar di hai, ab nahi fislega
const CAMERA_MIN_PITCH: float = -0.5
const CAMERA_MAX_PITCH: float = 0.2
const IDLE_BREATH_SPEED: float = 1.6
const IDLE_CHEST_ANGLE: float = 0.045
const IDLE_SHOULDER_ANGLE: float = 0.035
const IDLE_HEAD_ANGLE: float = 0.025
const RUN_CYCLES_PER_SECOND: float = 2.0
const RUN_BLEND_SPEED: float = 7.0
const RUN_LEG_SWING_ANGLE: float = 0.48
const RUN_ARM_SWING_ANGLE: float = 0.38
const RUN_ARM_DROP_ANGLE: float = 0.75
const RUN_ARM_ELBOW_FLEX_ANGLE: float = 0.5
const RUN_HIP_BOB_ANGLE: float = 0.025
const RUN_TORSO_SWAY_ANGLE: float = 0.035
const RUN_HEAD_STABILIZE_ANGLE: float = 0.012

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_health: int = MAX_HEALTH
var is_dead: bool = false
var time_since_last_attack: float = 1.0
var idle_time: float = 0.0
var idle_skeleton: Skeleton3D
var idle_bone_indices: Dictionary = {}
var idle_base_rotations: Dictionary = {}
var run_phase: float = 0.0
var run_blend: float = 0.0
var camera_pitch: float = 0.0
var camera_yaw: float = 0.0

# F BUTTON FIX: Yeh variable check karega ki attack button daba hai ya nahi
var _wants_to_attack: bool = false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var model: Node3D = $Model
@onready var skeleton: Skeleton3D = $Model/Rig_Medium/Skeleton3D

# Path check
@onready var anim_player: AnimationPlayer = find_child("AnimationPlayer", true, false)

const MODEL_FORWARD_OFFSET: float = 0.0

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	$CameraPivot/SpringArm3D.add_excluded_object(self.get_rid())
	camera_pitch = camera_pivot.rotation.x
	camera_yaw = camera_pivot.rotation.y
	_setup_procedural_idle()

func _setup_procedural_idle() -> void:
	idle_skeleton = skeleton
	for bone_name: String in ["hips", "chest", "upperarm.l", "lowerarm.l", "upperarm.r", "lowerarm.r", "upperleg.l", "upperleg.r", "head"]:
		var bone_index: int = idle_skeleton.find_bone(bone_name)
		if bone_index >= 0:
			idle_bone_indices[bone_name] = bone_index
			idle_base_rotations[bone_name] = idle_skeleton.get_bone_pose_rotation(bone_index)

func _process(delta: float) -> void:
	if idle_skeleton == null:
		return
	idle_time += delta
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var wants_run: bool = is_on_floor() and horizontal_speed > 0.1 and not is_dead
	var target_run_blend: float = 1.0 if wants_run else 0.0
	run_blend = move_toward(run_blend, target_run_blend, RUN_BLEND_SPEED * delta)
	if wants_run:
		var speed_ratio: float = clampf(horizontal_speed / SPEED, 0.0, 1.25)
		run_phase = fposmod(run_phase + delta * TAU * RUN_CYCLES_PER_SECOND * speed_ratio, TAU)
	var run_swing: float = sin(run_phase)
	var run_bob: float = cos(run_phase * 2.0)
	var idle_weight: float = 1.0 - run_blend
	var breath: float = sin(idle_time * IDLE_BREATH_SPEED)
	var shoulder_motion: float = sin(idle_time * IDLE_BREATH_SPEED + 0.18)
	var head_motion: float = sin(idle_time * IDLE_BREATH_SPEED * 0.5 + 0.4)
	_apply_procedural_rotation("hips", 0.0, Vector3.RIGHT, run_bob * RUN_HIP_BOB_ANGLE * run_blend)
	_apply_procedural_rotation("chest", breath * IDLE_CHEST_ANGLE * idle_weight, Vector3.RIGHT, run_bob * RUN_TORSO_SWAY_ANGLE * run_blend)
	_apply_procedural_rotation("upperleg.l", 0.0, Vector3.RIGHT, run_swing * RUN_LEG_SWING_ANGLE * run_blend)
	_apply_procedural_rotation("upperleg.r", 0.0, Vector3.RIGHT, -run_swing * RUN_LEG_SWING_ANGLE * run_blend)
	_apply_procedural_rotation("upperarm.l", shoulder_motion * IDLE_SHOULDER_ANGLE * idle_weight, Vector3.FORWARD, run_swing * RUN_ARM_SWING_ANGLE * run_blend, Vector3.UP, -RUN_ARM_DROP_ANGLE * run_blend, Vector3.RIGHT)
	_apply_procedural_rotation("lowerarm.l", 0.0, Vector3.RIGHT, RUN_ARM_ELBOW_FLEX_ANGLE * run_blend, Vector3.FORWARD)
	_apply_procedural_rotation("upperarm.r", shoulder_motion * IDLE_SHOULDER_ANGLE * idle_weight, Vector3.FORWARD, run_swing * RUN_ARM_SWING_ANGLE * run_blend, Vector3.UP, -RUN_ARM_DROP_ANGLE * run_blend, Vector3.RIGHT)
	_apply_procedural_rotation("lowerarm.r", 0.0, Vector3.RIGHT, -RUN_ARM_ELBOW_FLEX_ANGLE * run_blend, Vector3.FORWARD)
	_apply_procedural_rotation("head", head_motion * IDLE_HEAD_ANGLE * idle_weight, Vector3.UP, -run_bob * RUN_HEAD_STABILIZE_ANGLE * run_blend)

func _apply_procedural_rotation(bone_name: String, idle_angle: float, idle_axis: Vector3, run_angle: float, run_axis: Vector3 = Vector3.RIGHT, secondary_run_angle: float = 0.0, secondary_run_axis: Vector3 = Vector3.RIGHT) -> void:
	if not idle_bone_indices.has(bone_name):
		return
	var bone_index: int = idle_bone_indices[bone_name]
	var base_rotation: Quaternion = idle_base_rotations[bone_name]
	var idle_offset: Quaternion = Quaternion(idle_axis, idle_angle)
	var run_offset: Quaternion = Quaternion(run_axis, run_angle) * Quaternion(secondary_run_axis, secondary_run_angle)
	idle_skeleton.set_bone_pose_rotation(bone_index, base_rotation * idle_offset * run_offset)

# --- SABSE BADA FIX YAHAN HAI ---
# Yeh function UI se pehle aapka button pakad lega
func _input(event: InputEvent) -> void:
	if is_dead:
		return
		
	# Keyboard 'F' Button check
	if event is InputEventKey and event.physical_keycode == KEY_F and event.pressed and not event.echo:
		_wants_to_attack = true
		
	# Mouse Left Click check
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_wants_to_attack = true

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
		
	if event is InputEventMouseMotion:
		# Camera rotation uses persistent angles so large mouse deltas cannot bypass the clamp.
		camera_pitch = clampf(camera_pitch - event.relative.y * CAMERA_SENSITIVITY, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)
		camera_yaw -= event.relative.x * CAMERA_SENSITIVITY
		camera_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0.0)

	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	time_since_last_attack += delta

	if is_dead:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# BULLETPROOF ATTACK TRIGGER
	if _wants_to_attack:
		_wants_to_attack = false # Ek baar dabaane pe ek hi baar attack
		if time_since_last_attack >= ATTACK_COOLDOWN:
			print("1. F Button Detected!")
			_try_attack()

	# WASD Movement
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir == Vector2.ZERO:
		var x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		var y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		input_dir = Vector2(x, y).normalized()
		
	var cam_forward = -camera_pivot.global_transform.basis.z
	var cam_right = camera_pivot.global_transform.basis.x
	cam_forward.y = 0
	cam_right.y = 0
	cam_forward = cam_forward.normalized()
	cam_right = cam_right.normalized()
	
	var direction = (cam_right * input_dir.x - cam_forward * input_dir.y).normalized()
	
	var is_attacking = anim_player != null and anim_player.current_animation == "attack" and anim_player.is_playing()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		
		var target_angle = atan2(direction.x, direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_angle + MODEL_FORWARD_OFFSET, 12 * delta)
		
		if anim_player and not is_attacking:
			if not anim_player.is_playing() or anim_player.current_animation != "run":
				anim_player.play("run")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		
		if anim_player and not is_attacking:
			if not anim_player.is_playing() or anim_player.current_animation != "idle":
				anim_player.play("idle")

	move_and_slide()

func _try_attack() -> void:
	time_since_last_attack = 0.0
	print("2. Attack Triggered!")
	
	if anim_player:
		anim_player.play("attack")
	
	var origin: Vector3 = global_position + Vector3(0, 1.0, 0)
	var collider: Object = _find_melee_target(origin)
	if collider == null:
		print("3. Attack Hawa Mein Gaya (Miss)")
		return
	collider.call("take_damage", ATTACK_DAMAGE)
	print("4. HIT ENEMY SUCCESS!")

func _find_melee_target(origin: Vector3) -> Object:
	var attack_shape: SphereShape3D = SphereShape3D.new()
	attack_shape.radius = ATTACK_RANGE
	var shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	shape_query.shape = attack_shape
	shape_query.collision_mask = 4
	shape_query.transform = Transform3D(Basis.IDENTITY, origin)
	shape_query.exclude = [self.get_rid()]
	var results: Array = get_world_3d().direct_space_state.intersect_shape(shape_query, 32)
	var best_target: Object = null
	var best_distance: float = INF
	for result: Dictionary in results:
		var target: Object = result.get("collider", null)
		if target == null or not target.has_method("take_damage") or not target is Node3D:
			continue
		var target_node: Node3D = target as Node3D
		var horizontal_distance: float = Vector2(origin.x, origin.z).distance_to(Vector2(target_node.global_position.x, target_node.global_position.z))
		if horizontal_distance > ATTACK_RANGE:
			continue
		if horizontal_distance < best_distance and _melee_has_line_of_sight(origin, target_node):
			best_target = target
			best_distance = horizontal_distance
	return best_target

func _melee_has_line_of_sight(origin: Vector3, target: Node3D) -> bool:
	var target_point: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target_point, 5)
	query.exclude = [self.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider", null) == target

func take_damage(amount: int) -> void:
	if is_dead:
		return
	current_health = maxi(current_health - amount, 0)
	health_changed.emit(current_health)
	
	var ui_manager: Node = get_tree().get_first_node_in_group("ui_manager")
	if ui_manager != null and ui_manager.has_method("flash_damage"):
		ui_manager.call("flash_damage")
		
	if current_health <= 0:
		_die()

func _die() -> void:
	is_dead = true
	print("Player Died!")
	var ui_manager: Node = get_tree().get_first_node_in_group("ui_manager")
	if ui_manager != null and ui_manager.has_method("show_game_over"):
		ui_manager.call("show_game_over")
