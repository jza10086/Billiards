extends RefCounted
## Host-owned planar billiards in metres. roll stores the velocity equivalent of
## horizontal angular velocity; spin is vertical angular velocity in radians/s.
const HALF_WIDTH: float = 0.635
const HALF_LENGTH: float = 1.27
const RADIUS: float = 0.028575
const MAX_SPEED: float = 5.0
const MAX_TIP: float = 0.8
const FIXED_STEP: float = 1.0 / 240.0
const SLIDE_DECEL: float = 1.96
const ROLL_DECEL: float = 0.18
const SPIN_DECEL: float = 80.0
const BALL_RESTITUTION: float = 0.97
const BALL_FRICTION: float = 0.035
const RAIL_FRICTION: float = 0.18
const STOP_SPEED: float = 0.008
const CONTACT_EPSILON: float = 0.0000001
const SIDE_MOUTH: float = 0.081
const CORNER_MOUTH: float = 0.09
const POCKETS: Array[Vector2] = [
	Vector2(-HALF_WIDTH, -HALF_LENGTH), Vector2(HALF_WIDTH, -HALF_LENGTH),
	Vector2(-HALF_WIDTH, 0), Vector2(HALF_WIDTH, 0),
	Vector2(-HALF_WIDTH, HALF_LENGTH), Vector2(HALF_WIDTH, HALF_LENGTH)]
var balls: Array[Dictionary] = []
var shot_report: Dictionary = {}
var events: Array[Dictionary] = []
var shot_active: bool = false
var _accumulator: float = 0.0
var _cushions: Array[PackedVector2Array] = cushion_segments()

func _init() -> void:
	reset_rack()

## The visible cushion noses and the collision geometry share these segments.
static func cushion_segments() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			var near: Vector2 = Vector2(side * HALF_WIDTH, end * SIDE_MOUTH)
			var far: Vector2 = Vector2(side * HALF_WIDTH, end * (HALF_LENGTH - CORNER_MOUTH))
			result.append(PackedVector2Array([near, far]))
			result.append(PackedVector2Array([near, Vector2(side * (HALF_WIDTH + 0.045), end * 0.060)]))
			result.append(PackedVector2Array([far, Vector2(side * (HALF_WIDTH + 0.045), end * (HALF_LENGTH - 0.045))]))
		result.append(PackedVector2Array([
			Vector2(-HALF_WIDTH + CORNER_MOUTH, side * HALF_LENGTH),
			Vector2(HALF_WIDTH - CORNER_MOUTH, side * HALF_LENGTH)]))
		for end: float in [-1.0, 1.0]:
			result.append(PackedVector2Array([
				Vector2(end * (HALF_WIDTH - CORNER_MOUTH), side * HALF_LENGTH),
				Vector2(end * (HALF_WIDTH - 0.045), side * (HALF_LENGTH + 0.045))]))
	return result

func reset_rack() -> void:
	balls.clear()
	for id: int in 10:
		balls.append({"id": id, "pos": Vector2.ZERO, "vel": Vector2.ZERO,
			"roll": Vector2.ZERO, "spin": 0.0, "orientation": Quaternion.IDENTITY, "active": true})
	balls[0].pos = Vector2(0, 0.66)
	var rows: Array[int] = [1, 2, 3, 2, 1]
	var order: Array[int] = [1, 2, 3, 4, 9, 5, 6, 7, 8]
	var spacing: float = RADIUS * 2.0 + 0.00001
	var index: int = 0
	for row: int in rows.size():
		for col: int in rows[row]:
			balls[order[index]].pos = Vector2(
				(col - (rows[row] - 1) * 0.5) * spacing,
				-0.60 - row * spacing * sqrt(3.0) * 0.5)
			index += 1
	shot_active = false
	_accumulator = 0.0
	_clear_report()
	events.clear()

func _clear_report() -> void:
	shot_report = {"first_hit": -1, "rail_after_contact": false, "rail_ids": [], "pocketed": [], "scratch": false}

func is_moving() -> bool:
	return shot_active

func can_place_cue(pos: Vector2) -> bool:
	if not pos.is_finite() or is_moving():
		return false
	if absf(pos.x) > HALF_WIDTH - RADIUS - 0.003 or absf(pos.y) > HALF_LENGTH - RADIUS - 0.003:
		return false
	for pocket: Vector2 in POCKETS:
		if pos.distance_to(pocket) < 0.085 + RADIUS:
			return false
	for ball: Dictionary in balls:
		if ball.id != 0 and ball.active and pos.distance_to(ball.pos) < RADIUS * 2.0 + 0.001:
			return false
	return true

func _stop_ball(ball: Dictionary) -> void:
	ball.vel = Vector2.ZERO
	ball.roll = Vector2.ZERO
	ball.spin = 0.0

func place_cue(pos: Vector2) -> bool:
	if not can_place_cue(pos):
		return false
	balls[0].pos = pos
	_stop_ball(balls[0])
	balls[0].active = true
	return true

