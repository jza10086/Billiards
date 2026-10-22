extends SceneTree
var app
var output := ""
func _initialize(): call_deferred("run")
func snap(label: String):
	await create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	var img = root.get_texture().get_image()
	print("CAPTURE ", label, " ", img.get_size(), " result=",img.save_png(output.path_join(label+".png")))
func run():
	output=OS.get_environment("CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.quiet_mode=true
	await snap("01-table-aiming")
	app.toggle_camera()
	await snap("02-overhead")
	app.toggle_camera()
	root.size=Vector2i(960,640)
	await snap("03-small-aiming")
	root.min_size=Vector2i(0,0)
	root.size=Vector2i(720,450)
	await create_timer(.3).timeout
	var images=[]
	var stamps=[]
	var first=root.get_texture().get_image()
	images.append(first)
	stamps.append({"frame":0,"ms":0})
	await create_timer(.7).timeout
	var start=Time.get_ticks_msec()-700
	print("SHOT_ACCEPTED ",app.play_shot(Vector2(0,-1),.95))
	while Time.get_ticks_msec()-start<4200:
		await RenderingServer.frame_post_draw
		images.append(root.get_texture().get_image())
		stamps.append({"frame":images.size()-1,"ms":Time.get_ticks_msec()-start})
		await create_timer(.066).timeout
	var frames=output.path_join("shot-frames")
	DirAccess.make_dir_recursive_absolute(frames)
	for i in images.size(): images[i].save_png(frames.path_join("frame-%04d.png"%i))
	FileAccess.open(frames.path_join("timing.json"),FileAccess.WRITE).store_string(JSON.stringify(stamps))
	print("MOTION frames=",images.size()," size=",images[0].get_size())
	root.size=Vector2i(1280,800)
	await snap("04-after-break")
	var timeout=Time.get_ticks_msec()+20000
	while app.shot_active and Time.get_ticks_msec()<timeout: await process_frame
	await snap("05-settled")
	app.new_game()
	app.rules.ball_in_hand=true
	app.placement=Vector2(0,.65)
	app.placement_valid=app.simulation.can_place_cue(app.placement)
	app._refresh_ui()
	await snap("06-ball-in-hand")
	app.queue_free()
	await process_frame
	print("CAPTURE_DONE")
	quit()
