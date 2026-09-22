class_name Enemy
extends CharacterBody3D

## Chases the player using NavigationAgent3D pathfinding.
##
## Avoidance is enabled on the agent, so this script never moves the body
## directly: it hands an intended velocity to the agent with set_velocity(),
## and the NavigationServer answers on velocity_computed() with a "safe"
## velocity that steers around the other enemies.

const SPEED: float = 4.5  # deliberately slower than the player's 5.0
const MAX_HEALTH: int = 30
const ATTACK_RANGE: float = 1.5  # metres between origins

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var hit_sparks: GPUParticles3D = $HitSparks
@onready var hit_sound: AudioStreamPlayer3D = $HitSound
@onready var anim_player: AnimationPlayer = $EnemyModel/AnimationPlayer

var health: int = MAX_HEALTH
var attack_damage: int = 10
var attack_cooldown: float = 1.0
var time_since_last_attack: float = 0.0
var _player: Node3D = null


func _ready() -> void:
	agent.velocity_computed.connect(_on_velocity_computed)
	# The navigation map is not synchronised until the first physics frame,
	# so wait one frame before asking the agent for a path.
	await get_tree().physics_frame
	_acquire_player()


func _process(delta: float) -> void:
	# The cooldown keeps ticking even while out of range, so an enemy that has
	# just walked up to the player can strike straight away.
	time_since_last_attack += delta
	if _player == null:
		return
	if time_since_last_attack < attack_cooldown:
		return
	if global_position.distance_to(_player.global_position) < ATTACK_RANGE:
		_attack_player()


func _physics_process(delta: float) -> void:
	# Keep re-acquiring in case the player is spawned after the enemies.
	if _player == null:
		_acquire_player()

	var intended_velocity: Vector3 = Vector3.ZERO

	# Stay glued to the ground, or fall if we ended up off an edge.
	if is_on_floor():
		intended_velocity.y = 0.0
	else:
		intended_velocity.y = velocity.y + get_gravity().y * delta

	if _player != null:
		# Constantly re-target the agent at the player's current position.
		agent.target_position = _player.global_position

		if not agent.is_navigation_finished():
			var next_position: Vector3 = agent.get_next_path_position()
			var direction: Vector3 = next_position - global_position
			direction.y = 0.0
			direction = direction.normalized()
			intended_velocity.x = direction.x * SPEED
			intended_velocity.z = direction.z * SPEED

	# Play animation based on movement state.
	if anim_player and intended_velocity.length() > 0.1:
		if not anim_player.is_playing() or anim_player.current_animation != "running":
			anim_player.play("running")
	elif anim_player:
		if not anim_player.is_playing() or anim_player.current_animation != "idle":
			anim_player.play("idle")

	# The agent resolves this against the other avoidance agents and replies on
	# velocity_computed(), which is where the body actually moves.
	agent.set_velocity(intended_velocity)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()


func take_damage(amount: int) -> void:
	health -= amount
	print(name, " took ", amount, " damage - ", health, " hp left")
	hit_sparks.emitting = true
	hit_sparks.restart()
	hit_sound.play()
	if anim_player:
		anim_player.play("punch")
	if health <= 0:
		queue_free()


func _attack_player() -> void:
	time_since_last_attack = 0.0
	if anim_player:
		anim_player.play("punch")
	if _player.has_method("take_damage"):
		print(name, " attacks the player for ", attack_damage)
		_player.call("take_damage", attack_damage)


func _acquire_player() -> void:
	var found: Node = get_tree().get_first_node_in_group("player")
	_player = found as Node3D
	if _player != null:
		agent.target_position = _player.global_position
