extends CanvasLayer

@onready var root: Control = $Root
@onready var sfx_game_over: AudioStreamPlayer = $Gameover
@onready var sfx_click: AudioStreamPlayer = $SfxClick
@onready var btn_mainmenu: TextureButton = $Root/Mainmenu
@onready var btn_restart: TextureButton = $Root/Restart

func _ready() -> void:
	root.hide()
	_apply_click_mask(btn_mainmenu)
	_apply_click_mask(btn_restart)

func _apply_click_mask(button: TextureButton) -> void:
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(button.texture_normal.get_image())
	button.texture_click_mask = bitmap

# Death detected
func _on_player_died() -> void:
	root.show()
	var battle_bgm = get_tree().current_scene.get_node_or_null("BGM") as AudioStreamPlayer # BGM stopped
	if battle_bgm and battle_bgm.playing:
		battle_bgm.stop()

	sfx_game_over.play()
	
	get_tree().create_timer(1.1).timeout.connect(func():
		if sfx_game_over.playing:
			sfx_game_over.stop()
	)

# Return to menu
func _on_mainmenu_pressed() -> void:
	_disable_buttons()
	sfx_game_over.stop()
	sfx_click.play()
	
	await get_tree().create_timer(0.3).timeout
	if sfx_click.playing:
		sfx_click.stop()
	get_tree().change_scene_to_file("res://start_menu.tscn")

# Restart
func _on_restart_pressed() -> void:
	_disable_buttons()
	sfx_game_over.stop()
	sfx_click.play()
	
	await get_tree().create_timer(0.3).timeout
	if sfx_click.playing:
		sfx_click.stop()
	get_tree().reload_current_scene()

# Prevent from clicking to fast
func _disable_buttons() -> void:
	btn_mainmenu.disabled = true
	btn_restart.disabled = true
