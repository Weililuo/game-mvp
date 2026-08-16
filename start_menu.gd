extends Control

func _on_start_pressed() -> void:
	$SfxClick.play()
	
	# Set sound effect time
	get_tree().create_timer(0.23).timeout.connect(func(): 
		if $SfxClick.playing:
			$SfxClick.stop()
	)
	
	# Wait to change scene
	await get_tree().create_timer(0.10).timeout
	get_tree().change_scene_to_file("res://background.tscn")