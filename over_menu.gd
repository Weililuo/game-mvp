extends CanvasLayer


@onready var root: Control = $Root


func _ready() -> void:
	root.hide()
	_apply_click_mask($Root/Mainmenu)
	_apply_click_mask($Root/Restart)


func _apply_click_mask(button: TextureButton) -> void:
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(button.texture_normal.get_image())
	button.texture_click_mask = bitmap


func _on_player_died() -> void:
	root.show()


func _on_mainmenu_pressed() -> void:
	get_tree().change_scene_to_file("res://start_menu.tscn")


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()
