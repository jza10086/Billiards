class_name PoolRules
extends RefCounted
## Simplified local eight-ball. Not an exhaustive tournament rules engine.
var current_player := 0
var groups: Array = ["open","open"]
var ball_in_hand := false
var winner := -1
var is_break := true
var message := "玩家 1 开球 · 至少进 1 球或让 4 颗目标球碰库"
var foul_reason := ""
var shot_pending := false
var _remaining_at_start := 7
var _group_at_start := "open"
var _player_at_start := 0
var shots := 0

func reset() -> void:
	current_player = 0
	groups = ["open","open"]
	ball_in_hand = false
	winner = -1
	is_break = true
	message = "玩家 1 开球 · 至少进 1 球或让 4 颗目标球碰库"
	foul_reason = ""
	shot_pending = false
	shots = 0

func group_for_ball(id: int) -> String:
	if id >= 1 and id <= 7:
		return "solid"
	if id >= 9 and id <= 15:
		return "stripe"
	return "eight" if id == 8 else "cue"

func remaining(player: int, balls: Array) -> int:
	if player < 0 or player > 1:
		return 0
	var count := 0
	for ball in balls:
		if ball.active and (groups[player] == "open" and ball.id != 0 and ball.id != 8 or group_for_ball(ball.id) == groups[player]):
			count += 1
	return count

func can_shoot() -> bool:
	return winner < 0 and not shot_pending and not ball_in_hand

func confirm_placement() -> bool:
	if winner >= 0 or shot_pending or not ball_in_hand:
		return false
	ball_in_hand = false
	message = "玩家 %d · 白球已放置，请瞄准" % (current_player+1)
	return true

func begin_shot(balls: Array) -> bool:
	if not can_shoot():
		return false
	shot_pending = true
	_remaining_at_start = remaining(current_player,balls)
	_group_at_start = groups[current_player]
	_player_at_start = current_player
	foul_reason = ""
	return true

func finish_shot(report: Dictionary, balls: Array) -> Dictionary:
	if not shot_pending or winner >= 0:
		return {"accepted":false,"respot":[]}
	shot_pending = false
	shots += 1
	var respot: Array[int] = []
	var first: int = report.get("first_hit",-1)
	var pocketed: Array = report.get("pocketed",[])
	var scratch: bool = report.get("scratch",false) or pocketed.has(0)
	var was_break := is_break
	is_break = false
	var target := _group_at_start
	if _group_at_start != "open" and _remaining_at_start == 0:
		target = "eight"
	if scratch:
		foul_reason = "白球落袋"
	elif first <= 0:
		foul_reason = "未碰到目标球"
	elif not was_break and target == "open" and first == 8:
		foul_reason = "开放球局不能先碰 8 号球"
	elif not was_break and target != "open" and group_for_ball(first) != target:
		foul_reason = "先碰到非本组目标球"
	var object_pocketed := false
	for id in pocketed:
		if id > 0:
			object_pocketed = true
	if foul_reason.is_empty() and not object_pocketed and not report.get("rail_after_contact",false):
		foul_reason = "碰球后没有进袋或碰库"
	if was_break:
		var object_rails := 0
		for id in report.get("rail_ids",[]):
			if id > 0:
				object_rails += 1
		if foul_reason.is_empty() and not object_pocketed and object_rails < 4:
			foul_reason = "开球不足：需进球或 4 颗目标球碰库"
		if pocketed.has(8):
			respot.append(8)
	elif pocketed.has(8):
		if foul_reason.is_empty() and target == "eight":
			winner = _player_at_start
			message = "玩家 %d 获胜 · 合法打进 8 号球" % (winner+1)
		else:
			winner = 1-_player_at_start
			message = "玩家 %d 获胜 · 对方提前打进 8 号或伴随犯规" % (winner+1)
		return {"accepted":true,"respot":respot,"foul":not foul_reason.is_empty(),"winner":winner}
	if not foul_reason.is_empty():
		current_player = 1-_player_at_start
		ball_in_hand = true
		message = "%s · 玩家 %d 获得自由球" % [foul_reason,current_player+1]
		return {"accepted":true,"respot":respot,"foul":true,"winner":-1}
	if not was_break and groups[_player_at_start] == "open":
		for id in pocketed:
			var group := group_for_ball(id)
			if group == "solid" or group == "stripe":
				groups[_player_at_start] = group
				groups[1-_player_at_start] = "stripe" if group == "solid" else "solid"
				break
	var keep_turn := false
	for id in pocketed:
		if id > 0 and id != 8 and (was_break or group_for_ball(id) == groups[_player_at_start]):
			keep_turn = true
	if not keep_turn:
		current_player = 1-_player_at_start
	message = "玩家 %d %s" % [current_player+1,"继续击球" if keep_turn else "上场"]
	if was_break:
		message += " · 开放球局，开球不分组"
	return {"accepted":true,"respot":respot,"foul":false,"winner":-1,"keep_turn":keep_turn}
