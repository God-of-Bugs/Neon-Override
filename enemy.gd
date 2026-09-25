class_name Enemy
extends CharacterBody3D

const SPEED: float = 4.5
const MAX_HEALTH: int = 30
const ATTACK_RANGE: float = 2.2

const ROUGE_SCENE: PackedScene = preload("res://materials/glb file/Rogue.glb")

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var hit_sparks: GPUParticles3D = $HitSparks
@onready var hit_sound: AudioStreamPlayer3D = $HitSound

# YAHAN DHYAN DENA: Apne Enemy ke AnimationPlayer ka path yahan sahi dalna
@onready var anim_player: AnimationPlayer = find_child("AnimationPlayer", true, false)

var health: int = MAX_HEALTH
var attack_damage: int = 10
var attack_cooldown: float = 1.0
var time_since_last_attack: float = 0.0
var _player: Node3D = null

func _ready() -> void:
	agent.velocity_computed.connect(_on_velocity_computed)
	await get_tree().physics_frame
	_acquire_player()
	_setup_animations()
	call_deferred("_spawn_rogue_model")

func _setup_animations() -> void:
	if not anim_player:
		return
	var anim_running = Animation.new()
	anim_running.length = 0.5
	anim_running.resource_name = "running"
	
	var anim_idle = Animation.new()
	anim_idle.length = 0.5
	anim_idle.resource_name = "idle"
	
	var anim_punch = Animation.new()
	anim_punch.length = 0.5
	anim_punch.resource_name = "punch"
	
	var library = AnimationLibrary.new()
	library.add_animation("running", anim_running)
	library.add_animation("idle", anim_idle)
	library.add_animation("punch", anim_punch)
	anim_player.add_animation_library("", library)

func _spawn_rogue_model() -> void:
	if ROUGE_SCENE == null:
		push_error("Enemy: ROUGE_SCENE is null!")
		return
	var rogue_model = ROUGE_SCENE.instantiate()
	if rogue_model != null:
		add_child(rogue_model)
		rogue_model.scale = Vector3(1.75, 1.75, 1.75)

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

	# Enemies remain at their assigned spawn positions. They only attack when the player approaches.

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
