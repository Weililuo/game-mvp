extends CanvasLayer

@onready var time_label: Label = $Timer
@onready var score_label: Label = $Score
@onready var heart_container: HBoxContainer = $HealthBox

var full_heart = preload("res://ui/heart_ui_full.png")
var empty_heart = preload("res://ui/heart_ui_empty.png")

var survival_time: float = 0.0
var kill_count: int = 0
var is_game_over: bool = false

func _ready() -> void:
	add_to_group("ui")
	score_label.text = "0"
	
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.health_changed.connect(update_hearts)
		player.died.connect(func(): is_game_over = true)
		
	for i in range(3): # Set hearts for health
		var rect = TextureRect.new()
		rect.texture = full_heart
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(14, 18)
		heart_container.add_child(rect)

func _process(delta: float) -> void: # Set timer
	if not is_game_over:
		survival_time += delta
		time_label.text = "%.2fs" % survival_time

func add_kill() -> void:
	if is_game_over:
		return
	kill_count += 1
	score_label.text = "%d" % kill_count

func update_hearts(current_hp: int, max_hp: int) -> void:
	var hearts = heart_container.get_children()
	for i in range(hearts.size()):
		if i < current_hp:
			hearts[i].texture = full_heart
		else:
			hearts[i].texture = empty_heart