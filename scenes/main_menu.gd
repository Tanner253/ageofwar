extends Control

func _ready():
	# Web multiplayer: skip main menu and go straight to lobby/waiting screen
	if OS.has_feature("web"):
		var lobby_param = str(JavaScriptBridge.eval(
			"(new URLSearchParams(window.location.search)).get('lobby') || ''"
		))
		if lobby_param != "" and lobby_param != "null":
			get_tree().change_scene_to_file("res://scenes/lobby.tscn")
			return

func _on_multiplayer_pressed():
	# In the browser this redirects to the lobby page.
	# In editor, navigate to the Godot lobby screen.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = '/'")
	else:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_play_pressed():
	GlobalVariables.current_stage = GlobalVariables.stage.cave
	GlobalVariables.player_exp = 0
	GlobalVariables.player_money = 175
	get_tree().change_scene_to_file("res://scenes/difficulty_selection.tscn")

func _on_instructions_pressed():
	get_tree().change_scene_to_file("res://scenes/instructions_screen.tscn")

func _on_options_pressed():
	get_tree().change_scene_to_file("res://scenes/options_menu.tscn")

func _on_extra_pressed():
	get_tree().change_scene_to_file("res://scenes/extra_screen.tscn")

func _on_credits_pressed():
	get_tree().change_scene_to_file("res://scenes/credits_menu.tscn")

func _on_exit_pressed():
	get_tree().quit()
