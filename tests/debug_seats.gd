extends Node
## 一次性排查：把 4 个顾客分别放到 4 张座位上 _arrive_seat，打印实际用的坐姿帧。
## 用于确认「左椅→col2 右椅→col1」是否真的落到正确帧，而不是 col0/3 占位稿。

const ENTRY := "res://scenes/world.tscn"


func _ready() -> void:
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	var scene: Node2D = (load(ENTRY) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var spawner: CustomerSpawner = scene.get_node("Customers") as CustomerSpawner

	var f: FileAccess = FileAccess.open("res://data/seats.json", FileAccess.READ)
	var seats: Array = JSON.parse_string(f.get_as_text())
	var ids: Array[String] = ["explorer_lucy", "miner_simon",
			"dwarf_war_edward", "market_catherine"]

	for i in 4:
		var c: Customer = spawner.spawn(ids[i])
		if c == null:
			print("[SEAT] spawn 失败 ", ids[i])
			continue
		await get_tree().process_frame
		var seat: Dictionary = seats[i] as Dictionary
		c._seat = seat
		c.state = Customer.State.SITTING
		c._seated = false
		c._arrive_seat()
		var anim: CharacterAnimator = c.get_node("Anim") as CharacterAnimator
		var sit_n: int = anim.sprite_frames.get_frame_count(&"sit") if anim.sprite_frames != null else -1
		var col: int = -1
		if anim != null and anim.sprite_frames != null \
				and anim.sprite_frames.has_animation(anim.animation):
			var at: AtlasTexture = anim.sprite_frames.get_frame_texture(
					anim.animation, anim.frame) as AtlasTexture
			if at != null:
				col = int(at.region.position.x / 60.0)
		print("[SEAT] %s seat=%s side=%s dir=%s cols=%d rows=%d sit_frames=%d -> anim=%s frame=%d ATLAS_COL=%d"
				% [ids[i], str(seat.get("id", "")), str(seat.get("side", "")),
				str(c._dir), anim.columns, anim.rows, sit_n,
				anim.animation, anim.frame, col])

	await get_tree().process_frame
	get_tree().quit()
