extends RefCounted
## Recursive placement groups. Every table produces one winner; winners/losers
## continue in disjoint rank intervals until every player has an exact placement.
const Physics: Script = preload("res://games/minigame/godot_party_default_billiards/pool_physics.gd")
var tables: Dictionary = {}
var groups: Array[Dictionary] = []
var ranks: Dictionary = {}
var next_table: int = 0
var shot_seconds: float = 30.0

func start(ids: Array[String], seconds: float) -> void:
	tables.clear()
	groups.clear()
	ranks.clear()
	next_table = 0
	shot_seconds = seconds
	_group(ids, 1)

static func partition(ids: Array) -> Array:
	var result: Array = []
	var offset: int = 0
	while offset < ids.size():
		var count: int = 3 if ids.size() - offset == 3 else mini(2, ids.size() - offset)
		result.append(ids.slice(offset, offset + count))
		offset += count
	return result

func _group(ids: Array, first_rank: int) -> void:
	if ids.size() == 1:
		ranks[ids[0]] = first_rank
		return
	var group: Dictionary = {"ids": ids.duplicate(), "rank": first_rank, "tables": [], "done": false}
	for seats: Array in partition(ids):
		var table_id: String = str(next_table)
		next_table += 1
		var physics: RefCounted = Physics.new()
		_rack_nine(physics)
		tables[table_id] = {"ids": seats, "physics": physics, "turn": 0, "epoch": 0, "winner": "", "free": false, "break": true, "lowest": 1, "time": shot_seconds, "message": "先碰 1 号球开球", "range": "%d–%d 名" % [first_rank, first_rank + ids.size() - 1]}
		group.tables.append(table_id)
	groups.append(group)

func _rack_nine(physics: RefCounted) -> void:
	physics.balls.resize(10)
	var rows: Array[int] = [1, 2, 3, 2, 1]
	var order: Array[int] = [1, 2, 3, 4, 9, 5, 6, 7, 8]
	var spacing: float = Physics.RADIUS * 2 + 0.0003
	var index: int = 0
	for row: int in rows.size():
		for col: int in rows[row]:
			physics.balls[order[index]].pos = Vector2((col - (rows[row] - 1) * 0.5) * spacing, -0.60 - row * spacing * sqrt(3.0) * 0.5)
			index += 1

func active_table(id: String) -> String:
	for key: String in tables:
		if id in tables[key].ids and tables[key].winner == "":
			return key
	return ""

func act(id: String, data: Dictionary) -> bool:
	if not data.get("table") is String or not tables.has(data.table) or not data.get("epoch") is int:
		return false
	var table: Dictionary = tables[data.table]
	var physics: RefCounted = table.physics
	if table.winner != "" or data.epoch != table.epoch or table.ids[table.turn] != id or physics.is_moving():
		return false
	if data.get("kind") == "place":
		if not table.free or not data.get("pos") is Vector2 or not data.pos.is_finite():
			return false
		if physics.place_cue(data.pos):
			table.free = false
			return true
	elif data.get("kind") == "shot":
		if table.free or not data.get("direction") is Vector2 or not data.direction.is_finite() or not (data.get("power") is float or data.get("power") is int) or not is_finite(float(data.power)) or data.power < 0.05 or data.power > 1:
			return false
		table.lowest = lowest(physics.balls)
		return physics.shoot(data.direction, float(data.power) * Physics.MAX_SPEED)
	return false

static func lowest(balls: Array) -> int:
	for index: int in range(1, balls.size()):
		if balls[index].active:
			return index
	return 9

## Every foul is judged from a completed shot; a nine on a foul is respotted.
func settle(table: Dictionary, report: Dictionary) -> void:
	var pocketed: Array = report.get("pocketed", [])
	var object_pocketed: bool = false
	for value: int in pocketed:
		if value > 0:
			object_pocketed = true
	var foul: bool = report.get("scratch", false) or int(report.get("first_hit", -1)) != int(table.lowest) or (not object_pocketed and not report.get("rail_after_contact", false))
	var object_rails: int = 0
	for ball_id: int in report.get("rail_ids", []):
		if ball_id > 0:
			object_rails += 1
	if table["break"] and not object_pocketed and object_rails < 4:
		foul = true
	table["break"] = false
	if 9 in pocketed and not foul:
		table.winner = table.ids[table.turn]
		table.message = "合法打进 9 号球，赢得本桌"
		return
	if 9 in pocketed:
		_respot_nine(table.physics)
	if foul:
		table.turn = (int(table.turn) + 1) % table.ids.size()
		table.free = true
		table.message = "犯规：下家全台自由球"
	elif not object_pocketed:
		table.turn = (int(table.turn) + 1) % table.ids.size()
		table.message = "未进球，轮到下家"
	else:
		table.message = "合法进球，继续击球"
	table.epoch += 1
	table.time = shot_seconds

func _respot_nine(physics: RefCounted) -> void:
	if not physics.respot_ball(9):
		push_error("九号球无法安全重摆")

func tick(delta: float) -> void:
	for key: String in tables:
		var table: Dictionary = tables[key]
		if table.winner != "":
			continue
		var physics: RefCounted = table.physics
		if physics.is_moving():
			if physics.step(delta):
				settle(table, physics.shot_report)
		else:
			table.time = maxf(0, table.time - delta)
			if table.time <= 0:
				settle(table, {"first_hit": -1, "scratch": true})
	advance_groups()

func advance_groups() -> void:
	# Collect before creating children: never mutate the group list being traversed.
	var completed: Array[Dictionary] = []
	for group: Dictionary in groups:
		if group.done:
			continue
		var ready: bool = true
		for key: String in group.tables:
			if tables[key].winner == "":
				ready = false
		if ready:
			completed.append(group)
	for group: Dictionary in completed:
		group.done = true
		var winners: Array = []
		var losers: Array = []
		for key: String in group.tables:
			winners.append(tables[key].winner)
			for id: String in tables[key].ids:
				if id != tables[key].winner:
					losers.append(id)
		_group(winners, group.rank)
		_group(losers, int(group.rank) + winners.size())

func snapshot() -> Dictionary:
	var result: Dictionary = {}
	for key: String in tables:
		var table: Dictionary = tables[key]
		result[key] = {"ids": table.ids.duplicate(), "turn": table.turn, "epoch": table.epoch, "winner": table.winner, "free": table.free, "time": table.time, "message": table.message, "range": table.range, "balls": table.physics.balls.duplicate(true), "moving": table.physics.is_moving(), "lowest": lowest(table.physics.balls)}
	return {"tables": result, "ranks": ranks.duplicate()}