## tip.x is right english, tip.y is follow (positive) / draw (negative).
## Callers validate the normalized tip disk and speed at the action boundary.
func shoot(direction: Vector2, speed: float, tip: Vector2) -> bool:
	if is_moving() or not balls[0].active:
		return false
	_clear_report()
	events.clear()
	var forward: Vector2 = direction.normalized()
	balls[0].vel = forward * speed
	# Solid sphere I = 2/5 mr²: an offset impulse produces 2.5 * offset * v/r.
	balls[0].roll = forward * (2.5 * tip.y * speed)
	balls[0].spin = 2.5 * tip.x * speed / RADIUS
	shot_active = true
	_accumulator = 0.0
	return true

func step(delta: float) -> bool:
	events.clear()
	if not shot_active:
		return false
	# Preserve elapsed time even on a long rendering frame.
	_accumulator += delta
	while _accumulator + 0.000000001 >= FIXED_STEP:
		_tick(FIXED_STEP)
		_accumulator = maxf(0.0, _accumulator - FIXED_STEP)
		var moving: bool = false
		for ball: Dictionary in balls:
			if ball.active and (ball.vel != Vector2.ZERO or ball.roll != Vector2.ZERO or ball.spin != 0.0):
				moving = true
				break
		if not moving:
			shot_active = false
			_accumulator = 0.0
			return true
	return false

## Sliding friction couples translation and rotation, then rolling resistance
## removes energy without reversing the ball. Backspin can restart a stunned cue.
func _cloth(ball: Dictionary, dt: float) -> void:
	var slip: Vector2 = ball.vel - ball.roll
	var slip_speed: float = slip.length()
	var sliding_time: float = minf(dt, slip_speed / (3.5 * SLIDE_DECEL))
	if slip_speed > 0.0:
		var change: Vector2 = slip / slip_speed * SLIDE_DECEL * sliding_time
		ball.vel -= change
		ball.roll += change * 2.5
	if sliding_time < dt:
		ball.vel = Vector2(ball.vel).move_toward(Vector2.ZERO, ROLL_DECEL * (dt - sliding_time))
		ball.roll = ball.vel
	ball.spin = move_toward(ball.spin, 0.0, SPIN_DECEL * dt)
	if Vector2(ball.vel).length() < STOP_SPEED and Vector2(ball.roll).length() < STOP_SPEED:
		ball.vel = Vector2.ZERO
		ball.roll = Vector2.ZERO

func _tick(dt: float) -> void:
	for ball: Dictionary in balls:
		if ball.active:
			_cloth(ball, dt * 0.5)
	var remaining: float = dt
	while remaining > 0.000000001:
		var contact: Dictionary = _next_contact(remaining)
		var travel: float = contact.time
		for ball: Dictionary in balls:
			if ball.active:
				ball.pos += ball.vel * travel
				var angular: Vector3 = Vector3(ball.roll.y / RADIUS, ball.spin, -ball.roll.x / RADIUS)
				if angular.length_squared() > 0.0:
					ball.orientation = (Quaternion(angular.normalized(), angular.length() * travel) * ball.orientation).normalized()
				_capture(ball)
		remaining -= travel
		if contact.a < 0:
			break
		var a: Dictionary = balls[contact.a]
		if a.active:
			if contact.b >= 0:
				if balls[contact.b].active:
					_collide(a, balls[contact.b])
			else:
				_bounce_cushion(a, contact.normal)
	for ball: Dictionary in balls:
		if ball.active:
			_cloth(ball, dt * 0.5)

## Time of impact avoids missed thin cuts and preserves the actual first contact,
## including the close-packed opening rack. No position-dependent random impulses.
static func _circle_time(relative: Vector2, velocity: Vector2, radius: float, limit: float) -> float:
	var approach: float = relative.dot(velocity)
	if approach >= -0.000000001:
		return INF
	var c: float = relative.length_squared() - radius * radius
	if c <= CONTACT_EPSILON * radius:
		return 0.0
	var speed_squared: float = velocity.length_squared()
	var discriminant: float = approach * approach - speed_squared * c
	if discriminant < 0.0:
		return INF
	var time: float = c / (-approach + sqrt(discriminant))
	return time if time <= limit else INF

func _next_contact(limit: float) -> Dictionary:
	var result: Dictionary = {"time": limit, "a": -1, "b": -1, "normal": Vector2.ZERO}
	for i: int in balls.size():
		var a: Dictionary = balls[i]
		if not a.active:
			continue
		for j: int in range(i + 1, balls.size()):
			var b: Dictionary = balls[j]
			if not b.active:
				continue
			var time: float = _circle_time(b.pos - a.pos, b.vel - a.vel, RADIUS * 2.0, result.time)
			if time < result.time:
				result = {"time": time, "a": i, "b": j, "normal": Vector2.ZERO}
		if a.vel == Vector2.ZERO:
			continue
		for segment: PackedVector2Array in _cushions:
			var edge: Vector2 = segment[1] - segment[0]
			var length: float = edge.length()
			var tangent: Vector2 = edge / length
			var normal: Vector2 = Vector2(-tangent.y, tangent.x)
			var distance: float = (Vector2(a.pos) - segment[0]).dot(normal)
			if distance < 0.0:
				normal = -normal
				distance = -distance
			var approach: float = Vector2(a.vel).dot(normal)
			if approach < -0.000000001:
				var time: float = maxf(0.0, (RADIUS - distance) / approach)
				var along: float = (Vector2(a.pos) + Vector2(a.vel) * time - segment[0]).dot(tangent)
				if time < result.time and along >= 0.0 and along <= length:
					result = {"time": time, "a": i, "b": -1, "normal": normal}
			for point: Vector2 in segment:
				var time: float = _circle_time(a.pos - point, a.vel, RADIUS, result.time)
				if time < result.time:
					var hit_normal: Vector2 = (Vector2(a.pos) + Vector2(a.vel) * time - point).normalized()
					result = {"time": time, "a": i, "b": -1, "normal": hit_normal}
	return result

