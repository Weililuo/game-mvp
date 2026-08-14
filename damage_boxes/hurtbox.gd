class_name Hurtbox extends Area2D

## 受击判定盒（Hurtbox）
## - 挂在角色身上，表示该角色哪里会被打
## - 被 Hitbox 命中时，向自己的父节点（Owner 角色）调用 take_damage
## - 可设置 invulnerable 用于无敌帧（例如主角闪避期间）

## 是否处于无敌状态（无敌时不接收伤害）
var invulnerable: bool = false

## 被击中信号（可选订阅，用于闪白、数字跳字等）
signal hurt(amount: int, source: Hitbbox)

## 被 Hitbox 调用：将伤害向上转发给角色节点
func take_hit(amount: int, source: Hitbbox) -> void:
	if invulnerable:
		return
	emit_signal("hurt", amount, source)
	# 向父节点（通常是 CharacterBody2D）转发
	if owner and owner.has_method("take_damage"):
		owner.take_damage(amount)
	elif get_parent() and get_parent().has_method("take_damage"):
		get_parent().take_damage(amount)
