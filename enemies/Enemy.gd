extends CharacterBody2D
## ============================================================================
## 小怪（Enemy / Goblin）核心控制脚本
## ----------------------------------------------------------------------------
## 功能清单：
##   1. 基础属性：攻击力 / 最大生命 / 当前生命 / 移动速度 / 跳跃力 / 攻击范围
##   2. AI 状态机：IDLE ↔ CHASE ↔ ATTACK ↔ HURT ↔ DEAD 5 个状态
##   3. 感知锁定：通过 DetectionArea（Area2D）进入视野 → 锁目标；body_exited 仍保持追击，
##               仅当超过 MAX_CHASE_DIST 才 IDLE。_ready 主动扫一次主角兜底。
##   4. 核心动作：CHASE 下自动移动 + 面朝目标 + 遇墙/台阶自动跳；ATTACK 下播放 attack 动画，
##               在 method track 到第 6 帧 0.12s 左右 _open_attack_hitbox()，0.32s 左右关。
##               另外配 2 个 SceneTreeTimer 做超时强制开关，防止关键帧失效。
##   5. 受击：通过 Hurtbox.take_hit → Enemy.take_damage(hp 减伤 → 切 HURT 状态 → 动画 finished → 回 CHASE)
##   6. 死亡：hp ≤ 0 → 切 DEAD 播放 death（2 秒，行 0~6 帧）→ 结束自动 queue_free。
##               2 秒超时兜底，即使动画卡了也能销毁。
##   7. 兼容主角：hitbox 伤害通过 area_entered（Hurtbox）/ body_entered（Knight 没独立 Hurtbox 时）
##                 调用 knight.gd 的 take_damage(amount)，这样 Dash=0 伤、Shield=减伤（与队友逻辑一致）
## ============================================================================

const GRAVITY: float    = 1000.0
const JUMP_VELOCITY: float  = -300.0

## ----------------------------------------------------------------------------
## 状态枚举
## ----------------------------------------------------------------------------
enum State {
	IDLE,    ## 没目标 / 距离太远：播 idle
	CHASE,   ## 有目标且不在攻击范围：朝目标移动 + 跳 + 调整朝向
	ATTACK,  ## 进入 attack_range：播 attack + 开/关 hitbox
	HURT,    ## 被攻击命中：播 hurt 后退，结束回 CHASE
	DEAD     ## hp ≤ 0：播 death → queue_free
}

## 当前状态（IDLE 启动）
@export var state: State = State.IDLE

## ----------------------------------------------------------------------------
##  基础数据
## ----------------------------------------------------------------------------
@export var attack: int = 1                   	## 小怪每次攻击造成的伤害
@export var max_hp: int = 3                    	## 小怪最大生命
@export var move_speed: float = 60.0            ## 追击速度（像素/秒）
@export var jump_force: float = JUMP_VELOCITY   ## 跳跃速度（负值向上）
@export var attack_range: float = 14.0          ## 攻击触发范围（像素）
@export var attack_cd: float = 1.0              ## 攻击结束到下次可攻击的冷却
@export var stop_zone: float = 14           	## 距离小于该值停下（防止穿过目标反复晃）
@export var MAX_CHASE_DIST: float = 600.0       ## 超过这个距离后放弃追击（回 IDLE）
@export var hurt_pushback: float = 200.0         ## 被打瞬间反推速度（越小越不"飞"）
@export var hurt_back_duration: float = 0.18    ## 被打硬直（秒）—— 足够播完 hurt 动画

var hp: int = max_hp
var can_attack: bool = true                     ## attack_cd 是否结束
var _hitting_enemies: Dictionary = {}           ## 本次攻击命中过的敌人（防止挥一刀多次结算）
var _target: CharacterBody2D                     ## 锁定目标（主角 knight）

