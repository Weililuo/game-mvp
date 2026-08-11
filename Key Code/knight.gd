extends CharacterBody2D

const SPEED = 85.0
const DASH_SPEED = 150.0

var input_vector: float = 0.0 # Direction
var last_input_vector: float = 1.0 # Direction after input key
var can_dash: bool = true
const DASH_CD: float = 0.6 # Dash CD
var can_attack: bool = true
const ATTACK_CD: float = 0.3 # Attack CD

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var playback = animation_tree.get("parameters/StateMachine/playback") as AnimationNodeStateMachinePlayback

@onready var sprite_2d: Sprite2D = $Sprite2D


func _physics_process(delta: float) -> void:
	var state = playback.get_current_node()
	match state:
		"MoveState":
			move_state(delta)

		"AttackState":
			pass

		"AttackState2":
			pass

		"DashState":
			dash_state(delta)

		"ShieldState":
			shield_state(delta)


# Move Logic
func move_state(delta: float) -> void:
	input_vector = Input.get_axis("move_left", "move_right")

	# Turning right or left
	if input_vector < 0:
		sprite_2d.flip_h = true
		sprite_2d.offset.x = -10
	elif input_vector > 0:
		sprite_2d.flip_h = false
		sprite_2d.offset.x = 0

	if input_vector != 0.0:
		last_input_vector = input_vector
		update_animation_parameters()

	if Input.is_action_just_pressed("attack_1") and can_attack:
		can_attack = false
		playback.travel("AttackState")
		start_attack_cooldown()

	if Input.is_action_just_pressed("attack_2") and can_attack:
		can_attack = false
		playback.travel("AttackState2")
		start_attack_cooldown()

	if Input.is_action_just_pressed("dash") and can_dash:
		can_dash = false # In CD, can't use dash at the moment
		playback.travel("DashState")
		start_dash_cooldown() # Set timer

	if Input.is_action_just_pressed("shield"):
		playback.travel("ShieldState")

	velocity.x = input_vector * SPEED
	move_and_slide()


# Dash Function
func dash_state(delta: float) -> void:
	velocity.x = last_input_vector * DASH_SPEED
	move_and_slide()

	if Input.is_action_just_pressed("attack_1") and can_attack:
		can_attack = false
		playback.travel("AttackState")
		start_attack_cooldown()

	if Input.is_action_just_pressed("attack_2") and can_attack:
		can_attack = false
		playback.travel("AttackState2")
		start_attack_cooldown()
	
	if Input.is_action_just_pressed("shield"):
		playback.travel("ShieldState")


func shield_state(delta: float) -> void:
	if Input.is_action_just_pressed("attack_1") and can_attack:
		can_attack = false
		playback.travel("AttackState")
		start_attack_cooldown()

	elif Input.is_action_just_pressed("attack_2") and can_attack:
		can_attack = false
		playback.travel("AttackState2")
		start_attack_cooldown()

	elif Input.is_action_just_pressed("dash") and can_dash:
		can_dash = false
		playback.travel("DashState")
		start_dash_cooldown()


func start_dash_cooldown() -> void:
	get_tree().create_timer(DASH_CD).timeout.connect(
		func():
			can_dash = true,
	)


func start_attack_cooldown() -> void:
	get_tree().create_timer(ATTACK_CD).timeout.connect(
		func():
			can_attack = true,
	)


func update_animation_parameters() -> void:
	var move_speed = abs(input_vector)
	animation_tree.set(
		"parameters/StateMachine/MoveState/RunState/blend_position",
		abs(input_vector),
	)
	animation_tree.set(
		"parameters/StateMachine/MoveState/StandState/blend_position",
		abs(input_vector),
	)
