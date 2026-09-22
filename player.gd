extends CharacterBody3D
class_name Player

## Health, damage, death aur attack — sab yahan hai.
## Enemies take_damage() call karte hain, UI health_changed signal se
## update hoti hai, aur "attack" (left mouse / F) se hum ray maarte hain.

signal health_changed(value: int)

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 4.5
const MAX_HEALTH: int = 100
const ATTACK_DAMAGE: int = 15
const ATTACK_RANGE: float = 2.5
const ATTACK_COOLDOWN: float = 0.5

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_health: int = MAX_HEALTH
var is_dead: bool = false
var time_since_last_attack: float = 1.0

@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

func _ready() -> void:
	# Enemy isko "player" group se dhoondhte hain
	add_to_group("player")
	# Mouse lock karna
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventMouseMotion:
		# Mouse left/right karne par POORA player ghoomega (Cylinder wala style)
		rotate_y(-event.relative.x * 0.005)

		# Mouse up/down karne par sirf Camera up/down hoga
		$CameraPivot.rotate_x(-event.relative.y * 0.005)
		# Camera ko poora palatne se rokna
		$CameraPivot.rotation.x = clamp($CameraPivot.rotation.x, -1.0, 1.0)

	# ESC dabane par mouse wapas laana
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	time_since_last_attack += delta

	if is_dead:
		# Mara hua player bas zameen pe rukta hai, move nahi karta
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump (Space)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Attack (left mouse ya F) — cooldown ke saath
	if Input.is_action_just_pressed("attack") and time_since_last_attack >= ATTACK_COOLDOWN:
		_try_attack()

	# W, A, S, D Movement (Player jahan dekh raha hai uske relative)
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()


## Camera ki taraf dekh kar saamne 2.5m ke andar enemy pe ray maarta hai.
func _try_attack() -> void:
	time_since_last_attack = 0.0
	var look_dir: Vector3 = -camera.global_transform.basis.z
	look_dir.y = 0.0
	look_dir = look_dir.normalized()
	if look_dir == Vector3.ZERO:
		return
	var origin: Vector3 = global_position + Vector3(0, 1.0, 0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, origin + look_dir * ATTACK_RANGE, 4)
	query.exclude = [self.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit["collider"]
	if collider and collider.has_method("take_damage"):
		collider.call("take_damage", ATTACK_DAMAGE)


## Enemy isse damage ke liye call karta hai.
func take_damage(amount: int) -> void:
	if is_dead:
		return
	current_health = maxi(current_health - amount, 0)
	health_changed.emit(current_health)
	# Screen pe laal damage flash
	var ui_manager: Node = get_tree().get_first_node_in_group("ui_manager")
	if ui_manager != null and ui_manager.has_method("flash_damage"):
		ui_manager.call("flash_damage")
	if current_health <= 0:
		_die()


func _die() -> void:
	is_dead = true
	print("[Player] died — game over!")
	var ui_manager: Node = get_tree().get_first_node_in_group("ui_manager")
	if ui_manager != null and ui_manager.has_method("show_game_over"):
		ui_manager.call("show_game_over")