## ----------------------------------------------------------------------------
## 节点引用（用 get_node_or_null，避免手滑拖节点路径导致崩溃）
## ----------------------------------------------------------------------------
@onready var _anim: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var _attack_hitbox: Area2D = get_node_or_null("AttackHitbox") as Area2D
@onready var _detection_area: Area2D = get_node_or_null("DetectionArea") as Area2D
@onready var _hurtbox: Area2D = get_node_or_null("Hurtbox") as Area2D

## ============================================================================
##  1. _ready：初始化节点、HP、组、信号连接
## ============================================================================
func _ready() -> void:
	# —— 把自己加入 enemies 组，方便主角攻击统一筛
	add_to_group("enemies")

	# —— 当前 HP = 最大 HP
	hp = max_hp

	# —— 攻击盒初始关闭（等待 attack 动画第 6 帧开）
	if _attack_hitbox:
		_attack_hitbox.monitoring = false
		_attack_hitbox.monitorable = false
		if _attack_hitbox.has_method("set_damage"):
			_attack_hitbox.set_damage(attack)
		_attack_hitbox.area_entered.connect(_on_attack_hit_area) # Delete the rundundant one 

	# —— 感知区：主角进入时锁目标
	if _detection_area:
		_detection_area.area_entered.connect(_on_detect_area_entered)
		_detection_area.body_entered.connect(_on_detect_body_entered)

	# —— Hurtbox（自身受击盒）：由 hitbox.gd 调用 area.take_hit(dmg, src)
	if _hurtbox:
		if not _hurtbox.has_method("take_hit"):
			# Hurtbox 没有脚本时直接连上自身 take_damage 兜底（防止手忘挂 Hurtbox 脚本）
			_hurtbox.area_entered.connect(func(area: Area2D):
				if area.has_method("get_damage") and is_instance_valid(area):
					take_damage(area.get_damage())
			)

	# —— 主动兜底扫一次主角（防止 DetectionArea 初始化晚错过主角进入）
	_scan_target_fallback()

	# —— 默认播放 idle，保证第一帧就有正确姿势
	if _anim and _anim.has_animation("idle"):
		_anim.play("idle")


## ============================================================================
##  2. 感知：DetectionArea 信号回调 + Fallback 主动扫描
## ============================================================================
func _on_detect_body_entered(body: Node) -> void:
	_lock_target_if_player(body)

func _on_detect_area_entered(area: Area2D) -> void:
	if area.get_parent() and area.get_parent() is CharacterBody2D:
		_lock_target_if_player(area.get_parent())


## 兜底：如果 DetectionArea 没有触发（或场景打开时主角已经在感知里），主动查一次
func _scan_target_fallback() -> void:
	if is_instance_valid(_target):
		return
	const DETECT_RADIUS_SQ: float = 300.0 * 300.0

	# (a) 查 player 组
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if p is CharacterBody2D and is_instance_valid(p):
			var d_sq: float = global_position.distance_squared_to(p.global_position)
			if d_sq < DETECT_RADIUS_SQ:
				_target = p
				_set_state(State.CHASE)
				return

	# (b) 查名字含 Player / Knight
	var root = get_tree().current_scene if get_tree() else null
	if root:
		for n in root.find_children("*", "CharacterBody2D", true, false):
			if n == self:
				continue
			if not (n is CharacterBody2D):
				continue
			var nm: StringName = n.name
			if nm == "Player" or nm == "Knight" or nm == "knight" or String(nm).contains("Player"):
				var d_sq: float = global_position.distance_squared_to(n.global_position)
				if d_sq < DETECT_RADIUS_SQ:
					_target = n
					_set_state(State.CHASE)
					return

func _lock_target_if_player(node: Node) -> void:
	if node == self:
		return
	# 要求对方是 CharacterBody2D 且名字带 Player/Knight 或属于 player 组
	var is_player: bool = false
	if node.is_in_group("player"):
		is_player = true
	var nm: StringName = node.name
	if nm == "Player" or nm == "Knight" or nm == "knight" or String(nm).contains("Player"):
		is_player = true
	if is_player and node is CharacterBody2D:
		_target = node
		# 如果当前 IDLE 立刻切追击；否则保持（ATTACK/HURT 不打断）
		if state == State.IDLE:
			_set_state(State.CHASE)

