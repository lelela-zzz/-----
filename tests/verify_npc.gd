extends Node
## NPC 系统验收：数据 → 生成 → 动画 → 脚底对齐 → 碰撞 → 对话 → 昼夜同步。
##   "<godot.exe>" res://tests/verify_npc.tscn   （--headless 也可以，本测试不截图）
##
## 判定看打印出来的 [check] 行；末尾 [npc] 行是总账。

const ENTRY_SCENE := "res://scenes/world.tscn"

var scene: Node2D
var player: Player
var spawner: NpcSpawner
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	# 顾客会站到吧台前、也会抢「最近的人」，这里只验 NPC 本体，先关掉顾客层。
	# 序章导演同理：他会往酒馆里摆萃歌、弹序言卡，同样会搅乱采样。
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	scene = (load(ENTRY_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	player = scene.get_node("Sorted/Player") as Player
	spawner = scene.get_node_or_null("NPCs") as NpcSpawner

	_check_data()
	await _check_spawn()
	_check_each_npc()
	_check_ambient()
	await _check_collision()
	await _check_dialogue()
	_check_atlas_grid_fit()
	_check_scene_lines()

	print("[npc] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 1. 数据 -------------------------------------------------------------

func _check_data() -> void:
	var ok: bool = spawner != null and spawner.total_defs() == 21 and spawner.errors.is_empty()
	_report("data/npcs.json 载入 21 个角色且无错误", ok,
			"defs=%d / errors=%s" % [spawner.total_defs() if spawner else -1,
			spawner.errors if spawner else "no spawner"])

	var bad_sheet: String = ""
	var bad_size: String = ""
	for id: String in spawner.defs():
		var d: Dictionary = spawner.defs()[id] as Dictionary
		var tex: Texture2D = load(str(d["sheet"])) as Texture2D
		if tex == null:
			bad_sheet += id + " "
			continue
		# 顾客图集多了第 5 行坐姿帧（240x600），其余都是 240x480（4x4）。
		var is_customer: bool = d.has("customer")
		var expect_h: int = 600 if is_customer else 480
		if tex.get_width() != 240 or tex.get_height() != expect_h:
			bad_size += "%s(%dx%d) " % [id, tex.get_width(), tex.get_height()]
	_report("20 张图集可加载且尺寸正确（顾客 240x600=5 行含坐姿，其余 240x480=4 行）",
			bad_sheet == "" and bad_size == "",
			"缺图集 [%s] / 尺寸异常 [%s]" % [bad_sheet, bad_size])


# ---- 2. 生成 -------------------------------------------------------------

func _check_spawn() -> void:
	await get_tree().process_frame
	# 当前产品状态：酒馆里先不站人（world.tscn 里 NPCs.enabled = false）。
	# 数据、坐标、台词都留着，开关一开就回来 —— 所以这里先验"确实没人"。
	_report("默认不出场（enabled=false → 场景里 0 个 NPC）",
			get_tree().get_nodes_in_group("npc").is_empty() and not spawner.enabled,
			"npc=%d / enabled=%s" % [get_tree().get_nodes_in_group("npc").size(),
			spawner.enabled])

	# 后面几项要真人站场上才能测，这里手动打开再生成一次（spawn 自带防重入）。
	spawner.enabled = true
	spawner.spawn()
	await get_tree().process_frame
	# 转头看人发生在**物理帧**（Npc._physics_process → _face_player）。这里只等
	# process 帧的话，下面的朝向断言可能抢在第一次物理帧之前采样，偶发读到
	# 数据朝向（2026-10-30 偶发"walk_down≠walk_left"）。补 3 个物理帧钉死时序。
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var npcs: Array[Node] = get_tree().get_nodes_in_group("npc")
	# 人数由 npcs.json 决定（现在酒馆 7 位），别再硬编码 6 —— 一加人就假失败。
	_report("打开开关后按数据摆出全部 NPC 且都在 Sorted（y_sort）容器里",
			npcs.size() == spawner.expected_count() and npcs.size() > 0
					and npcs[0].get_parent().name == "Sorted",
			"实例 %d 个 / 期望 %d 个 / 父节点 %s"
					% [npcs.size(), spawner.expected_count(),
					npcs[0].get_parent().name if npcs.size() > 0 else "-"])


func _check_each_npc() -> void:
	var bad_anim: String = ""
	var bad_foot: String = ""
	var bad_mask: String = ""
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var npc: Npc = n as Npc
		var anim: CharacterAnimator = npc.get_node_or_null("Anim") as CharacterAnimator
		if anim == null or anim.sprite_frames == null:
			bad_anim += npc.npc_id + " "
			continue
		var frames: int = anim.sprite_frames.get_frame_count(&"walk_down")
		var anims: int = anim.sprite_frames.get_animation_names().size()
		# 4 动画 = 纯行走图集；5 动画 = 行走 + 坐姿行（顾客用）。两种都算正确。
		if frames != 4 or (anims != 4 and anims != 5):
			bad_anim += "%s(%d动画/%d帧) " % [npc.npc_id, anims, frames]
		# 脚底对齐：视觉原点应 = -foot*scale，四舍五入到 0.5 内
		var want: Vector2 = -npc.foot_in_cell * npc.sprite_scale
		if anim.position.distance_to(want) > 0.51:
			bad_foot += "%s(%.1f,%.1f≠%.1f,%.1f) " % [npc.npc_id,
					anim.position.x, anim.position.y, want.x, want.y]
		if anim.light_mask != 2:
			bad_mask += npc.npc_id + " "
	_report("每个 NPC：4 方向 x 4 帧 / 脚底对齐原点 / light_mask=2",
			bad_anim == "" and bad_foot == "" and bad_mask == "",
			"动画[%s] 对齐[%s] 光罩[%s]" % [bad_anim, bad_foot, bad_mask])

	# 朝向两条：
	#  1) 玩家不在范围内的 NPC 应该停在数据给的方向上；
	#  2) 范围内的 NPC 应该已经转过头来看玩家。
	# 注意不能用"第一个 NPC"来验 1) —— 玩家出生点附近就有人，他早转头了。
	# 这里从"还没转头看玩家"的 NPC 里挑离玩家最远的那位（既保证在范围外、
	# 又不再硬编码某个角色 —— 凯瑟琳已不再站酒馆，挑她会落空）。
	var far: Npc = null
	var far_dist: float = -1.0
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var cand: Npc = n as Npc
		var a: CharacterAnimator = cand.get_node_or_null("Anim") as CharacterAnimator
		if a == null or a.animation != StringName("walk_" + cand.facing):
			continue  # 已转头 = 玩家在交互范围内，跳过
		var d: float = cand.global_position.distance_to(player.global_position)
		if d > far_dist:
			far_dist = d
			far = cand
	var far_anim: CharacterAnimator = far.get_node("Anim") as CharacterAnimator
	_report("初始朝向按数据生效（玩家不在范围内）",
			far != null and far_anim != null
					and far_anim.animation == StringName("walk_" + far.facing),
			"%s facing=%s anim=%s" % [far.npc_id if far != null else "-",
			far.facing if far != null else "-",
			far_anim.animation if far_anim != null else "-"])

	var near: Npc = _npc_by_id("knight_ringe")
	var near_anim: CharacterAnimator = near.get_node("Anim") as CharacterAnimator
	var want: String = "walk_" + _dir_name(near.global_position, player.global_position)
	_report("玩家靠近时 NPC 转头看人", near_anim.animation == StringName(want),
			"%s anim=%s 期望=%s（玩家在%s）" % [near.npc_id, near_anim.animation, want,
			_dir_name(near.global_position, player.global_position)])


# ---- 2b. 全角色切格一致性（含 5 行坐姿图集）-------------------------------
# 凯瑟琳在集市站桩时曾因 npc.tscn 的 Anim 默认 rows=4、而她的图集是 240x600（5 行）而
# 错位：单格被切成 600/4=150px，脚下多出下一行的头顶。这里对「全部 21 个角色」逐一
# 实例化，断言每帧区域尺寸 == 声明的 cell、动画数 == 图集高/格高 —— 排除同类隐患。
func _check_atlas_grid_fit() -> void:
	var holder: Node2D = Node2D.new()
	add_child(holder)
	var npc_scene: PackedScene = load("res://scenes/npc.tscn") as PackedScene
	var bad: String = ""
	for id: String in spawner.defs():
		var d: Dictionary = spawner.defs()[id] as Dictionary
		var cell: Array = d.get("cell", [60, 120])
		var cw: int = int(cell[0])
		var ch: int = int(cell[1])
		var tex: Texture2D = load(str(d["sheet"])) as Texture2D
		var expect_rows: int = int(tex.get_height() / ch)
		var npc: Npc = npc_scene.instantiate() as Npc
		npc.configure(d, {"facing": "down", "wander": 0.0, "pos": [0, 0], "scene": "__test__"})
		holder.add_child(npc)
		var anim: CharacterAnimator = npc.get_node("Anim") as CharacterAnimator
		if anim == null or anim.sprite_frames == null:
			bad += id + "(无帧) "
		else:
			var anims: Array = anim.sprite_frames.get_animation_names()
			if anims.size() != expect_rows:
				bad += "%s(动画%d≠行%d) " % [id, anims.size(), expect_rows]
			else:
				for an in anims:
					var at: AtlasTexture = anim.sprite_frames.get_frame_texture(an, 0) as AtlasTexture
					if at == null or int(at.region.size.x) != cw or int(at.region.size.y) != ch:
						bad += "%s(%s 格%dx%d≠%dx%d) " % [id, str(an),
								int(at.region.size.x) if at != null else -1,
								int(at.region.size.y) if at != null else -1, cw, ch]
						break
		npc.queue_free()
	holder.queue_free()
	_report("全部 20 角色切格与声明一致（每帧=cell，行数=图集高/格高，含 5 行坐姿图集）",
			bad == "", bad)


# ---- 2c. 台词按出场位置区分 ----------------------------------------------
# 凯瑟琳在集市当摊主、在酒馆是顾客，两处必须是不同的话。以前两处共用 npcs.json 的
# 顶层 lines，站在集市里却说「集市收了摊我才得空进来」—— 等于把酒馆台词搬到了集市。
# 规则：placement 里写了 lines 就用它，没写才退回顶层 lines。
func _check_scene_lines() -> void:
	var npc_scene: PackedScene = load("res://scenes/npc.tscn") as PackedScene
	var bad: String = ""
	var checked: int = 0
	for id: String in spawner.defs():
		var d: Dictionary = spawner.defs()[id] as Dictionary
		var def_lines: Array = d.get("lines", []) as Array
		for p: Variant in (d.get("placement", []) as Array):
			var place: Dictionary = p as Dictionary
			var want: Array = place.get("lines", []) as Array
			if want.is_empty():
				want = def_lines
			var npc: Npc = npc_scene.instantiate() as Npc
			npc.configure(d, place)
			var got: Array = []
			for s: String in npc.lines:
				got.append(s)
			if got != want:
				bad += "%s@%s 台词没按位置生效 " % [id, str(place.get("scene", "?"))]
			checked += 1
			npc.free()

	# 凯瑟琳专项：集市与酒馆两套台词必须真的不同（否则等于没做区分）。
	var market: Array = []
	var tavern: Array = []
	for p: Variant in ((spawner.defs().get("market_catherine", {}) as Dictionary)
			.get("placement", []) as Array):
		var place: Dictionary = p as Dictionary
		var ls: Array = place.get("lines", []) as Array
		if ls.is_empty():
			ls = (spawner.defs().get("market_catherine", {}) as Dictionary).get("lines", []) as Array
		match str(place.get("scene", "")):
			"village":
				market = ls
			"world":
				tavern = ls
	if market.is_empty() or tavern.is_empty() or market == tavern:
		bad += "凯瑟琳集市台词与酒馆台词没区分开 "

	_report("台词按出场位置区分（凯瑟琳：集市摊主口吻 ≠ 酒馆顾客口吻）",
			bad == "" and checked > 0,
			"%d 个位置已核对 / 集市 %d 句、酒馆 %d 句 %s" % [
			checked, market.size(), tavern.size(), bad])


func _dir_name(from: Vector2, to: Vector2) -> String:
	var d: Vector2 = to - from
	if absf(d.x) >= absf(d.y):
		return "right" if d.x >= 0.0 else "left"
	return "down" if d.y >= 0.0 else "up"


# ---- 3. 昼夜同步 ---------------------------------------------------------

func _check_ambient() -> void:
	var lighting: LightingDirector = scene.get_node("Lighting") as LightingDirector
	var npc: Npc = get_tree().get_nodes_in_group("npc")[0] as Npc
	var anim: CharacterAnimator = npc.get_node("Anim") as CharacterAnimator

	lighting.follow_clock = false
	lighting.set_phase_instant(LightingDirector.PHASE_DAY)
	var day: Color = anim.modulate
	lighting.set_phase_instant(LightingDirector.PHASE_NIGHT)
	var night: Color = anim.modulate
	_report("NPC 跟昼夜环境色（夜 < 昼）",
			lighting.has_method("ambient_color") and night.get_luminance() < day.get_luminance() - 0.2,
			"昼 %s(%.2f) / 夜 %s(%.2f)" % [day, day.get_luminance(), night, night.get_luminance()])
	lighting.set_phase_instant(LightingDirector.PHASE_DAY)


# ---- 4. 碰撞 -------------------------------------------------------------

func _check_collision() -> void:
	var npc: Npc = _npc_by_id("knight_ringe")
	if npc == null:
		_report("NPC 阻挡玩家", false, "找不到 knight_ringe")
		return
	# 林格站在 (336,300)，脚底碰撞框 16x8（中心在原点上方 4px，即 y 296..304）。
	# 从他正上方往下顶：玩家脚框高 6，脚底应停在 296 - 6 = 290。
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(npc.global_position.x, npc.global_position.y - 70.0)
	await get_tree().physics_frame
	Input.action_press("move_down")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_down")
	await get_tree().physics_frame
	var stop_y: float = player.global_position.y
	_report("NPC 挡路（玩家被脚底碰撞框停住）",
			absf(stop_y - (npc.global_position.y - 10.0)) < 2.0,
			"停在 y=%.1f（NPC y=%.1f，期望 ≈%.1f）"
					% [stop_y, npc.global_position.y, npc.global_position.y - 10.0])


# ---- 5. 对话 -------------------------------------------------------------

func _check_dialogue() -> void:
	var npc: Npc = _npc_by_id("knight_ringe")
	player.velocity = Vector2.ZERO
	player.global_position = npc.global_position + Vector2(0, 26)
	for i in 8:
		await get_tree().physics_frame

	var prompt: Label = npc.get_node_or_null("Label") as Label
	if prompt == null:
		for child: Node in npc.get_children():
			if child is Label:
				prompt = child as Label
	_report("走近浮出 [E] 交谈 提示", prompt != null and prompt.visible,
			"prompt=%s" % (prompt.text if prompt != null else "<无>"))

	_push_action("interact")
	for i in 4:
		await get_tree().process_frame

	var box: Node = _dialogue_in_hud()
	_report("按 E 弹出对话框并冻结玩家",
			box != null and player.is_frozen(),
			"box=%s / frozen=%s" % [box.name if box != null else "<无>", player.is_frozen()])
	_report("对话框带正确的说话人与头像",
			box != null and str(box.get("speaker")) == npc.display_name
					and box.get("portrait") is AtlasTexture
					and (box.get("lines") as PackedStringArray).size() == npc.lines.size(),
			"speaker=%s / lines=%d / portrait=%s"
					% [box.get("speaker") if box != null else "-",
					(box.get("lines") as PackedStringArray).size() if box != null else -1,
					"AtlasTexture" if box != null and box.get("portrait") is AtlasTexture else "-"])

	# 连按 E 走完全部台词：每句最多两下（补全 + 翻页）。
	# 判"还在不在"要看 HUD 里有没有 UiPanel —— queue_free 是延迟的，
	# 用 is_instance_valid 判断会多按一下 E，把对话又开一遍。
	for i in 20:
		if _dialogue_in_hud() == null:
			break
		_push_key(KEY_E)
		await get_tree().process_frame
		await get_tree().process_frame

	for i in 4:
		await get_tree().process_frame

	_report("台词走完自动关框并解冻玩家",
			_dialogue_in_hud() == null and not player.is_frozen(),
			"残留对话框=%s / frozen=%s" % [_dialogue_in_hud() != null, player.is_frozen()])


# ---- 工具 ---------------------------------------------------------------

func _npc_by_id(id: String) -> Npc:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var npc: Npc = n as Npc
		if npc.npc_id == id:
			return npc
	return null


## HUD 层里现存的对话框（UiPanel 子类）。
## 面板挂在 HUD/UIRoot（640×384 + 2× 缩放）里 —— 直接挂 CanvasLayer 的话
## 640 坐标的老布局会缩在屏幕左上角，这正是"换分辨率就不适配"的坑。
func _dialogue_in_hud() -> Node:
	for container: String in ["HUD/UIRoot", "HUD"]:
		var host: Node = scene.get_node_or_null(container)
		if host == null:
			continue
		for child: Node in host.get_children():
			if child is UiPanel and is_instance_valid(child):
				return child
	return null


func _push_action(action: String) -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	get_viewport().push_input(ev)


func _push_key(keycode: Key) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	get_viewport().push_input(down)
	var up: InputEventKey = InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	get_viewport().push_input(up)


func _report(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[check] %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])
