extends SceneTree
const Physics = preload("res://scripts/pool_physics.gd")
const Rules = preload("res://scripts/pool_rules.gd")
var checks := 0
var failed := false
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		push_error(label)
		failed = true
func _init() -> void:
	var p = Physics.new()
	check(p.balls.size()==16,"rack count")
	for a in p.balls:
		for b in p.balls:
			if a.id != b.id:
				check(a.pos.distance_to(b.pos)>=Physics.RADIUS*2.0,"rack overlap")
	check(p.shoot(Vector2(0,-1),5.0),"break starts")
	check(not p.shoot(Vector2.RIGHT,2.0),"cannot double shoot")
	var settled := false
	for n in range(3000):
		if p.step(1.0/120.0):
			settled = true
			break
	check(settled,"break settles")
	check(p.shot_report.first_hit==1,"first contact apex")
	for ball in p.balls:
		check(ball.pos.is_finite() and ball.vel.is_finite(),"finite")
		if ball.active:
			check(absf(ball.pos.x)<=Physics.HALF_WIDTH and absf(ball.pos.y)<=Physics.HALF_LENGTH,"contained")
	# Straight side-pocket scratch.
	p.reset_rack()
	for ball in p.balls:
		ball.active = ball.id==0
	p.balls[0].pos = Vector2.ZERO
	check(p.shoot(Vector2.RIGHT,1.0),"pocket shot")
	for n in range(1000):
		if p.step(1.0/120.0): break
	check(p.shot_report.scratch and not p.balls[0].active,"cue pocket")
	check(p.place_cue(Vector2.ZERO),"place scratched cue")
	check(not p.place_cue(Vector2(3,2)),"reject out of bounds")
	check(not p.place_cue(Vector2.INF),"reject nonfinite")
	# Rules: legal break, open table assignment, foul turn, early8 loss.
	p.reset_rack()
	var r = Rules.new()
	r.reset()
	check(r.begin_shot(p.balls),"begin rules")
	var out: Dictionary = r.finish_shot({"first_hit":1,"pocketed":[],"rail_after_contact":true,"rail_ids":[1,2,3,4]},p.balls)
	check(out.accepted and r.current_player==1 and r.groups[0]=="open","legal break no group")
	check(r.begin_shot(p.balls),"assignment begin")
	p.balls[10].active = false
	r.finish_shot({"first_hit":10,"pocketed":[10],"rail_after_contact":false},p.balls)
	check(r.groups[1]=="stripe" and r.groups[0]=="solid" and r.current_player==1,"stripe assignment")
	check(r.begin_shot(p.balls),"foul begin")
	r.finish_shot({"first_hit":1,"pocketed":[],"rail_after_contact":true},p.balls)
	check(r.ball_in_hand and r.current_player==0,"wrong first hit")
	check(not r.begin_shot(p.balls),"must place cue first")
	check(r.confirm_placement(),"confirm placement")
	check(r.begin_shot(p.balls),"early8 begin")
	p.balls[8].active = false
	r.finish_shot({"first_hit":1,"pocketed":[8],"rail_after_contact":true},p.balls)
	check(r.winner==1,"early8 loses")
	check(not r.begin_shot(p.balls),"terminal no shot")
	# Break8 safely respotted, no win.
	p.reset_rack(); r.reset(); r.begin_shot(p.balls)
	p.balls[8].active = false
	out = r.finish_shot({"first_hit":1,"pocketed":[8],"rail_after_contact":true},p.balls)
	check(out.respot==[8] and r.winner==-1,"break8 respot")
	check(p.respot_ball(8) and p.balls[8].active,"actual respot")
	# Last group +8 together is not legal under declared simplified rules.
	p.reset_rack(); r.reset(); r.is_break=false; r.groups=["solid","stripe"]
	for id in range(2,8): p.balls[id].active=false
	r.begin_shot(p.balls)
	p.balls[1].active=false; p.balls[8].active=false
	r.finish_shot({"first_hit":1,"pocketed":[1,8],"rail_after_contact":true},p.balls)
	check(r.winner==1,"last group plus8 not legal")
	p.reset_rack(); r.reset(); r.is_break=false; r.groups=["solid","stripe"]
	for id in range(1,8): p.balls[id].active=false
	r.begin_shot(p.balls); p.balls[8].active=false
	r.finish_shot({"first_hit":8,"pocketed":[8]},p.balls)
	check(r.winner==0,"legal8 wins")
	print("Pool core passed ",checks," checks")
	quit(1 if failed else 0)
