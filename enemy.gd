class_name Enemy
extends CharacterBody3D

const SPEED: float = 4.5
const MAX_HEALTH: int = 30
const ATTACK_DAMAGE: int = 15
const ATTACK_RANGE: float = 2.5
const ATTACK_COOLDOWN: float = 0.5

const ROUGE_SCENE: PackedScene = preload("res://materials/glb file/Rogue.glb")

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var hit_sparks: GPUParticles3D = $HitSparks
@onready var hit_sound: AudioStreamPlayer3D = $HitSound

# YAHAN DHYAN DENA: Apne Enemy ke AnimationPlayer ka path yahan sahi dalna
@onready var anim_player: AnimationPlayer = find_child("AnimationPlayer", true, false)

var health: int = MAX_HEALTH
var attack_damage: int = ATTACK_DAMAGE
var attack_cooldown: float = ATTACK_COOLDOWN
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
		rogue_model.position.y = 0.004

func _process(delta: float) -> void:
	time_since_last_attack += delta
	if _player == null:
		return
	if time_since_last_attack < attack_cooldown:
		return
		
	# Symmetric melee check: nearby player, any angle, with wall blocking.
	var origin: Vector3 = global_position + Vector3(0, 1.0, 0)
	if _find_melee_player(origin):
		_attack_player()

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
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target_point, 3)
	query.exclude = [self.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider", null) == target

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

	if agent.avoidance_enabled:
		agent.set_velocity(intended_velocity)
	else:
		_on_velocity_computed(intended_velocity)

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
