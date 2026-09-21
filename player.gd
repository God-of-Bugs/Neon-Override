extends CharacterBody3D

const SPEED = 5.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_attacking = false
var anim_player : AnimationPlayer

func _ready():
	# Mouse ko lock karein
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Yeh function pure Model mein AnimationPlayer khud dhoondh lega (No crash)
	anim_player = find_child("AnimationPlayer", true, false)

func _unhandled_input(event):
	# Camera Setup - Mouse se ghoomne ke liye
	if event is InputEventMouseMotion:
		$CameraPivot.rotate_y(-event.relative.x * 0.003)
		$CameraPivot/SpringArm3D.rotate_x(-event.relative.y * 0.003)
		# Camera ko bohot upar/neeche jaane se rokna
		$CameraPivot/SpringArm3D.rotation.x = clamp($CameraPivot/SpringArm3D.rotation.x, -1.0, 1.0)
		
	# ESC dabane par mouse wapas aaye aur lock ho
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Attack Logic (Space / Enter)
	if Input.is_action_just_pressed("ui_accept") and not is_attacking:
		is_attacking = true
		velocity.x = 0
		velocity.z = 0
		play_safe_anim("Attack")
		# Animation complete hone ke liye wait karein
		await get_tree().create_timer(0.6).timeout 
		is_attacking = false

	if is_attacking:
		move_and_slide()
		return

	# Proper Camera-Relative Movement
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = ($CameraPivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		
		# Character ko smooth ghumana, sirf flat zameen par (Y-axis mix na ho)
		var look_target = global_position - direction
		look_target.y = global_position.y 
		
		if not global_position.is_equal_approx(look_target):
			$Model.look_at(look_target, Vector3.UP)
			
		play_safe_anim("Run")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		play_safe_anim("Idle")

	move_and_slide()

# Safely animation play karne ka function
func play_safe_anim(anim_name: String):
	if anim_player == null:
		return
	
	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
	elif anim_player.has_animation(anim_name.to_lower()):
		anim_player.play(anim_name.to_lower())
