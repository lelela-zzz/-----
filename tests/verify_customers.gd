extends Node
## 顾客系统验收：数据 → 生成 → 走位 → 排队 → 卖酒 → 偏好接口 → 离场。
##   "<godot.exe>" res://tests/verify_customers.tscn      （headless 也可以）

const ENTRY_SCENE := "res://scenes/world.tscn"

var scene: Node2D
var player: Player
var spawner: CustomerSpawner
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	# 自动刷新关掉，本用例自己决定什么时候、来哪一位
	CustomerSpawner.force_disable = true
	StoryDirector.force_disable = true
	scene = (load(ENTRY_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	player = scene.get_node("Sorted/Player") as Player
	spawner = scene.get_node_or_null("Customers") as CustomerSpawner

	_check_data()
	await _check_walk_and_queue()
	await _check_barkeep_no_steal()
	await _check_trade()
	await _check_preference()
	await _check_leave()
	await _check_same_day_rule()
	_check_capacity()
	_check_seat_side_sit()
	_check_no_placeholder_sit()

	print("[customers] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---- 1. 数据 -------------------------------------------------------------

func _check_data() -> void:
	var want: Array[String] = ["explorer_lucy", "miner_simon",
			"dwarf_war_edward", "market_catherine"]
	var got: Array[String] = spawner.roster() if spawner != null else ([] as Array[String])
	var missing: Array[String] = []
	for id: String in want:
		if not got.has(id):
			missing.append(id)
	_report("初期顾客 = 雪山线 3 人 + 凯瑟琳，且数据无错误",
			spawner != null and got.size() == 4 and missing.is_empty()
					and spawner.errors.is_empty(),
			"roster=%s / 缺=%s / errors=%s" % [got, missing,
			spawner.errors if spawner != null else "no spawner"])

	# spawner 只收带 customer 块的人：defs 恰好 4 条，路人（如绯村）不在里面
	_report("只有这四位进顾客池，其余角色不受影响",
			spawner.defs().size() == 4 and not spawner.defs().has("ronin_himura"),
			"顾客池 %d 条 / 含绯村=%s" % [spawner.defs().size(),
			spawner.defs().has("ronin_himura")])

	# 路线每个拐点都不在实体碰撞里（锅/柜台/长桌）
	var bad: String = ""
	for p: Vector2 in spawner.path_for(0):
		if _blocked_at(p):
			bad += "%s " % p
	_report("进店折线的每个拐点都在空地上", bad == "", "撞进碰撞的点：[%s]" % bad)


func _blocked_at(p: Vector2) -> bool:
	var q: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = 1
	q.collide_with_areas = false
	var hits: Array[Dictionary] = player.get_world_2d().direct_space_state.intersect_point(q, 8)
	for h: Dictionary in hits:
		var c: Object = h.get("collider")
		if c is StaticBody2D and not (c is TileMap):
			return true
	return false


# ---- 2. 走位与排队 -------------------------------------------------------

func _check_walk_and_queue() -> void:
	var cust: Customer = spawner.spawn("explorer_lucy")
	if cust == null:
		_report("顾客能从门口生成并走到吧台前排队", false, "spawn 返回 null")
		return
	cust.customer_speed = 400.0
	var start: Vector2 = cust.global_position
	_report("顾客从酒馆内门口出现",
			start.distance_to(CustomerSpawner.ENTRY) < 1.0 and cust.state == Customer.State.WALKING,
			"起点 %s / 状态 %d（0=WALKING）" % [start, cust.state])

	var ok: bool = false
	for i in 600:
		await get_tree().physics_frame
		if is_instance_valid(cust) and cust.state == Customer.State.QUEUED:
			ok = true
			break
	var slot: Vector2 = spawner.path_for(0)[5]
	_report("走到吧台前的队列槽位并停下",
			ok and cust.global_position.distance_to(slot) < 2.0,
			"停在 %s（槽位 %s）/ 状态 %d（1=QUEUED）"
					% [cust.global_position if is_instance_valid(cust) else "?", slot,
					cust.state if is_instance_valid(cust) else -1])

	var anim: CharacterAnimator = cust.get_node("Anim") as CharacterAnimator
	_report("排队时面向吧台（朝上待机）",
			anim.animation == &"walk_up" and not anim.is_playing(),
			"anim=%s playing=%s" % [anim.animation, anim.is_playing()])


# ---- 2b. 老板娘站位不抢顾客的 E -----------------------------------------

## 老板娘从左上角挪到左吧台后端 (76,100) 之后，玩家沿吧台往左走时，
## 总有一瞬站在"她比顾客更近"的地方。用的是"最近的人抢 E"，
## 所以这里必须有让位规则：排队的顾客优先。
func _check_barkeep_no_steal() -> void:
	var cust: Customer = _first_customer()
	if cust == null:
		_report("老板娘站位不抢顾客的 E", false, "场上没有顾客")
		return
	var npc: Npc = _place_barkeep(Vector2(76, 100))
	if npc == null:
		_report("老板娘站位不抢顾客的 E", false, "萃歌实例化失败")
		return

	var cust_prompt: Label = _prompt_of(cust)
	var npc_prompt: Label = _prompt_of(npc)

	# 危险位：站到 1 号槽顾客的左手边 —— 这里老板娘其实比顾客更近
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(95, 110)
	await _settle(8)
	var dc: float = player.global_position.distance_to(cust.global_position)
	var dn: float = player.global_position.distance_to(npc.global_position)
	_report("站在顾客与老板娘中间时，E 仍归顾客（顾客距离更远）",
			dc > dn and cust_prompt != null and npc_prompt != null
					and cust_prompt.visible and not npc_prompt.visible,
			"顾客距=%.1f 老板娘距=%.1f / 顾客提示=%s 老板娘提示=%s"
					% [dc, dn, cust_prompt != null and cust_prompt.visible,
					npc_prompt != null and npc_prompt.visible])

	# 走到老板娘身边：她照常能搭话
	player.global_position = Vector2(80, 106)
	await _settle(8)
	_report("走到老板娘身边时她照常出 [E] 交谈",
			npc_prompt != null and npc_prompt.visible
					and cust_prompt != null and not cust_prompt.visible,
			"顾客提示=%s 老板娘提示=%s / 文案=%s"
					% [cust_prompt != null and cust_prompt.visible,
					npc_prompt != null and npc_prompt.visible,
					npc_prompt.text if npc_prompt != null else "<无>"])

	npc.queue_free()
	await _settle(2)


## 按 npcs.json 里的定义把老板娘摆到一个指定坐标（不动 spawner 的总开关）。
func _place_barkeep(at: Vector2) -> Npc:
	var ps: PackedScene = load("res://scenes/npc.tscn") as PackedScene
	if ps == null:
		return null
	var def: Dictionary = {}
	var f: FileAccess = FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if f == null:
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		for d: Variant in ((data as Dictionary).get("npcs", []) as Array):
			if str((d as Dictionary).get("id", "")) == "tavern_cuige":
				def = d as Dictionary
				break
	if def.is_empty():
		return null
	var npc: Npc = ps.instantiate() as Npc
	npc.name = "Npc_tavern_cuige_probe"
	npc.configure(def, {"scene": "world", "pos": [at.x, at.y],
			"facing": "down", "wander": 0.0})
	scene.get_node("Sorted").add_child(npc)
	return npc


## 提示牌是脚本动态 add_child 的 Label 子节点。
func _prompt_of(n: Node) -> Label:
	for child: Node in n.get_children():
		if child is Label:
			return child as Label
	return null


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


# ---- 3. 卖酒 -------------------------------------------------------------

func _check_trade() -> void:
	var cust: Customer = _first_customer()
	if cust == null:
		_report("卖酒流程", false, "场上没有顾客")
		return

	Inventory.clear()
	Inventory.add("wine_warm_ginger", 2)
	var copper0: int = Inventory.copper

	# 站到他跟前
	player.velocity = Vector2.ZERO
	player.global_position = cust.global_position + Vector2(0, 30)
	for i in 8:
		await get_tree().physics_frame

	var prompt: Label = null
	for child: Node in cust.get_children():
		if child is Label:
			prompt = child as Label
	_report("走近出现 [E] 卖酒 提示",
			prompt != null and prompt.visible and prompt.text == "[E] 卖酒",
			"prompt=%s visible=%s" % [prompt.text if prompt else "<无>",
			prompt.visible if prompt else false])

	_push_action("interact")
	for i in 5:
		await get_tree().process_frame

	var panel: SellPanel = _sell_panel()
	_report("按 E 打开卖酒面板并冻结玩家",
			panel != null and player.is_frozen(),
			"panel=%s / frozen=%s" % [panel != null, player.is_frozen()])
	_report("面板只列出手上的酒（原料不出现）",
			panel != null and panel._items.size() == 1 and panel._items[0] == "wine_warm_ginger",
			"列表 = %s" % [panel._items if panel != null else []])

	_push_key(KEY_E)
	for i in 4:
		await get_tree().process_frame
	_report("卖 1 瓶：库存 -1、铜币 +原价、顾客记账",
			Inventory.count("wine_warm_ginger") == 1
					and Inventory.copper == copper0 + ItemDB.price("wine_warm_ginger")
					and cust.sold_count() == 1,
			"库存 %d / 铜 %d→%d / 已购 %d"
					% [Inventory.count("wine_warm_ginger"), copper0, Inventory.copper,
					cust.sold_count()])


# ---- 4. 偏好预留接口 -----------------------------------------------------

func _check_preference() -> void:
	var cust: Customer = _first_customer()
	if cust == null:
		_report("偏好接口", false, "场上没有顾客")
		return
	var base: int = ItemDB.price("wine_warm_ginger")

	# 默认：没填偏好 = 全部原价
	var default_ok: bool = is_equal_approx(cust.pref_multiplier("wine_warm_ginger"), 1.0) \
			and cust.price_for("wine_warm_ginger") == base \
			and cust.reaction_for("wine_warm_ginger") == "neutral"

	# 填上偏好：60% 加价 → 价格与好感档位都要跟着变
	cust.wine_pref = {"wine_warm_ginger": 1.6}
	var priced: int = cust.price_for("wine_warm_ginger")
	var loved: String = cust.reaction_for("wine_warm_ginger")
	var loved_ok: bool = priced == int(round(float(base) * 1.6)) and loved == "love"

	# 压价 + 不收非酒
	cust.wine_pref = {"wine_warm_ginger": 0.5}
	var cheap_ok: bool = cust.price_for("wine_warm_ginger") < base \
			and cust.reaction_for("wine_warm_ginger") == "dislike"
	var refuses: bool = not cust.accepts("ginger") and cust.accepts("wine_warm_ginger")

	cust.wine_pref = {}
	_report("偏好接口：空=原价 / 加价 / 压价 / 只收酒 四条都通",
			default_ok and loved_ok and cheap_ok and refuses,
			"原价 %d / 1.6x → %d(%s) / 0.5x →%s / 拒原料=%s"
					% [base, priced, loved, cheap_ok, refuses])


# ---- 5. 离场 -------------------------------------------------------------

func _check_leave() -> void:
	var cust: Customer = _first_customer()
	if cust == null:
		_report("卖完落座再离场", false, "场上没有顾客")
		return
	cust.drink_duration = 0.6   # 验收用：极短停留，加速流程
	var free_before: int = spawner.free_slots()
	_push_key(KEY_ESCAPE)   # 关面板：这一单成交，他该去落座了
	for i in 6:
		await get_tree().process_frame
	# 应当先去座位（SITTING），而不是立刻往回走
	var reached_seat: bool = false
	for i in 400:
		await get_tree().physics_frame
		if is_instance_valid(cust) and cust.state == Customer.State.SITTING and cust._seated:
			reached_seat = true
			break
	var anim_node: Node = cust.get_node_or_null("Anim") if is_instance_valid(cust) else null
	var anim_name: String = anim_node.animation if anim_node != null else ""
	_report("卖完酒后去凳子坐下（SITTING）",
		reached_seat and is_instance_valid(cust) and cust.state == Customer.State.SITTING
				and SeatRegistry.occupied_count() >= 1 and anim_name == "sit",
		"状态 %d / 落座=%s / 占座=%d / 动画=%s"
				% [cust.state if is_instance_valid(cust) else -1,
				cust._seated if is_instance_valid(cust) else false,
				SeatRegistry.occupied_count(), anim_name])

	# 坐够 → 离场 → 释放槽位 + 释放座位
	var gone: bool = false
	for i in 400:
		await get_tree().physics_frame
		if not is_instance_valid(cust):
			gone = true
			break
	_report("坐够后离场、槽位回收、座位释放",
			gone and spawner.active_count() == 0
					and spawner.free_slots() == free_before + 1
					and SeatRegistry.occupied_count() == 0,
			"已释放=%s / 在场 %d / 空槽 %d / 占座 %d"
					% [gone, spawner.active_count(), spawner.free_slots(),
					SeatRegistry.occupied_count()])


# ---- 5.4 坐姿方向按椅子侧别 ---------------------------------------------
# 左椅(x=137) → 朝右坐(col2)；右椅(x=272) → 朝左坐(col1)；只取侧面帧，绝不落到
# 坐姿行第 0/3 格（make_sit_row 的正/背占位稿）。这里直接读 seats.json 逐张座位核对
# Customer._sit_dir_for 的判定（纯函数，不需要把顾客放进场景，避免干扰其它用例）。
func _check_seat_side_sit() -> void:
	var f: FileAccess = FileAccess.open("res://data/seats.json", FileAccess.READ)
	if f == null:
		_report("坐姿方向按椅子侧别（左椅→朝右/右椅→朝左，只用侧面帧）", false, "打不开 seats.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		_report("坐姿方向按椅子侧别（左椅→朝右/右椅→朝左，只用侧面帧）", false, "seats.json 非数组")
		return
	var seats: Array = parsed as Array
	var cust: Customer = (load("res://scenes/customer.tscn") as PackedScene).instantiate() as Customer
	var bad: String = ""
	for s: Variant in seats:
		var seat: Dictionary = s as Dictionary
		var x: float = float(seat.get("x", 0.0))
		var side: String = str(seat.get("side", ""))
		var expect_left: bool = x < Customer.SEAT_MID_X
		var want: Vector2i = Vector2i.RIGHT if expect_left else Vector2i.LEFT
		var dir: Vector2i = cust._sit_dir_for(seat)
		var col: int = 1 if dir.x < 0 else 2
		var side_ok: bool = (side == "left") == expect_left
		if dir != want or dir.y != 0 or (col != 1 and col != 2) or not side_ok:
			bad += "%s(x=%.0f side=%s dir=%s want=%s col=%d) " % [
					str(seat.get("id", "")), x, side, dir, want, col]
	cust.free()
	_report("坐姿方向按椅子侧别（左椅→朝右/右椅→朝左，只用侧面帧 col1/col2）",
			bad == "", bad)


# ---- 5.4b 坐姿行不许再有占位矩形 -------------------------------------------
# 当初"先占位后面再补"留下的正/背两格里有一整块带描边的实心浅色矩形（约 52x22）
# 加两条方块腿。正式侧面美术到位后这两格已被真侧面覆盖（col0<-col2、col3<-col1）。
# 这里守两道门：① 正/背两格必须和对应的侧面格逐像素相同（占位稿不可能再回来）；
# ② 任何一格都不许出现"长直边的实心浅色块"（矩形形态学特征）。
const SIT_ROW_Y: int = 480
const CELL_W: int = 60
const CELL_H: int = 120
const PALE_MAX_RUN: int = 28      # 真侧面美术最长的一排浅色像素 24px，留 4px 余量


func _check_no_placeholder_sit() -> void:
	var sheets: Array[String] = []
	for k: Variant in spawner.defs().keys():
		var d: Dictionary = spawner.defs()[k] as Dictionary
		var sheet: String = str(d.get("sheet", ""))
		if sheet != "" and not sheets.has(sheet):
			sheets.append(sheet)
	var bad: String = ""
	for path: String in sheets:
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			bad += "%s 读不到图集 " % path
			continue
		var img: Image = tex.get_image()
		if img == null or img.get_height() < SIT_ROW_Y + CELL_H:
			continue    # 没有坐姿行的角色不管
		var c0: Array = _cell_pixels(img, 0)
		var c1: Array = _cell_pixels(img, 1)
		var c2: Array = _cell_pixels(img, 2)
		var c3: Array = _cell_pixels(img, 3)
		if not c0 == c2:
			bad += "%s 坐姿 col0 仍是独立占位稿%s " % [
					path.get_file(), _first_diff(c0, c2)]
		if not c3 == c1:
			bad += "%s 坐姿 col3 仍是独立占位稿%s " % [
					path.get_file(), _first_diff(c3, c1)]
		for col: int in range(4):
			var run: int = _longest_pale_run(_cell_pixels(img, col))
			if run > PALE_MAX_RUN:
				bad += "%s 坐姿 col%d 有 %dpx 长直边浅色块（疑似矩形） " % [
						path.get_file(), col, run]
	_report("坐姿行四格全为真侧面，无占位矩形（正/背两格已由侧面覆盖）",
			bad == "", bad)


func _first_diff(a: Array, b: Array) -> String:
	var n: int = 0
	var first: String = ""
	for i: int in range(mini(a.size(), b.size())):
		var ca: Color = a[i] as Color
		var cb: Color = b[i] as Color
		if ca != cb:
			n += 1
			if first == "":
				first = "首个不同(x=%d,y=%d):%s≠%s" % [
						i % CELL_W, i / CELL_W, str(ca), str(cb)]
	return "(差异 %d 像素 %s)" % [n, first]


func _cell_pixels(img: Image, col: int) -> Array:
	var out: Array = []
	out.resize(CELL_W * CELL_H)
	for y: int in range(CELL_H):
		for x: int in range(CELL_W):
			var c: Color = img.get_pixel(col * CELL_W + x, SIT_ROW_Y + y)
			# 导入器的 fix_alpha_border 会给全透明像素"抹"上邻色，RGB 不参与比较，
			# 否则同一张图复制到不同横向位置就会因为边缘邻居不同而误判。
			out[y * CELL_W + x] = (Color(0, 0, 0, 0) if c.a <= 0.0 else c)
	return out


## 坐姿格里"低饱和浅色"像素的最长横向连续段长度。
func _longest_pale_run(cell: Array) -> int:
	var best: int = 0
	for y: int in range(CELL_H):
		var run: int = 0
		for x: int in range(CELL_W):
			var c: Color = cell[y * CELL_W + x] as Color
			if c.a < 0.16:
				run = 0
				continue
			var mx: float = maxf(c.r, maxf(c.g, c.b))
			var mn: float = minf(c.r, minf(c.g, c.b))
			var sat: float = 0.0 if mx <= 0.0 else (mx - mn) / mx
			if sat < 0.30 and mx > 0.39 and mx < 0.96:
				run += 1
				best = maxi(best, run)
			else:
				run = 0
	return best


# ---- 5.5 当天不回头 -------------------------------------------------------

func _check_same_day_rule() -> void:
	# 此时 explorer_lucy 已买过酒并离场（见 _check_leave），其余三人没买过。
	# 先冻结时钟，让"天"完全由本用例掌控，不受走时影响。
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	if clock != null:
		clock.running = false
	var day0: int = clock.day if clock != null else 1

	# 反复随机放人：今天买过的 lucy 绝不该再被选中；
	# 候选人只剩没买过的 3 人，放满 3 位后第 4 次必须返回 null（是规则拦的，不是容量）。
	var picked: Array[String] = []
	for i in 4:
		var c: Customer = spawner.spawn_random()
		if c != null:
			picked.append(c.npc_id)
	var fourth: Customer = spawner.spawn_random()   # 再随机一次，应仍被规则拦
	_report("买过酒的人今天不再被随机放进来",
			picked.size() == 3 and not picked.has("explorer_lucy") and fourth == null,
			"今天被选中的=%s / 再随机=%s"
					% [picked, "null(被规则拦)" if fourth == null else fourth.npc_id])

	# 跨到下一天：lucy 恢复资格，应当能再次被放进来（此时另外 3 人仍在场）。
	# 店里上限只有 3 位、这会儿正好满员，临时放宽一格借个位置 ——
	# 本条验的是"过夜规则"，不是容量（容量见 _check_capacity）。
	if clock != null:
		clock.day = day0 + 1
	var cap0: int = spawner.max_customers
	spawner.max_customers = cap0 + 1
	var re: Customer = spawner.spawn_random()
	spawner.max_customers = cap0
	_report("过夜后（day 改变）买过酒的人恢复资格",
			re != null and re.npc_id == "explorer_lucy",
			"跨天后随机到=%s" % (re.npc_id if re != null else "<null>"))

	# 清场，把舞台交还给后面的 _check_capacity。
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var c: Customer = n as Customer
		if c != null and is_instance_valid(c):
			c.queue_free()
	for i in 30:
		await get_tree().physics_frame


# ---- 6. 上限 3 位 ---------------------------------------------------------

func _check_capacity() -> void:
	_report("顾客上限 = 3（4 位并排会在吧台前连成一道人墙）",
			spawner.max_customers == 3,
			"max_customers=%d" % spawner.max_customers)

	var xs: Array[float] = []
	var roster: Array[String] = spawner.roster()
	for i: int in mini(3, roster.size()):
		var c: Customer = spawner.spawn(roster[i])
		if c != null and not c._path.is_empty():
			xs.append(c._path[-1].x)
	_report("三位顾客能同时在场（一人一个槽位）",
			xs.size() == 3 and spawner.active_count() == 3,
			"在场 %d / 目标 x=%s" % [spawner.active_count(), xs])

	var spread: bool = true
	for i in xs.size():
		for j in xs.size():
			if i != j and absf(xs[i] - xs[j]) < 30.0:
				spread = false
	_report("排队不叠人（槽位间距 ≥ 角色宽 30px）", spread, "x=%s" % [xs])

	var extra: Customer = spawner.spawn_random()
	_report("满员后不再放人进来", extra == null and spawner.active_count() == 3,
			"spawn_random=%s / 在场 %d" % ["拒绝" if extra == null else extra.npc_id,
			spawner.active_count()])


# ---- 工具 ---------------------------------------------------------------

func _first_customer() -> Customer:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var c: Customer = n as Customer
		if c != null and is_instance_valid(c):
			return c
	return null


func _sell_panel() -> SellPanel:
	# 面板挂在 HUD/UIRoot（640×384 + 2× 缩放）里，不再直接挂 CanvasLayer。
	for container: String in ["HUD/UIRoot", "HUD"]:
		var box: Node = scene.get_node_or_null(container)
		if box == null:
			continue
		for child: Node in box.get_children():
			if child is SellPanel:
				return child as SellPanel
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
