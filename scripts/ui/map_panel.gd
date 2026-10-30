class_name MapPanel
extends UiPanel
## 地图面板：按 M 打开，选地点传送。
##
## 序章任务会把玩家支来支去（酒馆 ⇄ 集市），走路要穿过外观场景两趟，
## 有地图就一步到位 —— 这也是剧情文本里"点击 M 打开地图，选择卢迪克集市"
## 的实现。传送复用 DoorArea 的静态出生点机制：落点、游戏时间都和走门一致，
## 昼夜不会因为传送被重置回 8 点。

## 地点表：名字 + 场景 + 落点（脚底坐标）+ 可选解锁开关。
##
## 这是**精选的传送去处**，不等于地图图的全部节点（比如矿道入口/矿洞能走到，
## 但暂不开放直达）。以后解锁新去处往这里加一行即可。
##
## unlock = 需要的 SideStory 解锁开关；留空 = 一开始就可用。
## 没解锁的去处**根本不列出来** —— 光是把它列出来就等于告诉玩家"那儿能去"。
##
## 2026-10-28 已实现「快速前往」：选中去处 → 中央「跑路中」+ 一个钟从当前时刻
## 转到"消耗完之后"的时刻 → 真的推进 GameClock → 再切场景。
## 耗时 = 地图图里各跳 `minutes` 之和（data/map_graph.json，随手可调）；
## 同一张图 = 0 分钟，不播遮罩、直接瞬移。
const PLACES: Array[Dictionary] = [
	{"id": "world", "name": "银辉酒馆", "desc": "你和萃歌的家底",
			"scene": "res://scenes/world.tscn", "spawn": Vector2(319, 360)},
	{"id": "village", "name": "卢迪克集市", "desc": "凯瑟琳的摊位就在南边",
			"scene": "res://scenes/village.tscn", "spawn": Vector2(240, 788)},
	{"id": "tavern_exterior", "name": "酒馆门口", "desc": "月痕河镇的街上",
			"scene": "res://scenes/tavern_exterior.tscn", "spawn": Vector2(230, 363)},
	# 解锁开关 = snow_mountain；scene 留空表示"尚未开放"，
	# 真开放时把 scene 填成 res://scenes/snow_mountain.tscn 并给它加出口门。
	# （雪山本轮明确不做，这里只保留占位。）
	{"id": "snow_mountain", "name": "黑松山脉·雪山",
			"desc": "科考队驻扎的雪山营地",
			"scene": "res://scenes/snow_mountain.tscn",
			"spawn": Vector2(250, 475), "unlock": "snow_mountain"},
	# 第二章「月痕将熄」第 8 幕（ch2_to_spring）解锁泉水。
	{"id": "spring", "name": "黑松山脉·泉水",
			"desc": "魔物聚集的浑浊泉水",
			"scene": "res://scenes/spring.tscn",
			"spawn": Vector2(700, 620), "unlock": "spring"},
	# 第一章「雾凇无虞」第 8 幕（ch1_to_mine）解锁，之后可以直接跑路过去。
	# 落点取村庄北门 MineEntrancePath 的到达点（data/map_graph.json 的 village→mine_entrance）。
	{"id": "mine_entrance", "name": "黑松山脉·矿道入口",
			"desc": "科考队扎营的旧坑口",
			"scene": "res://scenes/mine_entrance.tscn",
			"spawn": Vector2(875, 40), "unlock": "mine_entrance"},
]

## 面板左上角与宽度；高度按"本次实际列出的去处条数"算 —— 3 项 192、5 项 272，
## 不会因为多解锁一个去处就把面板撑长、也不会给 3 项留一大块空白。
const FRAME_X: int = 150
const FRAME_Y: int = 76
const FRAME_W: int = 340
const ROW_TOP: int = 56
const ROW_H: int = 40

var _index: int = 0
var _rows: Array[Dictionary] = []
## 本次打开时的实际地点表 = 基础表 + 已解锁的支线去处。
var _places: Array[Dictionary] = []


