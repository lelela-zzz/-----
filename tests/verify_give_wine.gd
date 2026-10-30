extends Node
## 剧情"东西过手"验收（递酒 / 卖酒 / 收道具）：
##   1) 递酒（give, pay=false）：翻页时先弹窗；选前不扣、选后扣 1 瓶且不收钱；
##      结果补进这一句（「递上了…」），再按一次才翻页
##   2) 卖酒（give, pay=true）：选后扣 1 瓶、铜币涨、营业额记 1 瓶
##   3) 收道具（receive）：不弹窗，直接把东西塞进背包，并补一句「收到了…×N」
##   4) 身上没可交的东西（give 但没酒）：不弹空窗，也不卡住对话
## 运行： "<godot>" --headless --path . res://tests/verify_give_wine.tscn --quit-after 9000

var _pass := 0
var _fail := 0
var _scene: Node


func _ready() -> void:
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	await get_tree().process_frame
	_scene = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	await get_tree().process_frame

	await _case_gift()
	await _case_sell()
	await _case_receive()
	await _case_empty()

	print("[give_wine] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---- 1. 递酒（白送）------------------------------------------------------

func _case_gift() -> void:
	Inventory.clear()
	Inventory.add("wine_warm_ginger", 2)
	var before: int = Inventory.count("wine_warm_ginger")
	var copper0: int = Inventory.copper

	var dlg: UiPanel = _make_dialogue([
		{"speaker": "拜登", "role": "银辉酒馆老板", "text": "给，你要的酒。",
			"trade": {"give": "wine", "pay": false}},
		{"speaker": "", "role": "", "text": "（对方接过酒，道了谢。）"},
	])
	await _frames(6)

	var gw: Node = await _press_until_picker(dlg)
	_report("递酒句翻页 → 弹出选物窗", gw != null, "panel=%s" % (gw != null))
	_report("递酒窗是「只列酒 + 不收款」模式",
			gw != null and str(gw.get("pick_kind")) == "wine" and not bool(gw.get("pay_mode")),
			"kind=%s pay=%s" % [gw.get("pick_kind") if gw != null else "?",
			gw.get("pay_mode") if gw != null else "?"])
	_report("选之前不扣库存", Inventory.count("wine_warm_ginger") == before,
			"count=%d before=%d" % [Inventory.count("wine_warm_ginger"), before])

	if gw == null:
		return
	_push_key(KEY_E)
	await _frames(6)
	_report("选完扣掉 1 瓶", Inventory.count("wine_warm_ginger") == before - 1,
			"count=%d（原 %d）" % [Inventory.count("wine_warm_ginger"), before])
	_report("白送不收钱", Inventory.copper == copper0,
			"copper=%d（原 %d）" % [Inventory.copper, copper0])
	_report("结果补进这一句（写着递上了）", _text_has(dlg, "递上了"),
			_text_of(dlg))
	_report("选物窗已关闭", _pick_panel() == null, "")

	_push_key(KEY_E)
	await _frames(4)
	_report("再按一次才翻到下一句", is_instance_valid(dlg) and int(dlg.get("_index")) == 1,
			"index=%s" % (dlg.get("_index") if is_instance_valid(dlg) else "?"))

	await _close_dialogue(dlg)


# ---- 2. 卖酒（收钱）------------------------------------------------------

func _case_sell() -> void:
	Inventory.clear()
	Inventory.add("wine_burnt_ale", 1)
	var copper0: int = Inventory.copper
	var price: int = ItemDB.price("wine_burnt_ale")
	var wines0: int = Revenue.session_wines

	var dlg: UiPanel = _make_dialogue([
		{"speaker": "拜登", "role": "银辉酒馆老板", "text": "哈特菲利亚女士，您的酒。",
			"trade": {"give": "wine", "pay": true}},
		{"speaker": "哈特菲利亚", "role": "魔导士", "text": "谢谢。"},
	])
	await _frames(6)

	var gw: Node = await _press_until_picker(dlg)
	_report("卖酒句翻页 → 弹出选物窗", gw != null, "panel=%s" % (gw != null))
	_report("卖酒窗是「收款」模式", gw != null and bool(gw.get("pay_mode")),
			"pay=%s" % (gw.get("pay_mode") if gw != null else "?"))

	if gw == null:
		return
	_push_key(KEY_E)
	await _frames(6)
	_report("卖完扣 1 瓶", Inventory.count("wine_burnt_ale") == 0,
			"count=%d" % Inventory.count("wine_burnt_ale"))
	_report("卖完进账 %d 铜" % price, Inventory.copper == copper0 + price,
			"copper=%d → %d" % [copper0, Inventory.copper])
	_report("营业台账记了 1 瓶", Revenue.session_wines == wines0 + 1,
			"wines=%d → %d" % [wines0, Revenue.session_wines])
	_report("结果补进这一句（写着收了钱）", _text_has(dlg, "收了 %d 铜" % price),
			_text_of(dlg))

	await _close_dialogue(dlg)


# ---- 3. 收道具 -----------------------------------------------------------

func _case_receive() -> void:
	Inventory.clear()
	var before: int = Inventory.count("wine_riesling")

	var dlg: UiPanel = _make_dialogue([
		{"speaker": "爱德华", "role": "钢之炼金术士",
			"text": "我带来了「利塞布尔」的名酒雷司令，作为等价交换。",
			"trade": {"receive": [{"id": "wine_riesling", "count": 1}]}},
		{"speaker": "", "role": "", "text": "（他把酒放到柜台上。）"},
	])
	await _frames(6)

	# 只收东西、不用交东西 → 不该弹窗，按到这一句就自动结算
	var gw: Node = await _press_until_picker(dlg)
	_report("只收道具的句子不弹选物窗", gw == null, "panel=%s" % (gw != null))
	_report("道具真的进了背包（雷司令 +1）",
			Inventory.count("wine_riesling") == before + 1,
			"count=%d（原 %d）" % [Inventory.count("wine_riesling"), before])
	_report("结果补进这一句（写着收到了）", _text_has(dlg, "收到了"),
			_text_of(dlg))

	await _close_dialogue(dlg)


# ---- 4. 没东西可交 -------------------------------------------------------

func _case_empty() -> void:
	Inventory.clear()

	var dlg: UiPanel = _make_dialogue([
		{"speaker": "拜登", "role": "银辉酒馆老板", "text": "给，你要的酒。",
			"trade": {"give": "wine", "pay": true}},
		{"speaker": "客人", "role": "客人", "text": "……？（他看着你空空的手）"},
	])
	await _frames(6)

	var gw: Node = await _press_until_picker(dlg)
	_report("身上没酒 → 不弹空窗", gw == null, "panel=%s" % (gw != null))
	_report("没东西可交时老实补一句提示", _text_has(dlg, "没有能拿出来的东西"),
			_text_of(dlg))

	_push_key(KEY_E)
	await _frames(4)
	_report("说完照样能翻页（不会卡住）",
			not is_instance_valid(dlg) or int(dlg.get("_index")) >= 1,
			"index=%s" % (dlg.get("_index") if is_instance_valid(dlg) else "已关闭"))

	if is_instance_valid(dlg):
		await _close_dialogue(dlg)


# ---- 工具 ---------------------------------------------------------------

func _make_dialogue(entries: Array) -> UiPanel:
	var hud: Node = _scene.get_node("HUD/UIRoot")
	var ps: PackedScene = load("res://scenes/ui/story_dialogue.tscn") as PackedScene
	var dlg: UiPanel = ps.instantiate() as UiPanel
	dlg.set("entries", entries)
	dlg.set("gift_guest", "测试客")
	hud.add_child(dlg)
	return dlg


## 一直按 E，直到选物窗出现、或者这一句的交接已经结算完。
func _press_until_picker(dlg: UiPanel) -> Node:
	for i: int in 8:
		if not is_instance_valid(dlg) or not dlg.is_inside_tree():
			break
		var gw: Node = _pick_panel()
		if gw != null:
			return gw
		_push_key(KEY_E)
		await _frames(3)
		var done: Dictionary = dlg.get("_trade_done") as Dictionary
		if done.has(int(dlg.get("_index"))):
			break
	return _pick_panel()


func _close_dialogue(dlg: UiPanel) -> void:
	for i: int in 20:
		if not is_instance_valid(dlg) or not dlg.is_inside_tree():
			return
		_push_key(KEY_E)
		await _frames(2)


func _pick_panel() -> Node:
	for n: Node in get_tree().get_nodes_in_group("modal_ui"):
		if n.has_method("_candidates") and n.has_signal("chosen"):
			return n
	return null


func _text_of(dlg: UiPanel) -> String:
	if not is_instance_valid(dlg):
		return "（面板已关）"
	var lbl: Variant = dlg.get("_text_label")
	if lbl is Label:
		return (lbl as Label).text
	return ""


func _text_has(dlg: UiPanel, needle: String) -> bool:
	return _text_of(dlg).contains(needle)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


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
		_pass += 1
		print("[check] PASS  %s" % name)
	else:
		_fail += 1
		print("[check] FAIL  %s  (%s)" % [name, detail])
