extends Node2D

@onready var player_unit_spawn_position : Vector2 = $player_spawn_location.global_position
var unit_array : Array
var player_spawn_location_occupied : bool = false
var unable_to_spawn
var medival_special_active : bool

# Multiplayer: spawn positions for each side
var my_spawn_position    : Vector2  # where THIS client's units come from
var enemy_spawn_position : Vector2  # where the opponent's units come from

# Called when the node enters the scene tree for the first time.
func _ready():
	$Camera2D.global_position = Vector2(576, 280)
	$Camera2D/in_game_menu.connect("spawn_melee",         _on_melee_button_pressed)
	$Camera2D/in_game_menu.connect("spawn_range",         _on_range_button_pressed)
	$Camera2D/in_game_menu.connect("spawn_tank",          _on_tank_button_pressed)
	$Camera2D/in_game_menu.connect("spawn_super_soldier", _on_super_soldier_button_pressed)
	unable_to_spawn   = false
	medival_special_active = false

	# Default spawn positions
	my_spawn_position    = $player_spawn_location.global_position
	enemy_spawn_position = $ai_spawner.global_position

	if MultiplayerManager.is_multiplayer_game:
		_setup_multiplayer()
	else:
		# Single-player: connect AI age-change signal
		$ai_spawner.connect("change_age", _on_ai_change_age)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	$Camera2D/in_game_menu/money.text = str(GlobalVariables.player_money)
	$Camera2D/in_game_menu/exp.text   = str(GlobalVariables.player_exp)
	if medival_special_active == true:
		if $medival_special_timer.is_stopped() == true:
			$medival_special_timer.start(5.0)
		for unit in get_node("player_units").get_children():
			unit.max_health += 1
			unit.take_damage(-1)
			if unit.get_node("heal_sprite") == null:
				var sprite = Sprite2D.new()
				sprite.texture = load("res://age of war sprites/effects/heal/medival_special_heal.png")
				sprite.offset  = Vector2(0, -74)
				sprite.scale   = Vector2(0.8, 0.8)
				sprite.name    = "heal_sprite"
				unit.add_child(sprite)


# ── Multiplayer Setup ──────────────────────────────────────────────────────────

func _setup_multiplayer():
	GlobalVariables.is_multiplayer = true

	# Disable AI — the opponent player takes its place
	$ai_spawner.process_mode = Node.PROCESS_MODE_DISABLED

	# Player 2 controls the RIGHT side
	if MultiplayerManager.player_num == 2:
		GlobalVariables.is_player_two = true
		my_spawn_position    = $ai_spawner.global_position      # P2 spawns from the right
		enemy_spawn_position = $player_spawn_location.global_position  # P1 comes from the left

	# Spectator: hide all controls
	if MultiplayerManager.is_spectator:
		$Camera2D/in_game_menu.hide()

	# Connect network signals
	MultiplayerManager.enemy_spawn_received.connect(_on_enemy_spawn_received)
	MultiplayerManager.enemy_special_received.connect(_on_enemy_special_received)
	MultiplayerManager.enemy_age_advance_received.connect(_on_enemy_age_advance)
	MultiplayerManager.enemy_turret_received.connect(_on_enemy_turret_received)
	MultiplayerManager.opponent_disconnected.connect(_on_opponent_disconnected)
	MultiplayerManager.game_over_received.connect(_on_game_over_received)


# ── Spawn helpers ──────────────────────────────────────────────────────────────

func _spawn_my_unit(scene_path: String, unit_type: String, stage: String):
	"""Spawn a unit on THIS client's side and relay to opponent."""
	if unable_to_spawn and not GlobalVariables.is_player_two:
		return

	var unit = load(scene_path).instantiate()
	unit.position          = my_spawn_position
	unit.position.x       -= 32
	unit.is_player_owned   = not GlobalVariables.is_player_two  # P1→true, P2→false

	var container = "player_units" if not GlobalVariables.is_player_two else "enemy_units"
	get_node("/root/main_game/" + container).add_child(unit)

	if GlobalVariables.is_player_two:
		$ai_spawner/EnemySpawnAura.flash()
	else:
		%PlayerSpawnAura.flash()

	if MultiplayerManager.is_multiplayer_game:
		MultiplayerManager.send_spawn(unit_type, stage)


func _spawn_opponent_unit(unit_type: String, stage: String, from_player_num: int):
	"""Spawn a unit for the opponent (or, in spectator mode, for the given player)."""
	var scene_path: String
	if unit_type == "super_soldier":
		scene_path = "res://units/future/super_soldier/future_super_soldier.tscn"
	else:
		scene_path = "res://units/%s/%s/%s_%s.tscn" % [stage, unit_type, stage, unit_type]

	var unit = load(scene_path).instantiate()

	if MultiplayerManager.is_spectator:
		# Spectator: use player_num from the server message to determine side
		unit.is_player_owned = (from_player_num == 1)
		unit.position = player_unit_spawn_position if from_player_num == 1 else enemy_spawn_position
	else:
		# Opponent is always the other side
		unit.is_player_owned = GlobalVariables.is_player_two  # P1 receives P2's units (false→true)
		unit.position = enemy_spawn_position

	unit.position.x -= 32

	var container = "player_units" if unit.is_player_owned else "enemy_units"
	get_node("/root/main_game/" + container).add_child(unit)

	if unit.is_player_owned:
		%PlayerSpawnAura.flash()
	else:
		$ai_spawner/EnemySpawnAura.flash()


# ── Button Handlers ────────────────────────────────────────────────────────────