func _is_target_alive() -> bool: # Verify the alive of the character before taking actions
	if not is_instance_valid(_target):
		return false
	if _target.is_in_group("player") or "Player" in _target.name:
		return true
	if _target.get("_is_dead") == true or _target.name == "Death":
		return false
	return false

## ============================================================================
##  3. 每帧主循环 _physics_process
## ============================================================================
func _physics_process(delta: float) -> void:
	# —— 3.1 重力（小怪也是 CharacterBody2D，需要自己加）
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		if velocity.y > 900.0:
			velocity.y = 900.0

	# —— 3.2 没目标：再兜底扫一次（主角稍后走近小怪也能被扫到）
	if not is_instance_valid(_target):
		_scan_target_fallback()

	# —— 3.3 状态机 dispatch（IDLE/CHASE/ATTACK/HURT/DEAD）
	match state:
		State.IDLE:   _tick_idle(delta)
		State.CHASE:  _tick_chase(delta)
		State.ATTACK: _tick_attack(delta)
		State.HURT:   _tick_hurt(delta)
		State.DEAD:   _tick_dead(delta)
		_:            pass

	# —— 3.4 CharacterBody2D 移动
	move_and_slide()


## ============================================================================
##  4. 状态切换 + 5 个 tick 函数
## ============================================================================
func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.IDLE:   _enter_idle()
		State.CHASE:  _enter_chase()
		State.ATTACK: _enter_attack()
		State.HURT:   _enter_hurt()
		State.DEAD:   _enter_death()


func _enter_idle() -> void:
	_play_if_needed("idle")


func _tick_idle(_delta: float) -> void:
	# IDLE 时 velocity.x 拉回 0
	velocity.x = move_toward(velocity.x, 0.0, move_speed)
	# 有目标时切回 CHASE
	if is_instance_valid(_target) and global_position.distance_to(_target.global_position) <= MAX_CHASE_DIST:
		_set_state(State.CHASE)


func _enter_chase() -> void:
	# CHASE 动画统一在 tick 里根据 moving 决定 run / idle，不在这里硬播
	pass


func _tick_chase(delta: float) -> void:
	if not _is_target_alive():
		_target = null
		_set_state(State.IDLE)
		return

	var target_pos: Vector2 = _target.global_position
	var dx: float = target_pos.x - global_position.x
	var abs_dx: float = abs(dx)
	var dy: float = target_pos.y - global_position.y

	# 放弃追击（走太远）
	var dist: float = global_position.distance_to(target_pos)
	if dist > MAX_CHASE_DIST:
		_set_state(State.IDLE)
		return

	# 朝向（攻击盒也跟着翻转）
	if abs_dx > 1.0:
		_flip_facing(int(sign(dx)))

	# 停住区间：abs(dx) < stop_zone（通常比 attack_range 小一点，避免穿过目标抖动）
	var moving: bool
	if abs_dx < stop_zone:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		moving = false
	else:
		# 朝目标走
		var dir_x: float = sign(dx)
		velocity.x = move_toward(velocity.x, dir_x * move_speed, move_speed * 4.0 * delta)
		moving = true

	# CHASE 中根据 moving 决定播放 run / idle
	if moving:
		_play_if_needed("run")
	else:
		_play_if_needed("idle")

	# 跳跃：
	# (a) 主角明显在上方（dy < -20）且站在地上 → 跳
	# (b) 前方 22 像素有墙（is_on_wall）且站地上 → 跳（跨过台阶/小障碍）
	if is_on_floor():
		if dy < -20.0:
			velocity.y = jump_force
		elif _has_wall_ahead(int(sign(dx))):
			velocity.y = jump_force

	# 进入攻击范围 + 可以攻击 → ATTACK
	if can_attack and abs_dx <= attack_range and abs(dy) < 20:
		_set_state(State.ATTACK)


