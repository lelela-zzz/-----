extends Node
## 无窗口验收：四方向行走角色已接入主场景。
## 校验：world 里 Player/Body 是 CharacterAnimator、图集切成 4 动画×4 帧、
## 朝向→动画映射、待机定格。不依赖 frame_post_draw，headless 可跑。

const CASES: Array = [
	[Vector2i(0, 1), "walk_down"],
	[Vector2i(-1, 0), "walk_left"],
	[Vector2i(1, 0), "walk_right"],
	[Vector2i(0, -1), "walk_up"],
]


func _ready() -> void:
	var world: Node = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	for i in 8:
		await get_tree().process_frame

	var player: Node = world.get_node_or_null("Sorted/Player")
	var anim: AnimatedSprite2D = player.get_node_or_null("Body") as AnimatedSprite2D if player != null else null

	var exists: bool = anim != null and anim.sprite_frames != null
	var is_animator: bool = anim != null and anim.has_method("update_anim")
	print("[char] player:", player != null, " | Body 是动画角色:", exists, " | 有 update_anim:", is_animator)

	if not exists:
		print("[char] 总判定: FAIL")
		get_tree().quit()
		return

	var sf: SpriteFrames = anim.sprite_frames
	print("[char] 动画列表:", sf.get_animation_names())

	var counts_ok: bool = true
	for pair: Array in CASES:
		var cnt: int = sf.get_frame_count(pair[1])
		if cnt != 4:
			counts_ok = false
		print("   %s 帧数=%d" % [pair[1], cnt])

	var map_ok: bool = true
	for pair: Array in CASES:
		anim.update_anim(pair[0], true)
		if String(anim.animation) != pair[1]:
			map_ok = false
			print("   方向 %s → %s（期望 %s）" % [pair[0], anim.animation, pair[1]])

	anim.update_anim(Vector2i(0, 1), false)
	var idle_ok: bool = not anim.is_playing() and anim.frame == 0
	print("[char] 待机定格(暂停+帧0):", idle_ok)

	var all_ok: bool = exists and is_animator and counts_ok and map_ok and idle_ok
	print("[char] 总判定:", "PASS" if all_ok else "FAIL")
	get_tree().quit()
