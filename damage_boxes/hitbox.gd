class_name Hitbbox extends Area2D

## 攻击判定盒（Hitbox）
## - 挂在角色（主角/小怪）身上，作为武器或攻击动作的判定区域
## - 当它重叠到目标的 Hurtbox 时，向对方传递伤害
## - damage：该次攻击的伤害数值（由动画脚本在播放攻击动画关键帧时设置）

@export var damage: int = 1

## 击中目标时发出的信号（可选订阅，用于屏幕震动/音效等反馈）
signal hit_detected(target: Node, dealt_damage: int)

func _ready() -> void:
	# 当此 Hitbox 重叠到另一个 Area2D 时（应该是对方的 Hurtbox）
	area_entered.connect(_on_area_entered)
	# 也处理直接重叠到 CharacterBody2D 的情况（兼容主角无独立 Hurtbox 的情况）
	body_entered.connect(_on_body_entered)


## 重叠到 Hurtbox（Area2D）
func _on_area_entered(area: Area2D) -> void:
	# 只处理标记为 Hurtbox 类的节点
	if area is Hurtbox:
		# 调用 Hurtbox 暴露的 take_hit 方法，由它向父级转发
		if area.has_method("take_hit"):
			area.take_hit(damage, self)
			emit_signal("hit_detected", area, damage)


## 重叠到角色身体（CharacterBody2D）—— 兼容主角没有独立 Hurtbox 的情况
func _on_body_entered(body: Node) -> void:
	if body == owner or body == get_parent():
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
		emit_signal("hit_detected", body, damage)
