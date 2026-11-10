extends "res://games/protocols/godot_party_default_protocol/ranked_round.gd"
## Parallel nine-ball tables share only the tournament. Host physics resolves every shot.
const Tournament: Script = preload("res://games/minigame/godot_party_default_billiards/tournament.gd")
const Physics: Script = preload("res://games/minigame/godot_party_default_billiards/pool_physics.gd")
var tournament: RefCounted = Tournament.new()
var _published_tables: Dictionary = {}
var _published_ranks: Dictionary = {}
var _event_revision: int = 0
var _received_event: int = 0
var _motion_sequence: int = 0
var _received_motion: int = 0
var _pending_motion: Dictionary = {}
var _end_msec: int = 0
var _watching_peers: Dictionary = {}
var _subscribed_table: String = ""
const TableArt: Script = preload("res://games/minigame/godot_party_default_billiards/table_art.gd")
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
@onready var reset_tip_button: Button = %ResetTip
@onready var my_table_button: Button = %MyTable

func build_game() -> void:
	balls.assign(art.rack.get_children())
	overlay.gui_input.connect(_table_input)
	overlay.draw.connect(_draw_aim)
	table_choice.item_selected.connect(_select_table)
	tip_control.gui_input.connect(_tip_input)
	tip_control.draw.connect(_draw_tip)
	reset_tip_button.pressed.connect(_reset_tip)
	shoot_button.pressed.connect(_shoot)
	my_table_button.pressed.connect(_return_to_my_table)
	heading.text = api.i18n.text(&"hud.heading")
	footer.text = api.i18n.text(&"hud.footer")
	reset_tip_button.text = api.i18n.text(&"hud.reset_tip")
	my_table_button.text = api.i18n.text(&"hud.my_table")
	shoot_button.text = api.i18n.text(&"hud.shoot")
	%Instructions.text = api.i18n.text(&"hud.instructions")
	tip_control.tooltip_text = api.i18n.text(&"hud.tip_help")
	$OverlayHUD/Standard/Actions/PowerCaption.text = api.i18n.text(&"hud.power")
	_update_tip()

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
		_end_msec = api.net.host_time_msec() + roundi(float(settings.get("duration", 600)) * 1000.0)

## Sample moving balls at 30 Hz; turn, pocket and rest events remain reliable.
func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	tick_game(delta)
	if not running:
		return
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
			finish_rows(rows, [{"key": "rank", "title": api.i18n.text(&"result.rank"), "format": "integer"}])
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

## View-only controls remain available to spectators. A table popup owns its
## selection, but blocks unrelated actions until it closes; menus block both.
func _can_view_input(table_selection: bool = false) -> bool:
	return running and not api.input.input_blocked and (table_selection or not table_choice.get_popup().visible)

func _select_table(index: int) -> void:
	if not _can_view_input(true):
		return
	selected_table = table_keys[index]
	_subscribe_table()

func _return_to_my_table() -> void:
	if not _can_view_input():
		return
	for key: String in view.tables:
		if local_id in view.tables[key].ids and view.tables[key].winner == "":
			selected_table = key
			_subscribe_table()
			return

func _reset_tip() -> void:
	if not _can_view_input():
		return
	tip = Vector2.ZERO
	_update_tip()

## Only the entry sends logical actions; picking, aim and tip stay local view state.
func _can_act() -> bool:
	if not _can_view_input() or local_id.is_empty() or not view.get("tables", {}).has(selected_table):
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
		var offset: Vector2 = (event.position - tip_control.size * 0.5) / 48.0
		tip = Vector2(offset.x, -offset.y).limit_length(Physics.MAX_TIP)
		_update_tip()

