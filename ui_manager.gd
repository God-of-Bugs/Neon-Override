class_name UIManager
extends CanvasLayer

## HUD layer: a health bar that mirrors the player's health, and a game-over
## panel that appears when the player dies.
##
## The player never touches this node directly - MainWorld connects the
## player's health_changed signal to update_health(), and the player asks for
## this layer through the "ui_manager" group when it dies.

@onready var health_bar: ProgressBar = $HealthBar
@onready var game_over_panel: Panel = $GameOverPanel
@onready var game_over_sound: AudioStreamPlayer = $GameOverSound


func _ready() -> void:
	game_over_panel.visible = false


## Mirrors the player's current health onto the bar.
func update_health(value: int) -> void:
	health_bar.value = float(value)


## Reveals the game-over panel and hands the mouse back to the player so the
## Restart button can be clicked.
func show_game_over() -> void:
	game_over_panel.visible = true
	game_over_sound.play()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()
