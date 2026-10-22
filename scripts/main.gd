extends Node3D

const Physics = preload("res://scripts/pool_physics.gd")
const Rules = preload("res://scripts/pool_rules.gd")
const Art = preload("res://scripts/table_art.gd")
const GOLD = Color("d9b77d")
const IVORY = Color("eee8d9")
var simulation = Physics.new()
var rules = Rules.new()
var art: Node3D
var balls: Array[Node3D] = []
var camera: Camera3D
var cue: Node3D
var aim_line: MeshInstance3D
var ghost: MeshInstance3D
var aim_direction := Vector2(0,-1)
var camera_yaw := 0.82
var camera_elevation := 0.92
var camera_distance := 4.8
var overhead := false
var orbiting := false
var charging := false
var power := 0.0
var charge_time := 0.0
var placement := Vector2(0,0.6)
var placement_valid := false
var shot_active := false
var shot_number := 0
var ball_drop: Dictionary = {}
var ui: Control
var player_labels: Array[Label] = []
var group_labels: Array[Label] = []
var player_panels: Array[PanelContainer] = []
var state_label: Label
var hint_label: Label
var power_bar: ProgressBar
var power_label: Label
var status_label: Label
var camera_button: Button
var help_dialog: AcceptDialog
var restart_dialog: ConfirmationDialog
var last_mouse := Vector2.ZERO
var quiet_mode := false
var last_collision_sound := -1000
var sound_player: AudioStreamPlayer
var pocket_player: AudioStreamPlayer

func _ready() -> void:
	art = Art.new()
	add_child(art)
	art.build()
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 43
	camera.near = 0.02
	camera.far = 80
	_update_camera()
	for number in range(16):
		var ball: Node3D = art.make_ball(number)
		add_child(ball)
		balls.append(ball)
	cue = art.make_cue()
	add_child(cue)
	aim_line = _line_mesh(Color(0.85,0.84,0.69,0.65))
	ghost = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.029
	sphere.height = 0.058
	ghost.mesh = sphere
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(0.9,0.85,0.65,0.18)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = ghost_mat
	add_child(ghost)
	_build_ui()
	_setup_audio()
	new_game()

func _setup_audio() -> void:
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)
	pocket_player = AudioStreamPlayer.new()
	add_child(pocket_player)
	if ResourceLoader.exists("res://assets/audio/impactWood_light_001.ogg"):
		sound_player.stream = load("res://assets/audio/impactWood_light_001.ogg")
	if ResourceLoader.exists("res://assets/audio/impactSoft_medium_000.ogg"):
		pocket_player.stream = load("res://assets/audio/impactSoft_medium_000.ogg")
	sound_player.volume_db = -15
	pocket_player.volume_db = -12

func new_game() -> void:
	charging = false
	shot_active = false
	power = 0
	shot_number = 0
	ball_drop.clear()
	simulation.reset_rack()
	rules.reset()
	aim_direction = Vector2(0,-1)
	_sync_balls(0)
	_refresh_ui()

func _physics_process(delta: float) -> void:
	if not shot_active:
		return
	var before: Array = []
	for ball in simulation.balls:
		before.append(ball.active)
	var settled: bool = simulation.step(delta)
	for event in simulation.events:
		if event.type == "collision" and event.get("speed",0.0)>0.15 and Time.get_ticks_msec()-last_collision_sound>70 and not quiet_mode and sound_player.stream:
			sound_player.volume_db = clampf(-24+event.speed*4,-24,-10)
			sound_player.pitch_scale = randf_range(0.92,1.08)
			sound_player.play()
			last_collision_sound = Time.get_ticks_msec()
	for i in range(16):
		if before[i] and not simulation.balls[i].active:
			ball_drop[i] = 0.0
			if not quiet_mode and pocket_player.stream:
				pocket_player.play()
	if settled:
		shot_active = false
		var result: Dictionary = rules.finish_shot(simulation.shot_report,simulation.balls)
		for number in result.get("respot",[]):
			simulation.respot_ball(number)
			ball_drop.erase(number)
		if rules.ball_in_hand:
			placement = Vector2(0,0.65)
			placement_valid = simulation.can_place_cue(placement)
		_refresh_ui()

func _process(delta: float) -> void:
	if charging:
		charge_time += delta
		power = clampf(charge_time/1.6,0.04,1.0)
		power_bar.value = power*100
		power_label.text = "%02d%%" % int(power*100)
	_sync_balls(delta)
	_update_aim()

