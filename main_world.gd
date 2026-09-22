class_name MainWorld
extends Node3D

## Wires the level together: it is the only place that knows about both the
## player and the HUD, so the player can stay ignorant of the UI layer.

@onready var player: Player = $Player
@onready var ui_manager: UIManager = $UIManager

func _ready() -> void:
	# Player ki health ab HUD ke health bar se judi hai
	player.health_changed.connect(ui_manager.update_health)
	# Shuruaat mein ek baar bar set kar do
	ui_manager.update_health(player.current_health)