func _on_melee_button_pressed(stage: String):
	var path = "res://units/%s/melee/%s_melee.tscn" % [stage, stage]
	_spawn_my_unit(path, "melee", stage)

func _on_range_button_pressed(stage: String):
	var path = "res://units/%s/range/%s_range.tscn" % [stage, stage]
	_spawn_my_unit(path, "range", stage)

func _on_tank_button_pressed(stage: String):
	var path = "res://units/%s/tank/%s_tank.tscn" % [stage, stage]
	_spawn_my_unit(path, "tank", stage)

func _on_super_soldier_button_pressed(_stage: String):
	var path = "res://units/future/super_soldier/future_super_soldier.tscn"
	_spawn_my_unit(path, "super_soldier", "future")


# ── Network Event Handlers ─────────────────────────────────────────────────────

func _on_enemy_spawn_received(unit_type: String, stage: String, from_player_num: int):
	_spawn_opponent_unit(unit_type, stage, from_player_num)

func _on_enemy_special_received(attack_type: String, _from: int):
	match attack_type:
		"cave":     cave_special_attack()
		"medival":  spawn_random_projectiles_from_sky()
		"knight":   knight_special_attack()
		"miltary":  miltary_special_attack()
		"future":   future_special_attack()

func _on_enemy_age_advance(_new_age: String, _from: int):
	$enemy_base.update_sprite_ai()

func _on_enemy_turret_received(action: String, slot: int, turret_name: String, _from: int):
	match action:
		"buy":
			$enemy_base.remote_buy_turret(slot, turret_name)
		"sell":
			$enemy_base.remote_sell_turret(slot)
		"add_slot":
			$enemy_base.remote_add_turret_spot()

func _on_opponent_disconnected():
	# Show a message — the base will eventually be destroyed or they can return
	$Camera2D/in_game_menu.show()
	print("Opponent disconnected!")

func _on_game_over_received(winner_num: int):
	MusicManager.audioStreamPlayer.stop()
	if winner_num == MultiplayerManager.player_num:
		get_tree().change_scene_to_file("res://scenes/win_screen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/game_over.tscn")


# ── Single-player spawn location blocker ──────────────────────────────────────

func _on_player_spawn_location_body_entered(body):
	if body.is_player_owned == true:
		unable_to_spawn = true

func _on_player_spawn_location_body_exited(body):
	if body.is_player_owned == true:
		unable_to_spawn = false


# ── Special Attacks ────────────────────────────────────────────────────────────

func spawn_random_projectiles_from_sky():
	var i = 0
	while i < 25:
		var projectile = load("res://projectile.tscn").instantiate()
		projectile.global_position = Vector2(randf_range(300, 1500), randf_range(-200, -1000))
		projectile.direction = Vector2(randf_range(-0.5, 0.5), randf_range(2, 4)).normalized()
		projectile.damage = 60
		projectile.speed = 300
		projectile.is_player_owned = true
		projectile.spawn_offspring = false
		projectile.time_to_die = 8.0
		projectile.get_node("Sprite2D").texture = load("res://age of war sprites/bases/medival/turret_3/medival_turret_3_projectile_offspring.png")
		get_node("/root/main_game").add_child(projectile)
		i += 1

func cave_special_attack():
	var i = 0
	while i < 25:
		var projectile = load("res://cave_special_projectile.tscn").instantiate()
		projectile.global_position = Vector2(randf_range(300, 1500), randf_range(-200, -1000))
		projectile.direction = Vector2(randf_range(-0.5, 0.5), randf_range(2, 4)).normalized()
		projectile.damage = 80
		projectile.speed = randi_range(250, 350)
		projectile.is_player_owned = true
		projectile.spawn_offspring = false
		projectile.time_to_die = 8.0
		projectile.get_node("Sprite2D").rotation = projectile.direction.angle()
		projectile.get_node("CPUParticles2D").direction = projectile.direction.normalized().rotated(PI/2)
		get_node("/root/main_game").add_child(projectile)
		i += 1

func knight_special_attack():
	var i = 0
	while i < 35:
		var projectile = load("res://arrow_special_projectile.tscn").instantiate()
		projectile.global_position = Vector2(randf_range(300, 1500), randf_range(-200, -2000))
		projectile.direction = Vector2(randf_range(-0.5, 0.5), randf_range(2, 4)).normalized()
		projectile.damage = 150
		projectile.speed = 400
		projectile.is_player_owned = true
		projectile.spawn_offspring = false
		projectile.time_to_die = 12.0
		projectile.get_node("Sprite2D").rotation = projectile.direction.angle()
		get_node("/root/main_game").add_child(projectile)
		i += 1

func medival_special_attack():
	medival_special_active = true

func miltary_special_attack():
	var plane = load("res://miltary_special_plane.tscn").instantiate()
	plane.global_position = Vector2(-100, 150)
	get_node("/root/main_game").add_child(plane)

func future_special_attack():
	var laser = load("res://future_special_laser_attack.tscn").instantiate()
	get_node("/root/main_game").add_child(laser)


# ── Timers / Signals ───────────────────────────────────────────────────────────

func _on_medival_special_timer_timeout():
	medival_special_active = false
	$medival_special_timer.stop()
	for unit in get_node("player_units").get_children():
		if unit.get_node("heal_sprite") != null:
			unit.get_node("heal_sprite").queue_free()

func _on_ai_change_age():
	$enemy_base.update_sprite_ai()

func _on_button_pressed() -> void:
	MusicManager.audioStreamPlayer.stop()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# Unused stubs (kept for compatibility)
func get_first_player_unit(): pass
func get_first_enemy_unit():  pass
func get_last_player_unit():  pass
func get_last_enemy_unit():   pass