func _has_wall_ahead(dir_x: int) -> bool:
	# 检测脚下前方是否有墙/台阶（简单用 is_on_wall + 朝向判断，够用）
	if not is_on_wall():
		return false
	# CharacterBody2D.get_wall_normal()：墙法线朝外（指向 -dir_x 方向）→ 法线.x 与 dir_x 反号
	var n: Vector2 = get_wall_normal()
	if dir_x == 0:
		return false
	return sign(n.x) == -sign(dir_x)


func _enter_attack() -> void:
	velocity.x = 0.0
	_hitting_enemies.clear()
	# 播放 attack 动画（里面 method track 会调用 open/close_attack_hitbox）
	if _anim and _anim.has_animation("attack"):
		_anim.play("attack")

	# —— 双保险：即使 method track 因为动画资源没绑好失效，
	#            0.14s 强制开盒，0.36s 强制关盒，0.45s 当作 attack 结束（与 attack 动画 0.42s 对齐）
	var t := get_tree()
	t.create_timer(0.14).timeout.connect(_open_attack_hitbox)
	t.create_timer(0.36).timeout.connect(_close_attack_hitbox)
	t.create_timer(0.45).timeout.connect(_on_attack_end)


func _tick_attack(_delta: float) -> void:
	# ATTACK 状态下不移动，等动画/定时器结束
	velocity.x = move_toward(velocity.x, 0.0, move_speed)


func _on_attack_end() -> void:
	if state != State.ATTACK:
		return
	# —— 攻击结束立刻关攻击盒
	_close_attack_hitbox()
	# —— 进入冷却，冷却结束后 can_attack=true
	can_attack = false
	get_tree().create_timer(attack_cd).timeout.connect(func():
		can_attack = true
		# 冷却结束时若距离满足直接再攻；否则 CHASE 也会在 tick 里切
		if _is_target_alive():
			var dx: float = _target.global_position.x - global_position.x
			var dy: float = _target.global_position.y - global_position.y
			if state == State.CHASE and abs(dx) <= attack_range and abs(dy) < 20.0:
				_set_state(State.ATTACK)
	)
	# —— 攻击结束 → CHASE（让 CHASE tick 决定继续停住还是再追）
	if _is_target_alive():
		_set_state(State.CHASE)
	else:
		_target = null
		_set_state(State.IDLE)

## ============================================================================
##  5. 攻击盒：开关 + 命中回调
## ============================================================================
## 动画 method track 第 6 帧 ≈ 0.12s 调用这个
func open_attack_hitbox() -> void:
	_open_attack_hitbox()

## 动画 method track 第 12 帧 ≈ 0.32s 调用这个
func close_attack_hitbox() -> void:
	_close_attack_hitbox()


func _open_attack_hitbox() -> void:
	if not _attack_hitbox:
		return
	if _attack_hitbox.monitoring:
		return  ## 已经开着，不重复清命中表
	_hitting_enemies.clear()

	if "damage" in _attack_hitbox: # Verify that the attack damage of enemy is 1
		_attack_hitbox.damage = attack
	elif _attack_hitbox.has_method("set_damage"):
		_attack_hitbox.set_damage(attack)

	_attack_hitbox.monitoring = true
	_attack_hitbox.monitorable = true


func _close_attack_hitbox() -> void:
	if not _attack_hitbox:
		return
	_attack_hitbox.monitoring = false
	_attack_hitbox.monitorable = false
	_hitting_enemies.clear()


## 攻击盒命中 Area2D（如果主角有独立 Hurtbox，这里会命中）
func _on_attack_hit_area(area: Area2D) -> void:
	if not _attack_hitbox or not _attack_hitbox.monitoring:
		return
	# (a) 如果是 Hurtbox 且有 take_hit → 调它（通用）
	if area.has_method("take_hit"):
		var key = area.get_instance_id()
		if _hitting_enemies.has(key):
			return
		_hitting_enemies[key] = true
		area.take_hit(attack, _attack_hitbox)
		return
	# (b) 父节点是角色且有 take_damage → 直接调用（兼容 knight 没有独立 Hurtbox 场景）
	var par: Node = area.get_parent() if area.get_parent() else null
	if par and par.has_method("take_damage"):
		var key = par.get_instance_id()
		if _hitting_enemies.has(key):
			return
		_hitting_enemies[key] = true
		par.take_damage(attack)


