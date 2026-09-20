class_name Player
extends CharacterBody3D

## Third-person player controller.
## Origin sits at the feet; CollisionShape3D and MeshInstance3D are offset up by
## half the capsule. The body yaws with the mouse, CameraPivot pitches, and
## movement is relative to where the camera is facing.

signal health_changed(new_health: int)

const SPEED: float = 6.0
const JUMP_VELOCITY: float = 5.0
const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_MIN: float = -1.22173  # -70 degrees (looking up)
const PITCH_MAX: float = 0.523599  # +30 degrees (looking down)
const ATTACK_DAMAGE: int = 10

@onready var camera_pivot: Node3D = $CameraPivot
@onready var attack_hitbox: Area3D = $AttackHitbox
@onready var camera_3d: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var attack_sound: AudioStreamPlayer = $AttackSound
@onready var anim_player: AnimationPlayer = $PlayerModel/AnimationPlayer
@onready var ui_manager: Node = get_tree().get_first_node_in_group("ui_manager")

var max_health: int = 100
var current_health: int = 100

var _pitch: float = 0.0
var _just_captured: bool = false


func _ready() -> void:
	_capture_mouse()
	# Adopt whatever downward tilt is authored on the pivot in the scene.
	_pitch = camera_pivot.rotation.x


func _unhandled_input(event: InputEvent) -> void:
	# Once the player is dead the game-over panel owns the mouse.
	if current_health <= 0:
		return
	if event is InputEventMouseMotion:
		_look(event)
	elif event is InputEventMouseButton and event.pressed:
		# Click back in to re-capture after releasing with Escape.
		_capture_mouse()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _look(motion: InputEventMouseMotion) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	# The first motion event after capturing carries the pointer's jump to the
	# window centre; applying it would snap the view, so drop it.
	if _just_captured:
		_just_captured = false
		return
	rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
	_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	camera_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("attack"):
		_attack()

	# Movement relative to the camera's facing, flattened onto the ground plane.
	# Godot's built-in ui_* actions carry both the arrow keys and WASD.
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var cam_basis: Basis = camera_pivot.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	var right: Vector3 = cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	var direction: Vector3 = (right * input_dir.x - forward * input_dir.y).normalized()

	# Play animations based on movement state.
	if direction != Vector3.ZERO:
		if anim_player and not anim_player.is_playing() or anim_player.current_animation != "running":
			anim_player.play("running")
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		if anim_player and not anim_player.is_playing() or anim_player.current_animation != "idle":
			anim_player.play("idle")
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()


func take_damage(amount: int) -> void:
	# Ignore further hits once dead, so the UI is not spammed with signals.
	if current_health <= 0:
		return
	current_health = maxi(current_health - amount, 0)
	print("Player took ", amount, " damage - ", current_health, "/", max_health, " hp")
	health_changed.emit(current_health)
	hit_stop()
	if ui_manager != null and ui_manager.has_method("flash_damage"):
		ui_manager.flash_damage()
	if current_health <= 0:
		_die()


func _die() -> void:
	# Stop all movement; mouse look and attacks stop with it.
	set_physics_process(false)
	_show_game_over()


func _show_game_over() -> void:
	if ui_manager != null and ui_manager.has_method("show_game_over"):
		ui_manager.call("show_game_over")


func _attack() -> void:
	print("Player Attacked!")
	attack_sound.play()
	if anim_player:
		anim_player.play("punch")
	hit_stop()
	for body in attack_hitbox.get_overlapping_bodies():
		if body.is_in_group("enemy") and body.has_method("take_damage"):
			body.call("take_damage", ATTACK_DAMAGE)


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_just_captured = true


func hit_stop() -> void:
	Engine.time_scale = 0.1
	await get_tree().create_timer(0.05).timeout
	Engine.time_scale = 1.0
