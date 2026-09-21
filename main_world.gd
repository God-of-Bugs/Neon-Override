class_name MainWorld
extends Node3D

## Wires the level together: it is the only place that knows about both the
## player and the HUD, so the player can stay ignorant of the UI layer.

# Yahan se ': Player' hata diya hai taaki Line 7 wala error na aaye
@onready var player = $Player
@onready var ui_manager = $UIManager

func _ready() -> void:
	# In lines ko abhi '#' lagakar band kar diya hai kyunki naye player mein health nahi hai.
	# Jab hum health add karenge, tab inhe wapas chalu kar lenge.
	pass
	# player.health_changed.connect(ui_manager.update_health)
	# ui_manager.update_health(player.current_health)
