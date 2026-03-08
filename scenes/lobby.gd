extends Control

@onready var status_label   : Label  = $VBox/StatusLabel
@onready var lobby_label    : Label  = $VBox/LobbyLabel
@onready var back_button    : Button = $VBox/BackButton
@onready var title_label    : Label  = $VBox/TitleLabel

var dot_count := 0
var waiting := false

func _ready():
	MultiplayerManager.joined_lobby.connect(_on_joined)
	MultiplayerManager.game_started.connect(_on_game_started)
	MultiplayerManager.opponent_disconnected.connect(_on_opponent_disconnected)
	MultiplayerManager.connection_error.connect(_on_error)

	if MultiplayerManager.connected:
		status_label.text = "Connected — waiting for opponent"
		waiting = true
	else:
		status_label.text = "Connecting to server"
		MultiplayerManager.connect_to_server()

func _process(delta):
	if waiting:
		dot_count = (dot_count + 1) % 120
		var dots = ".".repeat((dot_count / 30) + 1)
		if MultiplayerManager.connected:
			status_label.text = "Waiting for opponent" + dots
		else:
			status_label.text = "Connecting to server" + dots

func _on_joined(role: String, lname: String, _pnum: int):
	lobby_label.text = lname
	if role == "spectator":
		status_label.text = "Entering as spectator..."
		waiting = false
		await get_tree().create_timer(0.5).timeout
		_start_game()
	else:
		waiting = true

func _on_game_started(_player_num: int):
	waiting = false
	status_label.text = "Battle begins!"
	await get_tree().create_timer(0.3).timeout
	_start_game()

func _start_game():
	get_tree().change_scene_to_file("res://main_game.tscn")

func _on_opponent_disconnected():
	waiting = false
	status_label.text = "Opponent disconnected. Return to lobby."

func _on_error(message: String):
	waiting = false
	status_label.text = "Error: " + message

func _on_back_pressed():
	MultiplayerManager.disconnect_from_server()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = '/'")
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
