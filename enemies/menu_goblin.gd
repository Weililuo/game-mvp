extends CharacterBody2D

@export var move_speed: float = 60.0         
@export var min_x: float = 20.0             
@export var max_x: float = 300.0              
@export var start_direction: float = 1.0      

enum State { WALK, IDLE }
var state: State = State.WALK

var direction: float = 1.0
var state_timer: float = 0.0

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	direction = start_direction
	_update_facing()
	_enter_walk()

func _physics_process(delta: float) -> void:
	state_timer -= delta
	
	match state:
		State.WALK:
			velocity.x = direction * move_speed
			
			if position.x >= max_x:
				position.x = max_x
				direction = -1.0
				_update_facing()
			elif position.x <= min_x:
				position.x = min_x
				direction = 1.0
				_update_facing()
			elif state_timer <= 0:
				_enter_idle()

		State.IDLE:
			velocity.x = 0.0
			if state_timer <= 0:
				if position.x >= max_x - 10:
					direction = -1.0
				elif position.x <= min_x + 10:
					direction = 1.0
				else:
					if randf() < 0.3:
						direction *= -1.0
				_update_facing()
				_enter_walk()

	move_and_slide()

func _enter_walk() -> void:
	state = State.WALK
	state_timer = randf_range(2.0, 4.0) 
	if anim and anim.has_animation("run"):
		anim.play("run")

func _enter_idle() -> void:
	state = State.IDLE
	state_timer = randf_range(0.3, 0.6) 
	if anim and anim.has_animation("idle"):
		anim.play("idle")

func _update_facing() -> void:
	if sprite:
		sprite.scale.x = abs(sprite.scale.x) * direction