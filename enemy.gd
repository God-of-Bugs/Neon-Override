class_name Enemy
extends CharacterBody3D

## Chases the player using NavigationAgent3D pathfinding.
##
## Avoidance is enabled on the agent, so this script never moves the body
## directly: it hands an intended velocity to the agent with set_velocity(),
## and the NavigationServer answers on velocity_computed() with a "safe"
## velocity that steers around the other enemies.

const SPEED: float = 4.5  # deliberately slower than the player's 6.0
const MAX_HEALTH: int = 30

@onready var agent: NavigationAgent3D = $NavigationAgent3D

var health: int = MAX_HEALTH
var _player: Node3D = null


func _ready() -> void:
	agent.velocity_computed.connect(_on_velocity_computed)
	# The navigation map is not synchronised until the first physics frame,
	# so wait one frame before asking the agent for a path.
	await get_tree().physics_frame
	_acquire_player()


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

	# The agent resolves this against the other avoidance agents and replies on
	# velocity_computed(), which is where the body actually moves.
	agent.set_velocity(intended_velocity)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()


func take_damage(amount: int) -> void:
	health -= amount
	print(name, " took ", amount, " damage - ", health, " hp left")
	if health <= 0:
		queue_free()


func _acquire_player() -> void:
	var found: Node = get_tree().get_first_node_in_group("player")
	_player = found as Node3D
	if _player != null:
		agent.target_position = _player.global_position
