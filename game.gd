extends "res://games/protocols/godot_party_default_protocol/ranked_round.gd"
## Parallel nine-ball tables share only the tournament. Host physics resolves every shot.
const Tournament: Script = preload("res://games/minigame/godot_party_default_billiards/tournament.gd")
const Art: Script = preload("res://games/minigame/godot_party_default_billiards/table_art.gd")
var tournament: RefCounted = Tournament.new()
var viewport: SubViewport
var surface: SubViewportContainer
var camera: Camera3D
var art: Node3D
var balls: Array[Node3D] = []
var table_choice: OptionButton
var power_slider: HSlider
var shoot_button: Button
var selected_table: String = ""
var shown_table: String = ""
var table_keys: Array[String] = []
var aim: Vector2 = Vector2.UP
var overlay: Control
var controls: Label
var placing: bool = false

func build_game() -> void:
	heading.text = "夜幕球房 · 九球分桌赛"
	footer.text = "先碰最小号球 · 合法进 9 赢桌 · 犯规给下家自由球 · 胜者组、败者组继续决出全部名次"
	surface = SubViewportContainer.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.stretch = true
	stage.add_child(surface)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1200, 760)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	surface.add_child(viewport)
	art = Art.new()
	viewport.add_child(art)
	art.build()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	camera.position = Vector3(0, 4, 0.01)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	for number: int in 10:
		var ball: Node3D = art.make_ball(number)
		viewport.add_child(ball)
		balls.append(ball)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_table_input)
	overlay.draw.connect(_draw_aim)
	stage.add_child(overlay)
	table_choice = OptionButton.new()
	table_choice.item_selected.connect(func(index: int) -> void: selected_table = table_keys[index])
	sidebar.add_child(table_choice)
	controls = label(sidebar, "", 20)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label(sidebar, "击球力度")
	power_slider = HSlider.new()
	power_slider.min_value = 0.05
	power_slider.max_value = 1.0
	power_slider.step = 0.01
	power_slider.value = 0.5
	sidebar.add_child(power_slider)
	shoot_button = button(sidebar, "出杆", _shoot)
	button(sidebar, "返回我的球桌", func() -> void:
		for key: String in view.get("tables", {}):
			if local_id in view.tables[key].ids and view.tables[key].winner == "":
				selected_table = key
				break)
	label(sidebar, "移动鼠标瞄准，点击出杆。\n自由球：先点击台面摆白球。", 20)

func godot_party_graphics_targets() -> Dictionary:
	var world: WorldEnvironment
	var sun: DirectionalLight3D
	if art != null:
		for node: Node in art.get_children():
			if node is WorldEnvironment:
				world = node
			elif node is DirectionalLight3D:
				sun = node
	return {"world": world, "sun": sun, "materials_root": art}

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
			var target: Vector3 = Vector3(ball.pos.x, 0.028575, ball.pos.y)
			balls[index].position = balls[index].position.lerp(target, 1.0 - exp(-delta * 25)) if shown_table == selected_table else target
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
	if not running or local_id.is_empty() or not view.get("tables", {}).has(selected_table):
		return false
	var table: Dictionary = view.tables[selected_table]
	return table.winner == "" and not table.moving and table.ids[table.turn] == local_id

func _table_input(event: InputEvent) -> void:
	if not _can_act():
		return
	var table: Dictionary = view.tables[selected_table]
	var pointer: Vector2 = overlay.get_local_mouse_position() * Vector2(viewport.size) / overlay.size
	var hit: Variant = Plane(Vector3.UP, 0.028575).intersects_ray(camera.project_ray_origin(pointer), camera.project_ray_normal(pointer))
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
		send_action({"kind": "shot", "table": selected_table, "epoch": view.tables[selected_table].epoch, "direction": aim, "power": power_slider.value})

func _draw_aim() -> void:
	if not _can_act() or view.tables[selected_table].free:
		return
	var pos: Vector2 = view.tables[selected_table].balls[0].pos
	var start: Vector2 = camera.unproject_position(Vector3(pos.x, 0.035, pos.y)) * overlay.size / Vector2(viewport.size)
	var end: Vector2 = camera.unproject_position(Vector3(pos.x + aim.x * 0.7, 0.035, pos.y + aim.y * 0.7)) * overlay.size / Vector2(viewport.size)
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
			table_choice.add_item("球桌 %d · %s" % [int(key) + 1, view.tables[key].range])
	if selected_table in table_keys:
		table_choice.select(table_keys.find(selected_table))
	status.text = "赛事剩余 %d 秒 · %d 张球桌进行中" % [ceili(view.time), active.size()]
	var lines: PackedStringArray = []
	for player: Dictionary in players:
		lines.append("%s · %s" % [player.name, "第 %d 名" % int(view.ranks[player.player_id]) if view.ranks.has(player.player_id) else "比赛中"])
	standings.text = "\n".join(lines)
	if view.tables.has(selected_table):
		var table: Dictionary = view.tables[selected_table]
		var names: PackedStringArray = []
		for id: String in table.ids:
			names.append(player_name(id))
		controls.text = " / ".join(names) + "\n轮到：" + player_name(table.ids[table.turn]) + "\n目标：%d 号 · 剩余 %d 秒\n%s" % [table.lowest, ceili(table.time), table.message]
	shoot_button.disabled = not _can_act() or view.tables[selected_table].free
	power_slider.editable = not shoot_button.disabled

func player_left(_id: String) -> void:
	finish_rows([], [], "cancelled")
