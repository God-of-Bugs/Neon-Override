class_name Player
extends CharacterBody3D

## Third-person player controller.
## Origin sits at the feet; CollisionShape3D and MeshInstance3D are offset up by
## half the capsule. The body yaws with the mouse, CameraPivot pitches, and
## movement is relative to where the camera is facing.

const SPEED: float = 6.0
const JUMP_VELOCITY: float = 5.0
const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_MIN: float = -1.22173  # -70 degrees (looking up)
const PITCH_MAX: float = 0.523599  # +30 degrees (looking down)
const ATTACK_DAMAGE: int = 10

@onready var camera_pivot: Node3D = $CameraPivot
@onready var attack_hitbox: Area3D = $AttackHitbox

var _pitch: float = 0.0
var _just_captured: bool = false


func _ready() -> void:
	_capture_mouse()
	# Adopt whatever downward tilt is authored on the pivot in the scene.
	_pitch = camera_pivot.rotation.x


func _unhandled_input(event: InputEvent) -> void:
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

	if direction != Vector3.ZERO:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()


func _attack() -> void:
	print("Player Attacked!")
	for body in attack_hitbox.get_overlapping_bodies():
		if body.is_in_group("enemy") and body.has_method("take_damage"):
			body.call("take_damage", ATTACK_DAMAGE)


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_just_captured = true