func _update_tip() -> void:
	var vertical_key: StringName = &"tip.follow" if tip.y > 0.05 else (&"tip.draw" if tip.y < -0.05 else &"tip.center")
	var vertical: String = api.i18n.text(vertical_key)
	if absf(tip.x) > 0.05:
		var side_key: StringName = &"tip.right" if tip.x > 0.0 else &"tip.left"
		tip_label.text = api.i18n.text(&"hud.tip_with_side", {"vertical": vertical, "side": api.i18n.text(side_key)})
	else:
		tip_label.text = api.i18n.text(&"hud.tip", {"vertical": vertical})
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
	view.time = maxf(0.0, float(_end_msec - api.net.host_time_msec()) / 1000.0)
	for table: Dictionary in view.tables.values():
		if not table.moving:
			table.time = maxf(0.0, float(table.end_msec - api.net.host_time_msec()) / 1000.0)
	var active: Array[String] = []
	for key: String in view.tables:
		if view.tables[key].winner == "":
			active.append(key)
	if not active.is_empty() and (selected_table.is_empty() or not view.tables.has(selected_table) or view.tables[selected_table].winner != ""):
		selected_table = active[0]
		for key: String in active:
			if local_id in view.tables[key].ids:
				selected_table = key
	_subscribe_table()
	if table_keys != active:
		table_keys = active
		table_choice.clear()
		for key: String in table_keys:
			table_choice.add_item(api.i18n.text(&"hud.table", {"table": int(key) + 1, "range": view.tables[key].range}))
	if selected_table in table_keys:
		table_choice.select(table_keys.find(selected_table))
	status.text = api.i18n.text(&"hud.time", {"time": ceili(view.time), "tables": active.size()})
	for player: Dictionary in players:
		var standing: String = api.i18n.text(&"hud.rank", {"rank": int(view.ranks[player.player_id])}) if view.ranks.has(player.player_id) else api.i18n.text(&"hud.playing")
		update_standing(player.player_id, api.i18n.text(&"hud.standing", {"player": player.name, "standing": standing}))
	if view.tables.has(selected_table):
		var table: Dictionary = view.tables[selected_table]
		var names: PackedStringArray = []
		for id: String in table.ids:
			names.append(player_name(id))
		controls.text = api.i18n.text(&"hud.details", {"players": " / ".join(names), "turn": player_name(table.ids[table.turn]), "ball": table.lowest, "time": ceili(table.time), "message": table.message})
	shoot_button.disabled = not _can_act() or view.tables[selected_table].free
	power_slider.editable = not shoot_button.disabled
	table_choice.disabled = not _can_view_input(true)
	reset_tip_button.disabled = not _can_view_input()
	my_table_button.disabled = not _can_view_input()

func player_left(_id: String) -> void:
	finish_rows([], [], "cancelled")

## Physics stays authoritative. Only poses travel continuously; no physics internals cross the wire.
func publish() -> void:
	if not running or not api.is_host():
		return
	var current: Dictionary = make_snapshot()
	var changes: Dictionary = {}
	var motion: Dictionary = {}
	for key: String in current.tables:
		var table: Dictionary = current.tables[key]
		var previous: Dictionary = _published_tables.get(key, {})
		var facts: Dictionary = {}
		for field: String in ["ids", "turn", "epoch", "winner", "free", "message", "range", "moving", "lowest"]:
			if not previous.has(field) or previous[field] != table[field]:
				facts[field] = table[field]
		var new_clock: bool = previous.is_empty() or previous.epoch != table.epoch or previous.moving != table.moving
		table["end_msec"] = api.net.host_time_msec() + roundi(float(table.time) * 1000.0) if new_clock else previous.end_msec
		if new_clock:
			facts["end_msec"] = table.end_msec
			facts["time"] = table.time
		var ball_events: Dictionary = {}
		var poses: Dictionary = {}
		for index: int in table.balls.size():
			var ball: Dictionary = table.balls[index]
			if previous.is_empty() or previous.balls[index].active != ball.active or (not table.moving and (previous.moving or previous.balls[index].pos != ball.pos)):
				ball_events[index] = {"active": ball.active, "pos": ball.pos, "orientation": ball.orientation}
			if ball.active and (ball.vel.length_squared() > 0.000001 or absf(ball.spin) > 0.01):
				poses[index] = {"pos": ball.pos, "orientation": ball.orientation}
		if not ball_events.is_empty():
			facts["balls"] = ball_events
		if not facts.is_empty():
			changes[key] = facts
		if not poses.is_empty():
			motion[key] = poses
	if not changes.is_empty() or current.ranks != _published_ranks or _event_revision == 0:
		_event_revision += 1
		var event: Dictionary = {"revision": _event_revision, "tables": changes}
		if _event_revision == 1:
			event["end_msec"] = _end_msec
		if current.ranks != _published_ranks:
			event["ranks"] = current.ranks
		var error: Error = api.net.broadcast(&"pool/events", event, MultiplayerPeer.TRANSFER_MODE_RELIABLE, false)
		if error != OK:
			party_stop(&"pool_send_failed")
			api.fail("pool_events", error_string(error))
			return
		_published_ranks = current.ranks.duplicate()
	_published_tables = current.tables.duplicate(true)
	if not motion.is_empty():
		_motion_sequence += 1
		for player: Dictionary in api.get_room_players():
			var watched: String = _watching_peers.get(player.peer_id, "")
			if not player.connected or player.peer_id == 1 or not motion.has(watched):
				continue
			var error: Error = api.net.send_to_peer(player.peer_id, &"pool/motion", {"revision": _event_revision, "sample": _motion_sequence, "tables": {watched: motion[watched]}}, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 1)
			if error != OK:
				party_stop(&"pool_send_failed")
				api.fail("pool_motion", error_string(error))
				return
	view = current
	render_game()

