class_name PoolPhysics
extends RefCounted
## Deterministic planar, fixed-step equal-mass billiards. Coordinates are metres (x,z).
const HALF_WIDTH := 0.635
const HALF_LENGTH := 1.27
const RADIUS := 0.028575
const POCKET_RADIUS := 0.073
const MAX_SPEED := 5.0
const FIXED_STEP := 1.0 / 480.0
const ROLL_DECEL := 0.24
const BALL_RESTITUTION := 0.97
const RAIL_RESTITUTION := 0.78
const STOP_SPEED := 0.012
const POCKETS := [Vector2(-HALF_WIDTH,-HALF_LENGTH), Vector2(HALF_WIDTH,-HALF_LENGTH), Vector2(-HALF_WIDTH,0), Vector2(HALF_WIDTH,0), Vector2(-HALF_WIDTH,HALF_LENGTH), Vector2(HALF_WIDTH,HALF_LENGTH)]
var balls: Array[Dictionary] = []
var shot_report: Dictionary = {}
var events: Array[Dictionary] = []
var shot_active := false
var _accumulator := 0.0

func _init() -> void:
	reset_rack()

func reset_rack() -> void:
	balls.clear()
	for id in range(16):
		balls.append({"id":id,"pos":Vector2.ZERO,"vel":Vector2.ZERO,"active":true})
	balls[0].pos = Vector2(0,0.66)
	# 8 in centre; opposing back corners belong to opposite groups.
	var order := [1,9,2,3,8,10,11,4,12,5,6,13,7,14,15]
	var k := 0
	var spacing := RADIUS * 2.0 + 0.0003
	for row in range(5):
		for col in range(row + 1):
			balls[order[k]].pos = Vector2((float(col)-float(row)*0.5)*spacing,-0.60-float(row)*spacing*sqrt(3.0)*0.5)
			k += 1
	shot_active = false
	_accumulator = 0.0
	_clear_report()
	events.clear()

func _clear_report() -> void:
	shot_report = {"first_hit":-1,"rail_after_contact":false,"rail_ids":[],"pocketed":[],"scratch":false}

func is_moving() -> bool:
	if shot_active:
		return true
	for ball in balls:
		if ball.active and ball.vel.length_squared() > 0.0:
			return true
	return false

func can_place_cue(pos: Vector2) -> bool:
	if not pos.is_finite() or is_moving():
		return false
	if absf(pos.x) > HALF_WIDTH-RADIUS-0.003 or absf(pos.y) > HALF_LENGTH-RADIUS-0.003:
		return false
	for pocket in POCKETS:
		if pos.distance_to(pocket) < POCKET_RADIUS + RADIUS:
			return false
	for ball in balls:
		if ball.id != 0 and ball.active and pos.distance_to(ball.pos) < RADIUS*2.0+0.001:
			return false
	return true

func place_cue(pos: Vector2) -> bool:
	if not can_place_cue(pos):
		return false
	balls[0].pos = pos
	balls[0].vel = Vector2.ZERO
	balls[0].active = true
	return true

func shoot(direction: Vector2, speed: float) -> bool:
	if is_moving() or not balls[0].active or not direction.is_finite() or not is_finite(speed):
		return false
	if direction.length_squared() < 0.000001 or speed <= 0.0:
		return false
	_clear_report()
	events.clear()
	balls[0].vel = direction.normalized()*clampf(speed,0.05,MAX_SPEED)
	shot_active = true
	_accumulator = 0.0
	return true

func step(delta: float) -> bool:
	events.clear()
	if not shot_active or not is_finite(delta) or delta <= 0.0:
		return false
	# Keep elapsed time, including slow rendering, rather than dropping physics time.
	_accumulator += minf(delta,0.25)
	while _accumulator + 0.000000001 >= FIXED_STEP:
		_tick(FIXED_STEP)
		_accumulator = maxf(0.0, _accumulator - FIXED_STEP)
		var moving := false
		for ball in balls:
			if ball.active and ball.vel.length_squared() > 0.0:
				moving = true
				break
		if not moving:
			shot_active = false
			_accumulator = 0.0
			return true
	return false

func _tick(dt: float) -> void:
	for ball in balls:
		if not ball.active:
			continue
		ball.pos += ball.vel*dt
		var speed: float = ball.vel.length()
		if speed <= ROLL_DECEL*dt + STOP_SPEED:
			ball.vel = Vector2.ZERO
		else:
			ball.vel *= (speed-ROLL_DECEL*dt)/speed
		_capture(ball)
	# Two solver passes prevent rack overlap from accumulating.
	for iteration in range(2):
		for i in range(balls.size()):
			if not balls[i].active:
				continue
			for j in range(i+1,balls.size()):
				if balls[j].active:
					_collide(balls[i],balls[j])
		for ball in balls:
			if ball.active:
				_rail(ball)
				_capture(ball)

