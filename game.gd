extends "res://games/protocols/godot_party_default_protocol/ranked_round.gd"
## Parallel nine-ball tables share only the tournament. Host physics resolves every shot.
const Tournament: Script = preload("res://games/minigame/godot_party_default_billiards/tournament.gd")
const Physics: Script = preload("res://games/minigame/godot_party_default_billiards/pool_physics.gd")
var tournament: RefCounted = Tournament.new()
const TableArt = preload("res://games/minigame/godot_party_default_billiards/table_art.gd")
@onready var art: TableArt = %PoolTable
@onready var camera: Camera3D = art.camera
var balls: Array[Node3D] = []
@onready var table_choice: OptionButton = %TableChoice
@onready var power_slider: HSlider = %Power
var tip: Vector2 = Vector2.ZERO
@onready var tip_control: Control = %TipSelector
@onready var tip_label: Label = %TipLabel
@onready var shoot_button: Button = %Shoot
var selected_table: String = ""
var shown_table: String = ""
var table_keys: Array[String] = []
var aim: Vector2 = Vector2.UP
@onready var overlay: Control = %AimSurface
@onready var controls: Label = %TableDetails
var placing: bool = false

func build_game() -> void:
	balls.assign(art.rack.get_children())
	overlay.gui_input.connect(_table_input)
	overlay.draw.connect(_draw_aim)
	table_choice.item_selected.connect(func(index: int) -> void: selected_table = table_keys[index])
	tip_control.gui_input.connect(_tip_input)
	tip_control.draw.connect(_draw_tip)
	%ResetTip.pressed.connect(func() -> void:
		tip = Vector2.ZERO
		_update_tip())
	shoot_button.pressed.connect(_shoot)
	%MyTable.pressed.connect(func() -> void:
		for key: String in view.get("tables", {}):
			if local_id in view.tables[key].ids and view.tables[key].winner == "":
				selected_table = key
				break)

func godot_party_graphics_targets() -> Dictionary:
	return {"world": art.world, "sun": art.sun, "materials_root": art}

func start_game() -> void:
	if api.is_host():
		var ids: Array[String] = []
		for player: Dictionary in players:
			ids.append(player.player_id)
		# Shuffle once from the public round seed; subsequent bracket order is stable.
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = api.get_seed()
		for index: int in range(ids.size() - 1, 0, -1):
			var target: int = rng.randi_range(0, index)
			var saved: String = ids[index]
			ids[index] = ids[target]
			ids[target] = saved
		tournament.start(ids, float(settings.get("shot_seconds", 30)))

## Fast ball motion needs more frequent snapshots than the shared turn-based UI.
func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	tick_game(delta)
	clock += delta
	if clock >= 1.0 / 30.0:
		clock = fmod(clock, 1.0 / 30.0)
		if api.is_host():
			publish()
		render_game()

func tick_game(delta: float) -> void:
	if api.is_host():
		tournament.tick(delta)
		if tournament.ranks.size() == players.size():
			var rows: Array = []
			for player: Dictionary in players:
				rows.append({"player_id": player.player_id, "rank": tournament.ranks[player.player_id], "status": "completed", "metrics": {"rank": tournament.ranks[player.player_id]}})
			finish_rows(rows, [{"key": "rank", "title": "最终名次", "format": "integer"}])
		elif elapsed >= float(settings.get("duration", 600)):
			finish_rows([], [], "cancelled")
	if view.get("tables", {}).has(selected_table):
		var table: Dictionary = view.tables[selected_table]
		for index: int in balls.size():
			var ball: Dictionary = table.balls[index]
			balls[index].visible = ball.active
			var target: Vector3 = Vector3(ball.pos.x, Physics.RADIUS, ball.pos.y)
			balls[index].position = balls[index].position.lerp(target, 1.0 - exp(-delta * 25)) if shown_table == selected_table else target
			balls[index].quaternion = balls[index].quaternion.slerp(ball.orientation, 1.0 - exp(-delta * 25)) if shown_table == selected_table else ball.orientation
		shown_table = selected_table
	overlay.queue_redraw()

func handle_action(id: String, data: Dictionary) -> void:
	if tournament.act(id, data):
		publish()

func make_snapshot() -> Dictionary:
	var snap: Dictionary = tournament.snapshot()
	snap["time"] = maxf(0, float(settings.get("duration", 600)) - elapsed)
	return snap

func _can_act() -> bool:
	if not running or api.input.input_blocked or local_id.is_empty() or not view.get("tables", {}).has(selected_table):
		return false
	var table: Dictionary = view.tables[selected_table]
	return table.winner == "" and not table.moving and table.ids[table.turn] == local_id