func _build() -> void:
	var here: String = _current_scene_path()
	# 只保留已解锁的去处（拓扑/显示名统一取自 data/map_graph.json）；
	# 先算出条数，才能把面板高度一次定下来。
	_places = _available_places()
	_frame = UiStyle.framed(self, Rect2(FRAME_X, FRAME_Y, FRAME_W,
			ROW_TOP + _places.size() * ROW_H + 16))

	var title: Label = UiStyle.label("地图", UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(14, 8)
	_frame.add_child(title)

	var hint: Label = UiStyle.label("[W/S] 选  [E] 前往", UiStyle.LINEN_DARK)
	hint.position = Vector2(150, 22)
	_frame.add_child(hint)

	UiStyle.divider(_frame, 8, 46, FRAME_W - 16)

	for i: int in _places.size():
		var place: Dictionary = _places[i]
		var y: int = ROW_TOP + i * ROW_H

		var bg: ColorRect = UiStyle.rect(UiStyle.BROWN)
		bg.position = Vector2(8, y - 6)
		bg.size = Vector2(FRAME_W - 16, ROW_H - 4)
		bg.visible = false
		_frame.add_child(bg)

		var accent: ColorRect = UiStyle.rect(UiStyle.FIRE)
		accent.position = Vector2(8, y - 6)
		accent.size = Vector2(2, ROW_H - 4)
		accent.visible = false
		_frame.add_child(accent)

		var name_label: Label = UiStyle.label(str(place["name"]), UiStyle.LINEN)
		name_label.position = Vector2(18, y)
		_frame.add_child(name_label)

		var desc: Label = UiStyle.label(str(place["desc"]), UiStyle.LINEN_DARK)
		desc.position = Vector2(18, y + 15)
		_frame.add_child(desc)

		var here_label: Label = UiStyle.label("· 在这里", UiStyle.FIRE)
		here_label.position = Vector2(FRAME_W - 74, y + 8)
		here_label.visible = str(place["scene"]) == here
		_frame.add_child(here_label)

		_rows.append({"bg": bg, "accent": accent, "name": name_label, "place": place})

	_index = _default_index(here)
	_refresh()


func _current_scene_path() -> String:
	var scene: Node = get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


## 只列**已解锁**的去处。没解锁的地图不出现在面板里 ——
## 否则玩家能一步传送到还没去过、剧情也没开放的地方。
func _available_places() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in PLACES:
		var flag: String = str(p.get("unlock", ""))
		if not flag.is_empty() and not SideStory.is_unlocked(flag):
			continue
		out.append(p.duplicate(true))
	return out


func _default_index(here: String) -> int:
	for i: int in _places.size():
		if str(_places[i]["scene"]) == here:
			return (i + 1) % _places.size()
	return 0


func _refresh() -> void:
	for i: int in _rows.size():
		var ui: Dictionary = _rows[i]
		var selected: bool = i == _index
		(ui["bg"] as ColorRect).visible = selected
		(ui["accent"] as ColorRect).visible = selected
		(ui["name"] as Label).add_theme_color_override("font_color",
				UiStyle.FIRE_CORE if selected else UiStyle.LINEN)


func _on_key(keycode: int) -> bool:
	match keycode:
		KEY_W, KEY_UP:
			_move(-1)
			return true
		KEY_S, KEY_DOWN:
			_move(1)
			return true
		KEY_M:
			close()
			return true
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			_travel()
			return true
	return false


func _move(step: int) -> void:
	_index = wrapi(_index + step, 0, _rows.size())
	_refresh()


func _travel() -> void:
	var place: Dictionary = _rows[_index]["place"] as Dictionary
	var path: String = str(place.get("scene", ""))
	# 尚未开放的去处（比如刚解锁的雪山）：不传送，避免 change_scene 传空路径
	if path == "" or not ResourceLoader.exists(path):
		return
	var here: String = _current_scene_path()
	if path == here:
		return

	# 跑路时长 = 地图图逐跳累加（data/map_graph.json 每条边的 minutes）
	var minutes: int = maxi(0, MapGraph.travel_minutes(here, path))
	var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
	var spawn: Vector2 = place["spawn"]
	var hour: int = clock.hour if clock != null else 8
	var minute: int = clock.minute if clock != null else 0
	var ui: Node = UiStyle.ui_layer(self)

	# 先关面板再跑路：close() 会解冻玩家，遮罩紧接着重新冻上 —— 同一帧内接得住。
	close()

	if ui == null or minutes <= 0:
		# 同一张图 / 没算到耗时：老路子，直接瞬移（时间照样带过去）
		_commit_travel(clock, minutes, path, spawn)
		return

	var overlay: TravelOverlay = TravelOverlay.new()
	ui.add_child(overlay)
	overlay.begin(clock, hour, minute, minutes, path, spawn)


## 不播遮罩的传送：推进时间 → 记下出发时刻/落点 → 切场景。
## 与走门共用 DoorArea 的静态通道，昼夜连续。
## 注意调用点在 close() 之后：queue_free 只是打标记，本帧内 self 仍可用。
func _commit_travel(clock: GameClock, minutes: int, path: String, spawn: Vector2) -> void:
	if clock != null:
		clock.advance(float(minutes) * clock.seconds_per_hour / 60.0)
		DoorArea.pending_hour = clock.hour
		DoorArea.pending_minute = clock.minute
	DoorArea.pending_position = spawn
	DoorArea.has_pending = true
	# 去哪儿也要记下来：老场景离场时顾客层据此判断"店里散不散场"
	DoorArea.pending_target = path
	get_tree().change_scene_to_file.call_deferred(path)