func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if topic == &"pool/watch":
		if running and api.is_host() and payload is String and _published_tables.has(payload):
			_watching_peers[sender.peer_id] = payload
			var poses: Dictionary = {}
			var table: Dictionary = _published_tables[payload]
			for index: int in table.balls.size():
				poses[index] = {"pos": table.balls[index].pos, "orientation": table.balls[index].orientation}
			_motion_sequence += 1
			var error: Error = api.net.send_to_peer(sender.peer_id, &"pool/view", {"revision": _event_revision, "sample": _motion_sequence, "tables": {payload: poses}})
			if error != OK:
				party_stop(&"pool_watch_failed")
				api.fail("pool_watch_failed", error_string(error))
		return
	if topic not in [&"pool/events", &"pool/motion", &"pool/view"]:
		super._message(sender, topic, payload)
		return
	if not running or sender.peer_id != 1 or api.is_host() or not payload is Dictionary:
		return
	if not payload.get("revision") is int or not payload.get("tables") is Dictionary:
		return
	if topic in [&"pool/motion", &"pool/view"]:
		if not payload.get("sample") is int or payload.sample <= _received_motion or payload.revision < _received_event:
			return
		_received_motion = payload.sample
		if payload.revision > _received_event:
			_pending_motion = payload
			return
		_apply_motion(payload)
		return
	if payload.revision <= _received_event:
		return
	if payload.revision != _received_event + 1:
		party_stop(&"pool_event_order")
		api.fail("pool_event_order", "台球事件序列不连续")
		return
	if view.is_empty():
		view = {"tables": {}, "ranks": {}, "time": 0.0}
	for key: Variant in payload.tables:
		var changes: Variant = payload.tables[key]
		if not key is String or not changes is Dictionary:
			return
		if not view.tables.has(key):
			if not changes.get("balls") is Dictionary or changes.balls.size() != 10:
				return
			view.tables[key] = {"balls": [{}, {}, {}, {}, {}, {}, {}, {}, {}, {}]}
		for field: String in changes:
			if field == "balls":
				for index: Variant in changes.balls:
					if not index is int or index < 0 or index >= 10 or not _valid_pose(changes.balls[index]) or not changes.balls[index].get("active") is bool:
						return
					view.tables[key].balls[index].merge(changes.balls[index], true)
			else:
				view.tables[key][field] = changes[field]
	if payload.has("end_msec"):
		if not payload.end_msec is int:
			return
		_end_msec = payload.end_msec
	if payload.has("ranks"):
		if not payload.ranks is Dictionary:
			return
		view.ranks = payload.ranks
	_received_event = payload.revision
	if not _pending_motion.is_empty() and _pending_motion.revision <= _received_event:
		if _pending_motion.revision == _received_event:
			_apply_motion(_pending_motion)
		_pending_motion.clear()
	render_game()

func _valid_pose(value: Variant) -> bool:
	return value is Dictionary and value.get("pos") is Vector2 and value.pos.is_finite() and value.get("orientation") is Quaternion and value.orientation.is_finite()

func _apply_motion(payload: Dictionary) -> void:
	for key: Variant in payload.tables:
		if not key is String or not view.tables.has(key) or not payload.tables[key] is Dictionary:
			continue
		for index: Variant in payload.tables[key]:
			if not index is int or index < 0 or index >= 10 or not _valid_pose(payload.tables[key][index]):
				continue
			view.tables[key].balls[index].merge(payload.tables[key][index], true)

## Spectators and players receive motion for the table they are actually viewing.
func _subscribe_table() -> void:
	if api.is_host() or selected_table.is_empty() or selected_table == _subscribed_table:
		return
	var error: Error = api.net.send_to_host(&"pool/watch", selected_table)
	if error != OK:
		party_stop(&"pool_watch_failed")
		api.fail("pool_watch_failed", error_string(error))
		return
	_subscribed_table = selected_table
