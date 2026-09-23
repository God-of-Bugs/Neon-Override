class_name Enemy
extends CharacterBody3D

const SPEED: float = 4.5
const MAX_HEALTH: int = 30
const ATTACK_RANGE: float = 2.2 

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var hit_sparks: GPUParticles3D = $HitSparks
@onready var hit_sound: AudioStreamPlayer3D = $HitSound

# YAHAN DHYAN DENA: Apne Enemy ke AnimationPlayer ka path yahan sahi dalna
@onready var anim_player: AnimationPlayer = $AnimationPlayer

var health: int = MAX_HEALTH
var attack_damage: int = 10
var attack_cooldown: float = 1.0
var time_since_last_attack: float = 0.0
var _player: Node3D = null

func _ready() -> void:
	agent.velocity_computed.connect(_on_velocity_computed)
	await get_tree().physics_frame
	_acquire_player()

func _process(delta: float) -> void:
	time_since_last_attack += delta
	if _player == null:
		return
	if time_since_last_attack < attack_cooldown:
		return
		
	# Distance check taaki Enemy range mein aate hi attack kare
	var dist = Vector2(global_position.x, global_position.z).distance_to(Vector2(_player.global_position.x, _player.global_position.z))
	if dist <= ATTACK_RANGE:
		_attack_player()

func _physics_process(delta: float) -> void:
	if _player == null:
		_acquire_player()

	var intended_velocity: Vector3 = Vector3.ZERO

	if is_on_floor():
		intended_velocity.y = 0.0
	else:
		intended_velocity.y = velocity.y + get_gravity().y * delta

	if _player != null:
		agent.target_position = _player.global_position
		
		# Enemy hamesha Player ki aakhon mein dekhega
		var look_target = Vector3(_player.global_position.x, global_position.y, _player.global_position.z)
		if global_position.distance_to(look_target) > 0.1:
			look_at(look_target, Vector3.UP)

		var dist_to_player = Vector2(global_position.x, global_position.z).distance_to(Vector2(_player.global_position.x, _player.global_position.z))
		
		# Brake System - Agar attack range mein hai, toh chalna band kar dega
		if dist_to_player > ATTACK_RANGE * 0.8:
			if not agent.is_navigation_finished():
				var next_position: Vector3 = agent.get_next_path_position()
				var direction: Vector3 = next_position - global_position
				direction.y = 0.0
				direction = direction.normalized()
				intended_velocity.x = direction.x * SPEED
				intended_velocity.z = direction.z * SPEED

	# ENEMY ANIMATION LOGIC
	if anim_player:
		var is_punching = (anim_player.current_animation == "punch" and anim_player.is_playing())
		if not is_punching:
			var horizontal_vel = Vector2(intended_velocity.x, intended_velocity.z)
			if horizontal_vel.length() > 0.1:
				if not anim_player.is_playing() or anim_player.current_animation != "running":
					anim_player.play("running")
			else:
				if not anim_player.is_playing() or anim_player.current_animation != "idle":
					anim_player.play("idle")

	agent.set_velocity(intended_velocity)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()

func take_damage(amount: int) -> void:
	health -= amount
	if hit_sparks:
		hit_sparks.emitting = true
		hit_sparks.restart()
	if hit_sound:
		hit_sound.play()
		
	# Damage padne par bhi thodi der ke liye attack/punch hilega
	if anim_player:
		anim_player.play("punch")
		
	if health <= 0:
		queue_free()

func _attack_player() -> void:
	time_since_last_attack = 0.0
	
	# Attack animation play karna
	if anim_player:
		anim_player.play("punch")
		
	if _player and _player.has_method("take_damage"):
		_player.call("take_damage", attack_damage)

func _acquire_player() -> void:
	var found: Node = get_tree().get_first_node_in_group("player")
	_player = found as Node3D
	if _player != null:
		agent.target_position = _player.global_position
