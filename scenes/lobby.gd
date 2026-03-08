extends Control

@onready var status_label   : Label  = $Panel/VBox/StatusLabel
@onready var lobby_label    : Label  = $Panel/VBox/LobbyLabel
@onready var back_button    : Button = $Panel/VBox/BackButton

func _ready():
	MultiplayerManager.joined_lobby.connect(_on_joined)
	MultiplayerManager.game_started.connect(_on_game_started)
	MultiplayerManager.opponent_disconnected.connect(_on_opponent_disconnected)
	MultiplayerManager.connection_error.connect(_on_error)

	if MultiplayerManager.connected:
		status_label.text = "Connected — waiting for opponent…"
	else:
		status_label.text = "Connecting to server…"
		MultiplayerManager.connect_to_server()

func _on_joined(role: String, lname: String, _pnum: int):
	lobby_label.text = lname
	if role == "spectator":
		status_label.text = "Spectating — loading game…"
		await get_tree().create_timer(0.5).timeout
		_start_game()
	else:
		status_label.text = "Waiting for opponent…"

func _on_game_started(_player_num: int):
	status_label.text = "Game starting…"
	await get_tree().create_timer(0.3).timeout
	_start_game()

func _start_game():
	get_tree().change_scene_to_file("res://main_game.tscn")

func _on_opponent_disconnected():
	status_label.text = "Opponent disconnected. Return to lobby."

func _on_error(message: String):
	status_label.text = "Error: " + message

func _on_back_pressed():
	MultiplayerManager.disconnect_from_server()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = '/'")
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
