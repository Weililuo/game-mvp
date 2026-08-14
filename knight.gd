extends CharacterBody2D

const SPEED = 85.0
const DASH_SPEED = 150.0
const GRAVITY: float = 900.0

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
	# === 新增：重力（让主角稳稳站在地平线上）===
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		if velocity.y > 900.0:
			velocity.y = 900.0

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

	# ===== 新增：SwordHitbox 随攻击状态自动开关 =====
	var in_attack: bool = (state == "AttackState" or state == "AttackState2")
	_set_sword_hitbox_active(in_attack)


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


# =============================================================
#  与小怪 Enemy 攻击/受击兼容而追加：生命值、受击、闪避无敌、护盾抵挡
# =============================================================

## 主角最大生命值
@export var max_hp: int = 100
## 主角当前生命值
var hp: int = 100
## 护盾状态下减伤比例（1.0 = 完全免伤，0.5 = 承受一半伤害）
@export var shield_damage_reduction: float = 1.0
## 是否已死亡（防止死亡逻辑重复触发）
var _is_dead: bool = false
## SwordHitbox 当前是否开启（缓存，减少每帧属性写操作）
var _sword_hitbox_active_cache: bool = false

## 血量变化信号（供 UI/屏幕震动/音效订阅）
signal health_changed(new_hp: int, max: int)
signal died()

## 主角攻击判定盒（场景节点名 = SwordHitbox，队友已配置）
@onready var _sword_hitbox: Hitbbox = get_node_or_null("SwordHitbox") as Hitbbox
## 若场景中挂了 Hurtbox 节点，这里可以绑定它（可选；用 get_node_or_null 避免没有节点时直接崩溃）
@onready var _hurtbox: Hurtbox = get_node_or_null("Hurtbox") as Hurtbox


func _ready() -> void:
	hp = max_hp
	emit_signal("health_changed", hp, max_hp)
	# 默认关闭 SwordHitbox——只在进入攻击状态时才开启
	_set_sword_hitbox_active(false, true)


## 开启/关闭主角攻击判定盒
## - 只在 AttackState / AttackState2 期间开启，避免"贴近就掉血"
func _set_sword_hitbox_active(active: bool, force: bool = false) -> void:
	if (not force) and active == _sword_hitbox_active_cache:
		return
	_sword_hitbox_active_cache = active
	if _sword_hitbox:
		_sword_hitbox.monitoring = active
		_sword_hitbox.monitorable = active


## 小怪（或主角自身 Hurtbox）调用此函数对主角造成伤害。
## 规则：
##   * 正在 Dash → 完全闪避（伤害 = 0），对应"闪避"能力
##   * 正在 Shield → 按 shield_damage_reduction 减伤，对应"防御护盾"
func take_damage(amount: int) -> void:
	if _is_dead or amount <= 0:
		return

	var cur_state: StringName = playback.get_current_node()

	# [1] 闪避状态：完全不受伤
	if cur_state == "DashState":
		return

	# [2] 护盾状态：按比例减伤
	var final_damage: int = amount
	if cur_state == "ShieldState":
		final_damage = int(round(amount * (1.0 - shield_damage_reduction)))

	if final_damage <= 0:
		return

	hp -= final_damage
	emit_signal("health_changed", hp, max_hp)

	# 只在"可被打断"的移动状态才额外切 hurt 动画，避免覆盖攻击/护盾/闪避的动作
	if cur_state == "MoveState" and $AnimationPlayer.has_animation("hurt"):
		$AnimationPlayer.play("hurt")

	if hp <= 0 and not _is_dead:
		_die()


func _die() -> void:
	_is_dead = true
	emit_signal("died")
	# 关闭碰撞，避免尸体还继续被打
	collision_layer = 0
	collision_mask = 0
	_set_sword_hitbox_active(false, true)
	if $AnimationPlayer and $AnimationPlayer.has_animation("death"):
		$AnimationPlayer.play("death")
		await $AnimationPlayer.animation_finished
	queue_free()
