extends Node2D

var enemy_scene = preload("res://enemies/Enemy.tscn")
var spawn_timer: float = 0.0
var current_spawn_interval: float = 3.5

func _process(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player or player.get("_is_dead"):
		return

	spawn_timer += delta
	if spawn_timer >= current_spawn_interval:
		spawn_timer = 0.0
		spawn_enemy_near_player(player)
		current_spawn_interval = max(0.2, current_spawn_interval - 0.05)

func spawn_enemy_near_player(player: Node2D) -> void:
	var enemy = enemy_scene.instantiate()

	var side = -1 if randf() < 0.5 else 1
	
	var spawn_offset_x = side * randf_range(180.0, 240.0)
	var target_x = player.global_position.x + spawn_offset_x

	target_x = clamp(target_x, -140.0, 480.0)

	enemy.global_position = Vector2(target_x, 173.0)
	
	get_parent().add_child(enemy)