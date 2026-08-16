extends CharacterBody2D

const SPEED = 85.0
const DASH_SPEED = 150.0
const GRAVITY: float = 900.0

var input_vector: float = 0.0 # Direction
var last_input_vector: float = 1.0 # Direction after input key
var can_dash: bool = true
const DASH_CD: float = 0.5 # Dash CD
var can_attack: bool = true
const ATTACK_CD: float = 0.3 # Attack CD

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var playback = animation_tree.get("parameters/StateMachine/playback") as AnimationNodeStateMachinePlayback

@onready var sprite_2d: Sprite2D = $Sprite2D


func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity.x = 0
		move_and_slide()
		return
	# === 新增：重力（让主角稳稳站在地平线上）===
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		if velocity.y > 900.0:
			velocity.y = 900.0

	var state = playback.get_current_node()
	
	if state == "ShieldState":
		shield_timer += delta
	else:
		shield_timer = 0.0

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
	sprite_2d.modulate.a = 1.0
	input_vector = Input.get_axis("move_left", "move_right")

	# Turning right or left
	if input_vector < 0:
		sprite_2d.flip_h = true
		sprite_2d.offset.x = -10
		$SwordHitbox.position.x = -1 # Hit left when facing left
	elif input_vector > 0:
		sprite_2d.flip_h = false
		sprite_2d.offset.x = 0
		$SwordHitbox.position.x = 1 # Vice Versa

	if input_vector != 0.0:
		last_input_vector = input_vector
		update_animation_parameters()

	if Input.is_action_just_pressed("attack_1") and can_attack:
		can_attack = false
		$SwordHitbox.damage = 1
		playback.travel("AttackState")
		start_attack_cooldown()

	if Input.is_action_just_pressed("attack_2") and can_attack:
		can_attack = false
		
		var is_execute = randf() < 0.1 # One-time kill
		if is_execute:
			$SwordHitbox.damage = 999  
		else:
			$SwordHitbox.damage = 2 
			
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
	sprite_2d.modulate.a = 0.5
	velocity.x = last_input_vector * DASH_SPEED
	move_and_slide()

	if Input.is_action_just_pressed("attack_1") and can_attack:
		can_attack = false
		playback.travel("AttackState")
		start_attack_cooldown()

	if Input.is_action_just_pressed("attack_2") and can_attack:
		can_attack = false
		
		var is_execute = randf() < 0.1 # One-time kill
		if is_execute:
			$SwordHitbox.damage = 999  
		else:
			$SwordHitbox.damage = 2 
			
		playback.travel("AttackState2")
		start_attack_cooldown()

	if Input.is_action_just_pressed("shield"):
		playback.travel("ShieldState")


func shield_state(delta: float) -> void:
	if Input.is_action_just_pressed("attack_1") and can_attack:
		can_attack = false
		playback.travel("AttackState")
		start_attack_cooldown()

	if Input.is_action_just_pressed("attack_2") and can_attack:
		can_attack = false
		
		var is_execute = randf() < 0.1 # One-time kill
		if is_execute:
			$SwordHitbox.damage = 999  
		else:
			$SwordHitbox.damage = 2 
			
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
@export var max_hp: int = 3
## 主角当前生命值
var hp: int = 3
## 记录当前举盾持续了多久（秒）
var shield_timer: float = 0.0
## 记录成功弹反的次数（满2次清零并回血）
var parry_count: int = 0
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
	add_to_group("player")
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

# 👇 参数里加上 source: Area2D = null，接收打人的怪物武器
func take_damage(amount: int, source: Area2D = null) -> void:
	if _is_dead or amount <= 0:
		return

	var cur_state: StringName = playback.get_current_node()

	# [1] 闪避状态：完全无敌
	if cur_state == "DashState":
		return

	# [2] 护盾状态：完全无敌 + 完美弹反检测
	if cur_state == "ShieldState":
		# 如果举盾时间小于等于 0.1 秒，触发完美弹反！
		if shield_timer <= 0.11:
			print("⚡ 完美弹反！")
			
			# 弹反计数与回血逻辑
			parry_count += 1
			if parry_count >= 2:
				parry_count = 0
				hp = min(hp + 1, max_hp) # 恢复 1 点生命，但不超过上限
				emit_signal("health_changed", hp, max_hp)
				print("💚 弹反两次，恢复1点生命！")
			
			# 对敌人造成反伤与强力击退
			if source and source.owner and source.owner.has_method("take_damage"):
				# 赋予怪物一个极其强烈的反向击退力 (400.0)
				source.owner.velocity.x = sign(source.owner.global_position.x - global_position.x) * 400.0
				# 强制造成 1 点反伤（这会直接打断怪物的攻击动作）
				source.owner.take_damage(1)
				
		return # ⚠️ 核心：只要是举盾状态，不管是不是完美弹反，都不掉血，直接结束！

	# [3] 正常受伤逻辑
	hp -= amount
	emit_signal("health_changed", hp, max_hp)

	# 只在"可被打断"的移动状态才额外切 hurt 动画
	if cur_state == "MoveState" or cur_state == "StandState":
		playback.travel("HurtState")

	if hp <= 0 and not _is_dead:
		_die()

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	emit_signal("died")
	# 关闭碰撞，避免尸体还继续被打
	collision_layer = 0
	remove_from_group("player")
	name = "Death" # Prevent from being tracked by enemy

	_set_sword_hitbox_active(false, true)

	if animation_tree:
		animation_tree.active = false
	
	velocity.x = 0

	if $AnimationPlayer and $AnimationPlayer.has_animation("death"):
		$AnimationPlayer.play("death")