func _sync_balls(delta: float) -> void:
	for i in range(balls.size()):
		var data: Dictionary = simulation.balls[i]
		var node := balls[i]
		if ball_drop.has(i):
			ball_drop[i] += delta
			var t: float = ball_drop[i]
			node.visible = t < 0.38
			node.position = Vector3(data.pos.x,0.028575-t*t*1.7,data.pos.y)
			node.scale = Vector3.ONE * maxf(0.05,1-t*1.6)
		elif data.active:
			node.visible = true
			node.scale = Vector3.ONE
			node.position = Vector3(data.pos.x,0.028575,data.pos.y)
			var velocity: Vector2 = data.vel
			if velocity.length_squared() > 0.0001:
				node.rotate(Vector3(velocity.y,0,-velocity.x).normalized(),velocity.length()*delta/0.028575)
		else:
			node.visible = false
	if rules.ball_in_hand and not shot_active and rules.winner < 0:
		balls[0].visible = true
		balls[0].scale = Vector3.ONE
		balls[0].position = Vector3(placement.x,0.032,placement.y)

func _line_mesh(color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = material
	add_child(node)
	return node

func _update_aim() -> void:
	var available: bool = not shot_active and rules.winner < 0 and not _modal_visible()
	cue.visible = available and not rules.ball_in_hand
	aim_line.visible = cue.visible
	ghost.visible = available and rules.ball_in_hand
	if rules.ball_in_hand:
		ghost.position = Vector3(placement.x,0.035,placement.y)
		var mat: StandardMaterial3D = ghost.material_override
		mat.albedo_color = Color(0.4,0.9,0.7,0.3) if placement_valid else Color(1,0.25,0.2,0.4)
	if not cue.visible:
		return
	var start: Vector2 = simulation.balls[0].pos
	var dir := Vector3(aim_direction.x,0,aim_direction.y)
	cue.position = Vector3(start.x,0.031,start.y) - dir*(0.05+power*0.22)
	cue.look_at(cue.position+dir,Vector3.UP)
	var distance := 1.35
	for number in range(1,16):
		var other: Dictionary = simulation.balls[number]
		if not other.active:
			continue
		var offset: Vector2 = other.pos-start
		var forward := offset.dot(aim_direction)
		var perpendicular := offset.length_squared()-forward*forward
		var diameter := 0.05715
		if forward>0 and perpendicular<diameter*diameter:
			distance = minf(distance,maxf(0.0,forward-sqrt(diameter*diameter-perpendicular)))
	if absf(aim_direction.x)>0.001:
		distance = minf(distance,((0.606*signf(aim_direction.x))-start.x)/aim_direction.x)
	if absf(aim_direction.y)>0.001:
		distance = minf(distance,((1.241*signf(aim_direction.y))-start.y)/aim_direction.y)
	var end := start+aim_direction*maxf(distance,0.01)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(Vector3(start.x,0.031,start.y))
	mesh.surface_add_vertex(Vector3(end.x,0.031,end.y))
	mesh.surface_end()
	aim_line.mesh = mesh

func _screen_table(screen: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	return Plane(Vector3.UP,0.028575).intersects_ray(origin,direction)

func _input(event: InputEvent) -> void:
	# A release over a HUD button must not leave the cue charging indefinitely.
	if charging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if get_viewport().gui_get_hovered_control() != null:
			cancel_charge()
		else:
			release_shot()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel_charge()
			if help_dialog.visible: help_dialog.hide()
			elif restart_dialog.visible: restart_dialog.hide()
			else: help_dialog.popup_centered(Vector2i(640,450))
		if _modal_visible(): return
		if event.keycode == KEY_V: toggle_camera()
		if event.keycode == KEY_R: request_restart()
		if event.keycode == KEY_SPACE: start_charge()
	if event is InputEventKey and not event.pressed and event.keycode == KEY_SPACE:
		release_shot()
	if _modal_visible(): return
	if event is InputEventMouseMotion:
		last_mouse = event.position
		if orbiting:
			camera_yaw -= event.relative.x*0.006
			camera_elevation = clampf(camera_elevation+event.relative.y*0.004,0.4,1.3)
			overhead = false
			_update_camera()
		elif not charging and not shot_active:
			var point = _screen_table(event.position)
			if point != null:
				if rules.ball_in_hand:
					placement = Vector2(point.x,point.z)
					placement_valid = simulation.can_place_cue(placement)
				else:
					var direction: Vector2 = Vector2(point.x,point.z)-simulation.balls[0].pos
					if direction.length()>0.04: aim_direction = direction.normalized()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed
			cancel_charge()
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clampf(camera_distance-0.2,2.7,5.6)
			_update_camera()
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clampf(camera_distance+0.2,2.7,5.6)
			_update_camera()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and rules.ball_in_hand and not shot_active and rules.winner<0:
				if simulation.place_cue(placement):
					rules.confirm_placement()
					ball_drop.erase(0)
					_refresh_ui()
			elif event.pressed: start_charge()
			else: release_shot()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_charge()
		orbiting = false

func start_charge() -> bool:
	if shot_active or charging or rules.winner >= 0 or rules.ball_in_hand or _modal_visible():
		return false
	charging = true
	charge_time = 0
	power = 0.04
	return true

func cancel_charge() -> void:
	charging = false
	power = 0
	if power_bar:
		power_bar.value = 0
		power_label.text = "蓄力"

func release_shot() -> bool:
	if not charging:
		return false
	var strength := maxf(power,0.04)
	cancel_charge()
	return play_shot(aim_direction,strength)

func play_shot(direction: Vector2,strength: float) -> bool:
	if shot_active or rules.winner>=0 or rules.ball_in_hand or _modal_visible(): return false
	if not direction.is_finite() or direction.length()<0.01 or not is_finite(strength): return false
	if simulation.is_moving() or not rules.can_shoot(): return false
	if not rules.begin_shot(simulation.balls): return false
	if not simulation.shoot(direction.normalized(),lerpf(0.35,4.8,clampf(strength,0,1))): return false
	shot_active = true
	shot_number += 1
	if sound_player.stream and not quiet_mode:
		sound_player.pitch_scale = randf_range(0.95,1.05)
		sound_player.play()
	_refresh_ui()
	return true

func _modal_visible() -> bool:
	return (help_dialog != null and help_dialog.visible) or (restart_dialog != null and restart_dialog.visible)

func request_restart() -> void:
	cancel_charge()
	restart_dialog.popup_centered(Vector2i(420,180))

func toggle_camera() -> void:
	cancel_charge()
	overhead = not overhead
	_update_camera()
	camera_button.text = "斜视  V" if overhead else "俯视  V"

func _update_camera() -> void:
	if overhead:
		camera.position = Vector3(0,5.7,0.01)
		camera.v_offset = -0.25
		camera.look_at(Vector3.ZERO,Vector3(0,0,-1))
	else:
		camera.v_offset = -0.35
		camera.position = Vector3(sin(camera_yaw)*cos(camera_elevation),sin(camera_elevation),cos(camera_yaw)*cos(camera_elevation))*camera_distance
		camera.look_at(Vector3(0,-0.08,0),Vector3.UP)

func _style(background: Color,border: Color=Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left=18
	style.content_margin_right=18
	style.content_margin_top=12
	style.content_margin_bottom=12
	return style

func _label(text: String,size: int,color: Color=IVORY) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	return label

func _button(text: String,callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(96,42)
	button.add_theme_stylebox_override("normal",_style(Color("17282b"),Color("43504b")))
	button.add_theme_stylebox_override("hover",_style(Color("29413e"),GOLD))
	button.add_theme_stylebox_override("pressed",_style(Color("34534a"),GOLD))
	button.pressed.connect(callback)
	return button

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	ui = Control.new()
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	theme.default_font_size = 16
	ui.theme = theme
	var top := MarginContainer.new()
	ui.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left=28; top.offset_right=-28; top.offset_top=24; top.offset_bottom=122
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	top.add_child(row)
	row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for index in range(3):
		if index == 1:
			var title_box := VBoxContainer.new()
			title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title_box.mouse_filter=Control.MOUSE_FILTER_IGNORE
			row.add_child(title_box)
			var title := _label("N O C T U R N E",24,GOLD)
			title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			title_box.add_child(title)
			var subtitle := _label("夜幕球房  /  EIGHT BALL",13,Color("92a9a3"))
			subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			title_box.add_child(subtitle)
		else:
			var panel := PanelContainer.new()
			panel.custom_minimum_size=Vector2(245,82)
			panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
			row.add_child(panel)
			player_panels.append(panel)
			var box := VBoxContainer.new()
			box.mouse_filter=Control.MOUSE_FILTER_IGNORE
			panel.add_child(box)
			var label := _label("",20)
			box.add_child(label)
			player_labels.append(label)
			var group := _label("",14,Color("a8b9b2"))
			box.add_child(group)
			group_labels.append(group)
	var bottom_back := Panel.new()
	ui.add_child(bottom_back)
	bottom_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_back.offset_top=-168
	bottom_back.add_theme_stylebox_override("panel",_style(Color(0.025,0.05,0.055,0.94)))
	bottom_back.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var bottom := MarginContainer.new()
	ui.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left=28; bottom.offset_right=-28; bottom.offset_top=-155; bottom.offset_bottom=-22
	bottom.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var bottom_box := VBoxContainer.new()
	bottom_box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bottom_box)
	state_label = _label("",23,GOLD)
	state_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	bottom_box.add_child(state_label)
	status_label = _label("",14,Color("b5c5bd"))
	status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	bottom_box.add_child(status_label)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation",12)
	controls.alignment=BoxContainer.ALIGNMENT_CENTER
	bottom_box.add_child(controls)
	camera_button = _button("俯视  V",toggle_camera)
	controls.add_child(camera_button)
	controls.add_child(_button("玩法  Esc",func(): cancel_charge(); help_dialog.popup_centered(Vector2i(640,450))))
	var power_box := VBoxContainer.new()
	power_box.custom_minimum_size=Vector2(270,0)
	controls.add_child(power_box)
	power_label = _label("蓄力",13,GOLD)
	power_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	power_box.add_child(power_label)
	power_bar = ProgressBar.new()
	power_bar.custom_minimum_size=Vector2(270,11)
	power_bar.show_percentage=false
	power_bar.add_theme_stylebox_override("background",_style(Color("253330")))
	power_bar.add_theme_stylebox_override("fill",_style(GOLD))
	power_box.add_child(power_bar)
	controls.add_child(_button("重新开局",request_restart))
	var mute := _button("声音：开",func(): quiet_mode=not quiet_mode)
	mute.pressed.connect(func(): mute.text="声音：关" if quiet_mode else "声音：开")
	controls.add_child(mute)
	hint_label=_label("鼠标瞄准 · 按住左键 / 空格蓄力，松开击球 · 右键拖动视角 · 滚轮缩放",13,Color("80978f"))
	hint_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	bottom_box.add_child(hint_label)
	help_dialog=AcceptDialog.new()
	help_dialog.title="夜幕球房 · 操作与简化八球规则"
	help_dialog.dialog_text="本地双人轮流操作，同屏美式八球。\n\n鼠标移动瞄准，按住左键或空格蓄力，松开击球。\n右键拖动旋转视角，滚轮缩放，V 切换俯视。\n犯规后对手获得自由球：移动鼠标，点击合法位置放置白球。\n\n开球后球台开放，首次合法进球确定全色 / 花色。\n先碰己方球，击中后必须有球入袋或碰库。\n合法进己方球可继续；白球入袋、未碰球或错球为犯规。\n清完己方球后再单独打入黑 8 获胜，提前入袋或黑 8 同时犯规则输。\n开球黑 8 重置，不直接结束比赛。\n\n这是休闲简化版：不含叫袋、跳球、旋转 / 塞、比赛裁判细则。"
	ui.add_child(help_dialog)
	restart_dialog=ConfirmationDialog.new()
	restart_dialog.title="重新开局"
	restart_dialog.dialog_text="结束当前对局，重新摆球？"
	restart_dialog.confirmed.connect(new_game)
	ui.add_child(restart_dialog)

func _refresh_ui() -> void:
	for player in range(2):
		var active: bool = rules.current_player==player and rules.winner<0
		player_panels[player].add_theme_stylebox_override("panel",_style(Color(0.035,0.075,0.08,0.92),GOLD if active else Color("283c3b")))
		player_labels[player].text=("●  " if active else "○  ")+"玩家 %d"%(player+1)
		var group: String = rules.groups[player]
		var caption := "球台开放 · 尚未分组"
		if group != "open":
			caption=("全色  1—7" if group=="solid" else "花色  9—15")+"  ·  剩余 %d"%rules.remaining(player,simulation.balls)
		group_labels[player].text=caption
	if rules.winner>=0:
		state_label.text="玩家 %d 获胜"%(rules.winner+1)
	elif shot_active:
		state_label.text="球在运动中"
	elif rules.ball_in_hand:
		state_label.text="玩家 %d · 自由球，请放置白球"%(rules.current_player+1)
	elif rules.is_break:
		state_label.text="玩家 %d · 开球"%(rules.current_player+1)
	else:
		state_label.text="玩家 %d · 轮到你击球"%(rules.current_player+1)
	status_label.text=rules.message