## 攻击盒直接重叠到 CharacterBody2D（Knight 默认没有独立 Hurtbox 的兼容兜底）
func _on_attack_hit_body(body: Node) -> void:
	if not _attack_hitbox or not _attack_hitbox.monitoring:
		return
	if body == self:
		return
	if body.has_method("take_damage"):
		var key = body.get_instance_id()
		if _hitting_enemies.has(key):
			return
		_hitting_enemies[key] = true
		body.take_damage(attack)


## ============================================================================
##  6. 受击 + 死亡
## ============================================================================
func take_damage(amount: int, source: Area2D = null) -> void:
	if state == State.DEAD or amount <= 0:
		return
	hp = max(0, hp - amount)
	_set_state(State.HURT)
	if hp <= 0:
		_set_state(State.DEAD)

func _enter_hurt() -> void:
	# 攻击状态被打，立刻关攻击盒防鬼畜
	_close_attack_hitbox()
	# —— 被打瞬间把横向速度设为"背对目标方向 × hurt_pushback"（小硬直，不飞）
	var dir_x: int = 1
	if is_instance_valid(_target):
		dir_x = int(sign(global_position.x - _target.global_position.x))
		if dir_x == 0:
			dir_x = 1
	velocity.x = float(dir_x) * hurt_pushback
	# 翻转朝向（朝攻击者）
	_flip_facing(-dir_x)
	# 播 hurt 动画（0.15s），结束后若没死 → CHASE
	if _anim and _anim.has_animation("hurt"):
		_anim.play("hurt")
	get_tree().create_timer(max(hurt_back_duration, 0.15)).timeout.connect(func():
		if state == State.HURT:
			_set_state(State.CHASE)
	)


func _tick_hurt(_delta: float) -> void:
	# 硬直内 velocity 按摩擦衰减（不用加额外逻辑）
	velocity.x = move_toward(velocity.x, 0.0, 400.0)


func _enter_death() -> void:
	_close_attack_hitbox()
	get_tree().call_group("ui", "add_kill")
	# 关碰撞 → 尸体不再被打/挡路
	collision_layer = 0
	if _hurtbox:
		_hurtbox.monitoring = false
		_hurtbox.monitorable = false
	# 播放 death（2 秒 7 帧，行 0 帧 0~6）
	var died_anim_finished: bool = false
	if _anim and _anim.has_animation("death"):
		_anim.play("death")

	# 双保险：动画 finished 或 2.5 秒超时后都 queue_free
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)
	if _anim:
		_anim.animation_finished.connect(func(_anim_name: StringName):
			if state == State.DEAD and is_instance_valid(self):
				queue_free()
		, CONNECT_ONE_SHOT)


func _tick_dead(_delta: float) -> void:
	# 死亡后就让动画播完等待销毁，不再做任何移动/追击
	velocity.x = 0.0


## ============================================================================
##  7. 工具函数：朝向翻转 + 防重影的"动画只在变化时 play"
## ============================================================================
func _flip_facing(dir_x: int) -> void:
	if dir_x == 0 or not _sprite:
		return
	# Sprite2D 翻转 scale.x
	var s: Vector2 = _sprite.scale
	s.x = abs(s.x) * float(dir_x)
	_sprite.scale = s
	# —— 攻击盒 position 也左右翻转（负 x 的 dir 才会取负）
	if _attack_hitbox:
		var ap: Vector2 = _attack_hitbox.position
		ap.x = abs(ap.x) * float(dir_x)
		_attack_hitbox.position = ap


func _play_if_needed(anim_name: String) -> void:
	if not _anim:
		return
	if not _anim.has_animation(anim_name):
		return
	if _anim.current_animation != anim_name:
		_anim.play(anim_name)
