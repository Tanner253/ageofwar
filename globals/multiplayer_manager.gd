extends Node

# ── Signals ───────────────────────────────────────────────────────────────────
signal lobby_list_received(lobbies: Array)
signal joined_lobby(role: String, lobby_name: String, player_num: int)
signal game_started(player_num: int)
signal enemy_spawn_received(unit_type: String, stage: String, from_player_num: int)
signal enemy_special_received(attack_type: String, from_player_num: int)
signal enemy_age_advance_received(new_age: String, from_player_num: int)
signal enemy_turret_received(action: String, slot: int, turret_name: String, from_player_num: int)
signal opponent_disconnected()
signal game_over_received(winner_num: int)
signal connection_error(message: String)

# ── State ─────────────────────────────────────────────────────────────────────
var ws := WebSocketPeer.new()
var connected := false

var is_multiplayer_game := false
var is_spectator := false
var player_num := 0        # 1, 2, or 0 (spectator)
var lobby_id := ""
var lobby_name := ""

var _pending_lobby_id := ""
var _pending_role := ""

# ── Init ──────────────────────────────────────────────────────────────────────
func _ready():
	set_process(false)
	if OS.has_feature("web"):
		var lid = _get_url_param("lobby")
		var role = _get_url_param("role")
		if lid != "" and lid != "null":
			_pending_lobby_id = lid
			_pending_role = role if role != "" else "player"
			connect_to_server()

func _get_url_param(param: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var result = JavaScriptBridge.eval(
		"decodeURIComponent((new URLSearchParams(window.location.search)).get('%s') || '')" % param
	)
	if result == null:
		return ""
	return str(result)

func _get_server_url() -> String:
	if OS.has_feature("web"):
		# Explicit server URL passed from lobby page (split architecture)
		var server_url = _get_url_param("server")
		if server_url != "" and server_url != "null":
			return server_url
		# Fallback: same origin
		var protocol = str(JavaScriptBridge.eval("window.location.protocol"))
		var host     = str(JavaScriptBridge.eval("window.location.host"))
		var ws_proto = "wss://" if protocol == "https:" else "ws://"
		return ws_proto + host
	return "ws://localhost:10000"

# ── Connection ────────────────────────────────────────────────────────────────
func connect_to_server():
	if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		return
	var url = _get_server_url()
	var err = ws.connect_to_url(url)
	if err != OK:
		emit_signal("connection_error", "Failed to connect to server: " + str(err))
		return
	set_process(true)

func _process(_delta):
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not connected:
				connected = true
				_send_player_name()
				if _pending_lobby_id != "":
					join_lobby(_pending_lobby_id, _pending_role)
					_pending_lobby_id = ""
			while ws.get_available_packet_count():
				var text = ws.get_packet().get_string_from_utf8()
				_handle_message(text)
		WebSocketPeer.STATE_CLOSED:
			if connected:
				connected = false
				set_process(false)

func _send_player_name():
	var name_param = _get_url_param("name")
	if name_param != "" and name_param != "null":
		_send({ "type": "set_name", "name": name_param })

# ── Message Handling ──────────────────────────────────────────────────────────
func _handle_message(text: String):
	var msg = JSON.parse_string(text)
	if msg == null:
		return

	match msg.get("type", ""):
		"lobby_list":
			emit_signal("lobby_list_received", msg.get("lobbies", []))

		"joined":
			lobby_id   = msg.get("lobby_id", "")
			lobby_name = msg.get("lobby_name", "")
			player_num = msg.get("player_num", 0)
			is_spectator = (msg.get("role", "") == "spectator")
			emit_signal("joined_lobby", msg.get("role", ""), lobby_name, player_num)

		"game_start":
			var pnum = msg.get("player_num", 0)
			is_multiplayer_game = true
			if pnum == 0:
				is_spectator = true
			player_num = pnum
			if OS.has_feature("web"):
				JavaScriptBridge.eval("if(window.hideWaitingOverlay)window.hideWaitingOverlay()")
			emit_signal("game_started", pnum)

		"spawn":
			emit_signal("enemy_spawn_received",
				msg.get("unit", "melee"),
				msg.get("stage", "cave"),
				msg.get("player_num", 0))

		"special":
			emit_signal("enemy_special_received",
				msg.get("attack", "cave"),
				msg.get("player_num", 0))

		"age_advance":
			emit_signal("enemy_age_advance_received",
				msg.get("age", "cave"),
				msg.get("player_num", 0))

		"turret_action":
			emit_signal("enemy_turret_received",
				msg.get("action", "buy"),
				msg.get("slot", 0),
				msg.get("turret_name", ""),
				msg.get("player_num", 0))

		"opponent_disconnected":
			emit_signal("opponent_disconnected")

		"game_over":
			emit_signal("game_over_received", msg.get("winner", 0))

		"error":
			emit_signal("connection_error", msg.get("message", "Unknown error"))

# ── Send Helpers ──────────────────────────────────────────────────────────────
func _send(msg: Dictionary):
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))

func join_lobby(lid: String, role: String = "player"):
	_send({ "type": "join", "lobby_id": lid, "role": role })

func send_spawn(unit_type: String, stage: String):
	_send({ "type": "spawn", "unit": unit_type, "stage": stage })

func send_special(attack_type: String):
	_send({ "type": "special", "attack": attack_type })

func send_age_advance(new_age: String):
	_send({ "type": "age_advance", "age": new_age })

func send_turret_action(action: String, slot: int, turret_name: String = ""):
	_send({ "type": "turret_action", "action": action, "slot": slot, "turret_name": turret_name })

func send_game_over(winner_player_num: int):
	_send({ "type": "game_over", "winner": winner_player_num })

func send_surrender():
	_send({ "type": "surrender" })

func disconnect_from_server():
	ws.close()
	connected = false
	is_multiplayer_game = false
	is_spectator = false
	player_num = 0
	set_process(false)