func _capture(ball: Dictionary) -> void:
	var p: Vector2 = ball.pos
	# A ball must cross the pocket throat, not merely touch a large circular zone.
	var side: bool = absf(p.x) >= HALF_WIDTH and absf(p.y) < 0.060
	var corner: bool = absf(p.x) > HALF_WIDTH - CORNER_MOUTH and absf(p.y) > HALF_LENGTH - CORNER_MOUTH and absf(p.x) + absf(p.y) >= HALF_WIDTH + HALF_LENGTH - 0.030
	if not side and not corner:
		return
	ball.active = false
	_stop_ball(ball)
	shot_report.pocketed.append(ball.id)
	if ball.id == 0:
		shot_report.scratch = true
	events.append({"type": "pocket", "id": ball.id, "position": ball.pos})

func _collide(a: Dictionary, b: Dictionary) -> void:
	var separation: Vector2 = b.pos - a.pos
	var normal: Vector2 = separation.normalized()
	var correction: float = maxf(0.0, RADIUS * 2.0 - separation.length()) * 0.5 + CONTACT_EPSILON
	a.pos -= normal * correction
	b.pos += normal * correction
	var approach: float = (Vector2(a.vel) - Vector2(b.vel)).dot(normal)
	var normal_impulse: float = approach * (1.0 + BALL_RESTITUTION) * 0.5
	var tangent: Vector2 = Vector2(-normal.y, normal.x)
	var slip: float = (Vector2(a.vel) - Vector2(b.vel)).dot(tangent) - RADIUS * (a.spin + b.spin)
	var friction: float = clampf(slip / 7.0, -BALL_FRICTION * normal_impulse, BALL_FRICTION * normal_impulse)
	var impulse: Vector2 = normal * normal_impulse + tangent * friction
	a.vel -= impulse
	b.vel += impulse
	a.spin += friction * 2.5 / RADIUS
	b.spin += friction * 2.5 / RADIUS
	if shot_report.first_hit == -1:
		if a.id == 0:
			shot_report.first_hit = b.id
		elif b.id == 0:
			shot_report.first_hit = a.id
	if approach > 0.05:
		events.append({"type": "collision", "speed": approach, "position": (a.pos + b.pos) * 0.5})

func _bounce_cushion(ball: Dictionary, normal: Vector2) -> void:
	var speed: float = -Vector2(ball.vel).dot(normal)
	# Hard hits compress the cushion more; normal restitution decreases smoothly.
	var restitution: float = lerpf(0.86, 0.70, clampf(speed / MAX_SPEED, 0.0, 1.0))
	var normal_impulse: float = speed * (1.0 + restitution)
	var tangent: Vector2 = Vector2(-normal.y, normal.x)
	var slip: float = Vector2(ball.vel).dot(tangent) + ball.spin * RADIUS
	var friction: float = clampf(-slip / 3.5, -RAIL_FRICTION * normal_impulse, RAIL_FRICTION * normal_impulse)
	ball.vel += normal * normal_impulse + tangent * friction
	ball.spin += friction * 2.5 / RADIUS
	ball.pos += normal * CONTACT_EPSILON
	if shot_report.first_hit >= 0:
		shot_report.rail_after_contact = true
		if not shot_report.rail_ids.has(ball.id):
			shot_report.rail_ids.append(ball.id)
	if speed > 0.05:
		events.append({"type": "rail", "id": ball.id, "position": ball.pos, "speed": speed})

func respot_ball(id: int) -> bool:
	if id < 0 or id >= balls.size() or is_moving():
		return false
	var candidates: Array[Vector2] = [Vector2(0, -0.60)]
	for row: int in 35:
		candidates.append(Vector2(0, -1.12 + row * 0.065))
	for row: int in 32:
		for col: int in 17:
			candidates.append(Vector2(-0.52 + col * 0.065, -1.05 + row * 0.065))
	for p: Vector2 in candidates:
		var free: bool = true
		for other: Dictionary in balls:
			if other.id != id and other.active and p.distance_to(other.pos) < RADIUS * 2.0 + 0.001:
				free = false
				break
		if free:
			balls[id].pos = p
			_stop_ball(balls[id])
			balls[id].active = true
			return true
	return false