func _capture(ball: Dictionary) -> void:
	for pocket in POCKETS:
		if ball.pos.distance_to(pocket) < POCKET_RADIUS:
			ball.active = false
			ball.vel = Vector2.ZERO
			shot_report.pocketed.append(ball.id)
			if ball.id == 0:
				shot_report.scratch = true
			events.append({"type":"pocket","id":ball.id,"position":ball.pos})
			return

func _collide(a: Dictionary,b: Dictionary) -> void:
	var separation: Vector2 = b.pos-a.pos
	var distance := separation.length()
	var diameter := RADIUS*2.0
	if distance >= diameter:
		return
	var normal := separation/distance if distance > 0.000001 else Vector2.RIGHT
	var overlap := diameter-distance
	a.pos -= normal*(overlap*0.5+0.0000001)
	b.pos += normal*(overlap*0.5+0.0000001)
	var approach: float = (a.vel-b.vel).dot(normal)
	if approach <= 0.0:
		return
	var impulse := normal*approach*(1.0+BALL_RESTITUTION)*0.5
	a.vel -= impulse
	b.vel += impulse
	if shot_report.first_hit == -1:
		if a.id == 0:
			shot_report.first_hit = b.id
		elif b.id == 0:
			shot_report.first_hit = a.id
	if approach > 0.05:
		events.append({"type":"collision","speed":approach,"position":(a.pos+b.pos)*0.5})

func _rail(ball: Dictionary) -> void:
	var p: Vector2 = ball.pos
	var v: Vector2 = ball.vel
	var hit := false
	# Pocket circles extend inward past rail faces. Outside a mouth, solid rails
	# constrain centre positions. Open mouths are funnelled to the pocket.
	var side_mouth := absf(p.y) < 0.066 or absf(p.y) > HALF_LENGTH-0.068
	var end_mouth := absf(p.x) > HALF_WIDTH-0.068
	if absf(p.x) > HALF_WIDTH-RADIUS:
		if side_mouth:
			if absf(p.x) > HALF_WIDTH:
				_capture(ball)
				if ball.active:
					p.x = signf(p.x)*(HALF_WIDTH-RADIUS)
					v.x = -v.x*RAIL_RESTITUTION
					hit = true
		else:
			p.x = signf(p.x)*(HALF_WIDTH-RADIUS)
			if v.x*signf(p.x) > 0:
				v.x = -v.x*RAIL_RESTITUTION
				hit = true
	if absf(p.y) > HALF_LENGTH-RADIUS:
		if end_mouth:
			if absf(p.y) > HALF_LENGTH:
				_capture(ball)
				if ball.active:
					p.y = signf(p.y)*(HALF_LENGTH-RADIUS)
					v.y = -v.y*RAIL_RESTITUTION
					hit = true
		else:
			p.y = signf(p.y)*(HALF_LENGTH-RADIUS)
			if v.y*signf(p.y) > 0:
				v.y = -v.y*RAIL_RESTITUTION
				hit = true
	ball.pos = p
	if ball.active:
		ball.vel = v
	if hit:
		if shot_report.first_hit >= 0:
			shot_report.rail_after_contact = true
			if not shot_report.rail_ids.has(ball.id):
				shot_report.rail_ids.append(ball.id)
		events.append({"type":"rail","id":ball.id,"position":p,"speed":v.length()})

func respot_ball(id: int) -> bool:
	if id < 0 or id >= balls.size() or is_moving():
		return false
	# Preferred foot spot, then centre-line scan; deterministic and overlap free.
	var candidates: Array[Vector2] = [Vector2(0,-0.60)]
	for row in range(35):
		candidates.append(Vector2(0,-1.12+row*0.065))
	for row in range(32):
		for col in range(17):
			candidates.append(Vector2(-0.52+col*0.065,-1.05+row*0.065))
	for p in candidates:
		var free := true
		for other in balls:
			if other.id != id and other.active and p.distance_to(other.pos) < RADIUS*2.0+0.001:
				free = false
				break
		if free:
			balls[id].pos = p
			balls[id].vel = Vector2.ZERO
			balls[id].active = true
			return true
	return false
