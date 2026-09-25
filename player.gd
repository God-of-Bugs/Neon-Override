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

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_health: int = MAX_HEALTH
var is_dead: bool = false
var time_since_last_attack: float = 1.0

# F BUTTON FIX: Yeh variable check karega ki attack button daba hai ya nahi
var _wants_to_attack: bool = false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var model: Node3D = $Model

# Path check
@onready var anim_player: AnimationPlayer = find_child("AnimationPlayer", true, false)

const MODEL_FORWARD_OFFSET: float = 0.0

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	$CameraPivot/SpringArm3D.add_excluded_object(self.get_rid())

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
		# Camera Rotation
		camera_pivot.rotate_y(-event.relative.x * CAMERA_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * CAMERA_SENSITIVITY)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -0.5, 0.5)

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
	var collider: Object = hit.get("collider", null)
	if collider == null or not collider.has_method("take_damage"):
		collider = _find_melee_target(origin, look_dir)
	if collider == null:
		print("3. Attack Hawa Mein Gaya (Miss)")
		return
	collider.call("take_damage", ATTACK_DAMAGE)
	print("4. HIT ENEMY SUCCESS!")

func _find_melee_target(origin: Vector3, look_dir: Vector3) -> Object:
	var attack_shape: SphereShape3D = SphereShape3D.new()
	attack_shape.radius = ATTACK_HIT_RADIUS
	var shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	shape_query.shape = attack_shape
	shape_query.collision_mask = 4
	shape_query.exclude = [self.get_rid()]
	for distance: float in [ATTACK_RANGE * 0.6]:
		shape_query.transform = Transform3D(Basis.IDENTITY, origin + look_dir * distance)
		var results: Array = get_world_3d().direct_space_state.intersect_shape(shape_query, 8)
		for result: Dictionary in results:
			var target: Object = result.get("collider", null)
			if target != null and target.has_method("take_damage"):
				return target
	return null

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
