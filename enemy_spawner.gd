extends Node3D

@export var max_enemies: int = 5
@export var spawn_interval: float = 3.0

var enemies_spawned: int = 0
var timer: Timer

func _ready():
	timer = get_node_or_null("Timer")
	if timer == null:
		timer = Timer.new()
		timer.name = "Timer"
		add_child(timer)
		
	timer.wait_time = spawn_interval
	timer.autostart = true
	timer.timeout.connect(_on_timer_timeout)
	timer.start()
	
	_spawn_enemy()

func _on_timer_timeout():
	if enemies_spawned >= max_enemies:
		timer.stop()
		print("Saare enemies aa chuke hain! Wave Complete.")
		return
		
	_spawn_enemy()

func _spawn_enemy():
	var enemy = load("res://Enemy.tscn").instantiate()
	var random_x = randf_range(-3.0, 3.0)
	var random_z = randf_range(-3.0, 3.0)
	get_tree().current_scene.call_deferred("add_child", enemy)
	enemy.call_deferred("set_global_position", global_position + Vector3(random_x, 0.5, random_z))
	enemies_spawned += 1
	print("Naya Enemy Aaya! Total: ", enemies_spawned)
