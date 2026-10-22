extends SceneTree
const Physics = preload("res://scripts/pool_physics.gd")
const Rules = preload("res://scripts/pool_rules.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func empty_physics():
	var p = Physics.new()
	for b in p.balls:
		b.active = false
		b.vel = Vector2.ZERO
	p.balls[0].active = true
	p.balls[0].pos = Vector2.ZERO
	return p
func report(first: int, pocketed: Array = [], rail := true, scratch := false) -> Dictionary:
	return {"first_hit":first,"pocketed":pocketed,"rail_after_contact":rail,"scratch":scratch,"rail_ids":[1,2,3,4]}
func run() -> void:
	physics_checks()
	rule_checks()
	await ui_checks()
	print("INDEPENDENT REVIEW: %d checks; %d failures" % [checks, failures.size()])
	for item in failures: push_error(item)
	quit(0 if failures.is_empty() else 1)
func physics_checks() -> void:
	var p = Physics.new()
	check(p.balls.size()==16,"16 balls")
	for i in range(16):
		check(p.balls[i].id==i and p.balls[i].active,"rack identity %d"%i)
		for j in range(i+1,16): check(p.balls[i].pos.distance_to(p.balls[j].pos)>=Physics.RADIUS*2,"rack separation")
	check(not p.shoot(Vector2.ZERO,1),"reject zero direction")
	check(not p.shoot(Vector2(INF,0),1),"reject nonfinite direction")
	check(not p.shoot(Vector2.UP,NAN),"reject nonfinite speed")
	check(not p.can_place_cue(Vector2(INF,0)),"reject nonfinite placement")
	check(not p.can_place_cue(p.balls[1].pos),"reject overlapping placement")
	for mouth in Physics.POCKETS: check(not p.can_place_cue(mouth),"reject pocket placement")
	check(not p.can_place_cue(Vector2(2,0)),"reject off-table placement")
	p = empty_physics()
	p.balls[1].active=true
	p.balls[1].pos=Vector2(0,-0.3)
	check(p.shoot(Vector2.UP,5),"max speed shot accepted")
	check(not p.shoot(Vector2.RIGHT,1),"cannot double shoot")
	check(not p.place_cue(Vector2(.3,.3)),"cannot place during motion")
	p.step(.06)
	check(p.shot_report.first_hit==1,"max speed cannot tunnel through object")
	check(p.balls[1].vel.y < -4,"equal mass impulse transfers velocity")
	var settled := false
	for frame in range(2400):
		if p.step(1.0/60.0):
			settled=true
			break
	check(settled and not p.is_moving(),"shot settles in finite time")
	check(not p.step(1.0/60.0),"settle event emitted once")
	for b in p.balls:
		check(b.pos.is_finite() and b.vel.is_finite(),"finite dynamics")
		if b.active: check(absf(b.pos.x)<=Physics.HALF_WIDTH and absf(b.pos.y)<=Physics.HALF_LENGTH,"active ball bounded")
	# All six pockets, approached on their centre line.
	for pocket in Physics.POCKETS:
		p=empty_physics()
		var inward: Vector2=-pocket.normalized()
		p.balls[0].pos=pocket+inward*.17
		check(p.shoot(-inward,1),"pocket test shot accepted")
		for frame in range(100): p.step(1.0/60.0)
		check(not p.balls[0].active and p.shot_report.scratch,"pocket captures white")
		check(p.shot_report.pocketed.count(0)==1,"pocket report unique")
		check(p.place_cue(Vector2.ZERO),"scratch can be placed after settle")
	# Frame partition invariance under normal delta limits.
	var a=Physics.new(); var b=Physics.new()
	a.shoot(Vector2(.08,-1),4.8); b.shoot(Vector2(.08,-1),4.8)
	for frame in range(120): a.step(1.0/60.0)
	for frame in range(20): b.step(.1)
	for id in range(16):
		check(a.balls[id].active==b.balls[id].active,"partition active consistency")
		check(a.balls[id].pos.distance_to(b.balls[id].pos)<.00001,"partition position consistency")
	# Multiple breaks and glancing shots must settle and retain bounds.
	for angle in [-.25,-.1,0.0,.1,.25]:
		p=Physics.new(); p.shoot(Vector2(angle,-1),5)
		for frame in range(1600):
			if p.step(1.0/60.0): break
		check(not p.is_moving(),"break settles")
		for ball in p.balls:
			if ball.active:
				check(absf(ball.pos.x)<=Physics.HALF_WIDTH and absf(ball.pos.y)<=Physics.HALF_LENGTH,"break remains bounded")
		check(p.respot_ball(8),"8 ball respot")
		for ball in p.balls:
			if ball.active and ball.id!=8: check(ball.pos.distance_to(p.balls[8].pos)>=Physics.RADIUS*2,"respot nonoverlap")
	p.reset_rack()
	check(not p.is_moving() and p.shot_report.first_hit==-1 and p.shot_report.pocketed.is_empty(),"reset clears shot")
func rule_checks() -> void:
	var p=Physics.new(); var r=Rules.new(); r.reset()
	check(not r.finish_shot(report(1),p.balls).accepted,"reject report before shot")
	check(r.begin_shot(p.balls),"start break")
	check(not r.begin_shot(p.balls),"reject repeated begin")
	p.balls[1].active=false
	r.finish_shot(report(1,[1]),p.balls)
	check(r.groups==["open","open"] and r.current_player==0,"break pot keeps turn without assigning")
	check(not r.finish_shot(report(1,[1]),p.balls).accepted,"reject repeated finish")
	r.begin_shot(p.balls); p.balls[9].active=false
	r.finish_shot(report(9,[9]),p.balls)
	check(r.groups==["stripe","solid"] and r.current_player==0,"postbreak legal pot assigns groups")
	r.begin_shot(p.balls); r.finish_shot(report(2),p.balls)
	check(r.current_player==1 and r.ball_in_hand,"wrong group gives opposing hand")
	check(not r.can_shoot() and not r.begin_shot(p.balls),"placement required")
	check(r.confirm_placement() and not r.confirm_placement(),"placement confirmed once")
	r.begin_shot(p.balls); r.finish_shot(report(2,[],false),p.balls)
	check(r.current_player==0 and r.ball_in_hand,"no rail/pot foul")
	for first in [-1,8]:
		r=Rules.new(); r.is_break=false; r.begin_shot(p.balls)
		r.finish_shot(report(first),p.balls)
		check(r.ball_in_hand and r.current_player==1,"open wrong/no contact foul")
	r=Rules.new(); r.is_break=false; r.begin_shot(p.balls)
	r.finish_shot(report(1,[1],true,true),p.balls)
	check(r.groups==["open","open"] and r.ball_in_hand,"foul pot does not assign")
	r=Rules.new(); r.begin_shot(p.balls)
	var result=r.finish_shot(report(1,[8]),p.balls)
	check(result.respot==[8] and r.winner==-1,"8 on break respotted")
	r=Rules.new(); r.begin_shot(p.balls)
	result=r.finish_shot(report(1,[8,0],true,true),p.balls)
	check(result.respot==[8] and r.ball_in_hand and r.winner==-1,"break8 scratch is hand not win")
	r=Rules.new(); r.begin_shot(p.balls)
	var weak=report(1); weak.rail_ids=[1,2,3]
	r.finish_shot(weak,p.balls)
	check(r.ball_in_hand,"weak break foul")
	r=Rules.new(); r.is_break=false; r.begin_shot(p.balls)
	r.finish_shot(report(1,[8]),p.balls)
	check(r.winner==1,"early8 loss")
	for scratch in [false,true]:
		p=Physics.new(); r=Rules.new(); r.is_break=false; r.groups=["solid","stripe"]
		for id in range(1,8): p.balls[id].active=false
		r.begin_shot(p.balls); p.balls[8].active=false
		r.finish_shot(report(8,[8],false,scratch),p.balls)
		check(r.winner==(1 if scratch else 0),"legal8 win versus scratch8 loss")
		check(not r.can_shoot() and not r.begin_shot(p.balls),"terminal locks shots")
		r.reset(); check(r.winner==-1 and r.groups==["open","open"] and not r.shot_pending,"reset after win")
	p=Physics.new(); r=Rules.new(); r.is_break=false; r.groups=["solid","stripe"]
	for id in range(2,8): p.balls[id].active=false
	r.begin_shot(p.balls); p.balls[1].active=false; p.balls[8].active=false
	r.finish_shot(report(1,[1,8]),p.balls)
	check(r.winner==1,"lastgroup+8 same shot still early8 loss")

func ui_checks() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	scene.set_process(false)
	scene.quiet_mode=true
	check(scene.start_charge(),"UI start charge")
	check(not scene.start_charge(),"UI repeated charge blocked")
	scene._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not scene.charging and scene.power==0,"focus loss cancels charge")
	scene.start_charge(); scene.toggle_camera()
	check(not scene.charging and scene.overhead,"camera switch cancels charge")
	scene.start_charge(); scene.request_restart()
	check(not scene.charging and scene.restart_dialog.visible,"restart opens confirmation and cancels charge")
	check(not scene.play_shot(Vector2.UP,.2),"modal blocks shot")
	scene.restart_dialog.hide()
	check(not scene.play_shot(Vector2(INF,0),.2),"UI nonfinite input blocked")
	check(not scene.rules.shot_pending,"invalid UI shot leaves rules idle")
	check(scene.play_shot(Vector2.UP,.08),"UI shot starts")
	check(not scene.start_charge() and not scene.play_shot(Vector2.UP,.2),"moving locks user shot")
	for frame in range(2000):
		scene._physics_process(1.0/60.0)
		if not scene.shot_active: break
	check(not scene.shot_active and not scene.rules.shot_pending,"UI settles rules once")
	check(scene.rules.shots==1,"exactly one rules result")
	scene.new_game()
	check(scene.rules.shots==0 and not scene.shot_active and not scene.charging,"new game clears UI and rules")
	check(scene.simulation.balls[0].active and scene.ball_drop.is_empty(),"newgame respawns and clears drop")
	for dims in [Vector2i(960,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dims
		await process_frame
		await process_frame
		for label in scene.player_labels+scene.group_labels+[scene.state_label,scene.hint_label]:
			check(label.get_global_rect().position.x>=-1,"label left bound")
			check(label.get_global_rect().end.x<=root.get_visible_rect().size.x+1,"label right bound")
		check(not scene.player_panels[0].get_global_rect().intersects(scene.player_panels[1].get_global_rect()),"player panels separate")
		for angle in [.65,.82]:
			for top_view in [false,true]:
				scene.overhead=top_view
				scene.camera_yaw=angle
				scene._update_camera()
				for pocket in Physics.POCKETS:
					var pixel: Vector2=scene.camera.unproject_position(Vector3(pocket.x,0,pocket.y))
					check(pixel.y+12<scene.ui.size.y-168,"all6 pockets above HUD (%s %s): %s"%[dims,top_view,pixel])
					check(pixel.y>120 and pixel.x>10 and pixel.x<scene.ui.size.x-10,"all6 pockets within clear stage")
	scene.queue_free()
	await process_frame
