class_name MainWorld
extends Node3D

## Wires the level together: it is the only place that knows about both the
## player and the HUD, so the player can stay ignorant of the UI layer.

@onready var player: Player = $Player
@onready var ui_manager: UIManager = $UIManager


func _ready() -> void:
	player.health_changed.connect(ui_manager.update_health)
	# Push the starting health so the bar matches the player from frame one.
	ui_manager.update_health(player.current_health)