func _table_input(event: InputEvent) -> void:
	if not event is InputEventMouse or not _can_act():
		return
	var table: Dictionary = view.tables[selected_table]
	var pointer: Vector2 = overlay.get_global_transform_with_canvas() * event.position
	var hit: Variant = Plane(Vector3.UP, Physics.RADIUS).intersects_ray(art.to_local(camera.project_ray_origin(pointer)), art.global_transform.basis.inverse() * camera.project_ray_normal(pointer))
	if not hit is Vector3:
		return
	var point: Vector2 = Vector2(hit.x, hit.z)
	if table.free:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			send_action({"kind": "place", "table": selected_table, "epoch": table.epoch, "pos": point})
	elif event is InputEventMouseMotion:
		aim = (point - Vector2(table.balls[0].pos)).normalized()

func _shoot() -> void:
	if _can_act() and not view.tables[selected_table].free:
		send_action({"kind": "shot", "table": selected_table, "epoch": view.tables[selected_table].epoch, "direction": aim, "power": power_slider.value, "tip": tip})

func _tip_input(event: InputEvent) -> void:
	if not _can_act():
		return
	var selecting: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var dragging: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if selecting or dragging:
		var offset: Vector2 = (tip_control.get_local_mouse_position() - tip_control.size * 0.5) / 48.0
		tip = Vector2(offset.x, -offset.y).limit_length(Physics.MAX_TIP)
		_update_tip()

func _update_tip() -> void:
	var vertical: String = "高杆" if tip.y > 0.05 else ("低杆" if tip.y < -0.05 else "中杆")
	var side: String = " · 右塞" if tip.x > 0.05 else (" · 左塞" if tip.x < -0.05 else "")
	tip_label.text = "击球点：" + vertical + side
	tip_control.queue_redraw()

func _draw_tip() -> void:
	var center: Vector2 = tip_control.size * 0.5
	tip_control.draw_circle(center, 48.0, Color("#eee9da"))
	tip_control.draw_line(center - Vector2(36, 0), center + Vector2(36, 0), Color("#acb0ad"), 1.0, true)
	tip_control.draw_line(center - Vector2(0, 36), center + Vector2(0, 36), Color("#acb0ad"), 1.0, true)
	tip_control.draw_circle(center + Vector2(tip.x, -tip.y) * 48.0, 5.0, Color("#b54338"))

func _draw_aim() -> void:
	if not _can_act() or view.tables[selected_table].free:
		return
	var pos: Vector2 = view.tables[selected_table].balls[0].pos
	var to_overlay: Transform2D = overlay.get_global_transform_with_canvas().affine_inverse()
	var start: Vector2 = to_overlay * camera.unproject_position(art.to_global(Vector3(pos.x, 0.035, pos.y)))
	var end: Vector2 = to_overlay * camera.unproject_position(art.to_global(Vector3(pos.x + aim.x * 0.7, 0.035, pos.y + aim.y * 0.7)))
	overlay.draw_line(start, end, Color("#eee4ae"), 2, true)

func render_game() -> void:
	if view.is_empty():
		return
	var active: Array[String] = []
	for key: String in view.tables:
		if view.tables[key].winner == "":
			active.append(key)
	if not active.is_empty() and (selected_table.is_empty() or not view.tables.has(selected_table) or view.tables[selected_table].winner != ""):
		selected_table = active[0]
		for key: String in active:
			if local_id in view.tables[key].ids:
				selected_table = key
	if table_keys != active:
		table_keys = active
		table_choice.clear()
		for key: String in table_keys:
			table_choice.add_item(api.i18n.text(&"hud.table", {"table": int(key) + 1, "range": view.tables[key].range}))
	if selected_table in table_keys:
		table_choice.select(table_keys.find(selected_table))
	status.text = api.i18n.text(&"hud.time", {"time": ceili(view.time), "tables": active.size()})
	for player: Dictionary in players:
		update_standing(player.player_id, "%s · %s" % [player.name, "第 %d 名" % int(view.ranks[player.player_id]) if view.ranks.has(player.player_id) else "比赛中"])
	if view.tables.has(selected_table):
		var table: Dictionary = view.tables[selected_table]
		var names: PackedStringArray = []
		for id: String in table.ids:
			names.append(player_name(id))
		controls.text = api.i18n.text(&"hud.details", {"players": " / ".join(names), "turn": player_name(table.ids[table.turn]), "ball": table.lowest, "time": ceili(table.time), "message": table.message})
	shoot_button.disabled = not _can_act() or view.tables[selected_table].free
	power_slider.editable = not shoot_button.disabled

func player_left(_id: String) -> void:
	finish_rows([], [], "cancelled")
