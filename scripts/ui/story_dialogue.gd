extends UiPanel
## 多说话人剧情对话（支线用）。
##
## 和 dialogue_box 的区别：dialogue_box 是"一个 NPC 的连续独白"，标题固定；
## 这里每一句自带 speaker / role，拜登与 NPC 交替，必要时插旁白（speaker 为空，
## 名字藏掉、正文压暗一档）。推进方式一样：E/空格/回车，先补全再翻页。
##
## 句子可以带"东西过手"的一拍（`trade` 字典）：
##   give     交出什么："" 不用交 / "wine" 只列酒 / 其他 kind / 具体规则由 pick_kind 给
##   pay      交出的是买卖（收钱、记营业额）还是白送
##   receive  对方给你的东西：[{id, count}, ...]
## 例：
##   {"text": "给，你要的酒。", "trade": {"give": "wine", "pay": true}}
##   {"text": "……名酒雷司令，作为等价交换。", "trade": {"receive": [{"id": "wine_riesling", "count": 1}]}}
##
## 老写法 `"give_wine": true` 仍然认，等同 `{"give": "wine", "pay": false}`。

signal entry_shown(index: int)

const CHARS_PER_SECOND: float = 45.0
## 对话条高度；横向位置/宽度由 UiPanel.bottom_bar 按画布算，别在这里写死 x。
const FRAME_H: int = 128

## 由 SideStory 在 add_child 之前写入：[{speaker, role, text, trade?}, ...]
var entries: Array = []

## 交接环节：标题副行的"给谁"，由 SideStory 写 npc_name。
var gift_guest: String = ""
## 付款人（顾客节点，可能为 null）。卖酒时走他的钱袋，买不起就卖不成。
var trade_payer: Node = null

var _paused: bool = false          # 选物窗开着时，本对话不响应 E
var _pick_open: bool = false
var _pending_trade: Dictionary = {}  # 正在结算的这一拍
var _trade_done: Dictionary = {}     # 已结算的句号，避免重复弹窗
var _dark: Node = null               # 漆黑空间覆盖层（厄里斯那段）

var _frame_rect: Rect2 = Rect2()
var _name_label: Label = null
var _role_label: Label = null
var _text_label: Label = null
var _index: int = 0
var _revealed: float = 0.0
var _full_len: int = 0


func _build() -> void:
	_frame_rect = bottom_bar(FRAME_H)
	var frame: Panel = UiStyle.panel(UiStyle.SHADOW, UiStyle.BROWN)
	frame.position = _frame_rect.position
	frame.size = _frame_rect.size
	add_child(frame)

	_name_label = UiStyle.label("", UiStyle.FIRE_CORE, UiStyle.BODY_SIZE)
	_name_label.position = Vector2(12, 8)
	frame.add_child(_name_label)

	_role_label = UiStyle.label("", UiStyle.LINEN_DARK, UiStyle.BODY_SIZE)
	_role_label.position = Vector2(12, 8)
	frame.add_child(_role_label)

	var hint: Label = UiStyle.label("[E] 继续", UiStyle.LINEN_DARK)
	hint.position = Vector2(int(_frame_rect.size.x) - 76, 8)
	frame.add_child(hint)

	UiStyle.divider(frame, 12, 28, int(_frame_rect.size.x) - 24)

	_text_label = UiStyle.label("", UiStyle.LINEN, UiStyle.BODY_SIZE)
	_text_label.position = Vector2(12, 38)
	_text_label.size = Vector2(_frame_rect.size.x - 24, _frame_rect.size.y - 46)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frame.add_child(_text_label)

	_show_entry(0)


func _entry(i: int) -> Dictionary:
	if i < 0 or i >= entries.size():
		return {}
	return entries[i] as Dictionary


func _show_entry(i: int) -> void:
	if _text_label == null:
		return
	var e: Dictionary = _entry(i)
	var speaker: String = str(e.get("speaker", ""))
	var role: String = str(e.get("role", ""))
	var text: String = str(e.get("text", ""))

	_name_label.text = speaker
	_name_label.visible = speaker != ""
	_role_label.text = role
	_role_label.visible = role != ""
	if speaker != "":
		# 身份紧跟名字；名字宽度决定副标题的起点
		_role_label.position = Vector2(12 + _text_width(speaker) + 10, 8)
		_text_label.add_theme_color_override("font_color", UiStyle.LINEN)
	else:
		# 旁白：没有名字、正文暗一档，和人物台词区分开
		_text_label.add_theme_color_override("font_color", UiStyle.LINEN_DARK)

	_text_label.text = text
	_full_len = text.length()
	_revealed = 0.0
	_text_label.visible_characters = 0
	# 这一句是不是"进入/离开漆黑空间"：进场盖黑幕、退场撤黑幕
	_apply_dark_space(e)
	# 逐句广播：剧情导演据此在指定台词触发场景事件（如矿井史莱姆被姜酒杀死）。
	entry_shown.emit(i)


func _apply_dark_space(e: Dictionary) -> void:
	match str(e.get("dark_space", "")):
		"on":
			_dark_show()
		"off":
			_dark_hide()


func _dark_show() -> void:
	if _dark != null and is_instance_valid(_dark):
		return
	var ps: PackedScene = load("res://scenes/dark_room.tscn") as PackedScene
	if ps == null:
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	_dark = ps.instantiate()
	host.add_child(_dark)


func _dark_hide() -> void:
	if _dark != null and is_instance_valid(_dark):
		_dark.call("fade_out_and_free")
	_dark = null


## 关对话时务必撤掉黑幕（哪怕是被 Esc 直接跳过）。
func close() -> void:
	_dark_hide()
	super.close()


func _text_width(s: String) -> int:
	var f: Font = UiStyle.theme().default_font
	return int(f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.BODY_SIZE).x)


func _process(delta: float) -> void:
	if _text_label == null or _full_len <= 0:
		return
	if _text_label.visible_characters >= _full_len and _text_label.visible_characters != -1:
		return
	_revealed = minf(_revealed + delta * CHARS_PER_SECOND, float(_full_len))
	_text_label.visible_characters = int(_revealed)


func _fully_revealed() -> bool:
	return _text_label == null or _text_label.visible_characters == -1 \
			or _text_label.visible_characters >= _full_len


func _advance() -> void:
	if not _fully_revealed():
		# 第一下先把这句显示完，第二下才翻页 —— 手快的人不会漏字
		_revealed = float(_full_len)
		_text_label.visible_characters = -1
		return
	# 这一句有东西要过手（递酒 / 卖酒 / 收人情）：先结算，玩家再按一次才翻页
	if not _trade_done.has(_index):
		var t: Dictionary = _trade_at(_index)
		if not t.is_empty():
			_begin_trade(t)
			return
	_advance_index()


func _advance_index() -> void:
	_index += 1
	if _index >= entries.size():
		close()
		return
	_show_entry(_index)


# ---- 东西过手 -------------------------------------------------------------

## 这一句要交接什么。没有就返回空字典。
func _trade_at(i: int) -> Dictionary:
	var e: Dictionary = _entry(i)
	var t: Variant = e.get("trade", null)
	if t is Dictionary:
		return t as Dictionary
	# 老写法：give_wine = 递一瓶酒，不收钱
	if bool(e.get("give_wine", false)):
		return {"give": "wine", "pay": false}
	return {}


## 身上有多少件符合条件的东西（决定要不要开选物窗）。
func _candidate_count(kind: String) -> int:
	var n: int = 0
	for id: String in ItemDB.items:
		var k: String = str((ItemDB.items[id] as Dictionary).get("kind", ""))
		if kind != "" and k != kind:
			continue
		if Inventory.count(id) > 0:
			n += 1
	return n


func _begin_trade(t: Dictionary) -> void:
	_pending_trade = t
	var want: String = str(t.get("give", ""))
	# 身上没有可交的东西，就别弹一个空窗 —— 直接结算（可能只有 receive）
	if want != "" and _candidate_count(want) > 0:
		_open_picker(want, bool(t.get("pay", false)))
		return
	_settle_trade("", want != "")


func _open_picker(kind: String, pay: bool) -> void:
	_paused = true
	_pick_open = true
	var hud: Node = UiStyle.ui_layer(self)
	var ps: PackedScene = load("res://scenes/ui/give_wine_panel.tscn") as PackedScene
	if hud == null or ps == null:
		# 找不到 UI 层就当作"算了"，照常翻页，别把对话卡死
		_pick_open = false
		_settle_trade("")
		return
	var panel: UiPanel = ps.instantiate() as UiPanel
	panel.set("guest_name", gift_guest if gift_guest != "" else "客人")
	panel.set("pick_kind", kind)
	panel.set("pay_mode", pay)
	hud.add_child(panel)
	panel.connect("chosen", _on_pick_chosen)
	panel.closed.connect(_on_pick_closed)


func _on_pick_chosen(id: String) -> void:
	if not _pick_open:
		return
	_pick_open = false
	_settle_trade(id)


func _on_pick_closed() -> void:
	# 选物窗被 Esc / 关闭：没选也算处理过，直接继续
	if not _pick_open:
		return
	_pick_open = false
	_settle_trade("")


## 结算这一拍：交出（可能收钱）→ 收下对方给的 → 把结果补进这句话里。
## [param no_stock] 为真表示"确实没东西可交"（不是玩家自己点了算了）。
func _settle_trade(given_id: String, no_stock: bool = false) -> void:
	var t: Dictionary = _pending_trade
	_pending_trade = {}
	var bits: Array[String] = []

	if given_id != "":
		var res: Dictionary = _hand_over(given_id, bool(t.get("pay", false)))
		if bool(res.get("ok", false)):
			bits.append("递上了「%s」" % ItemDB.item_name(given_id))
			var paid: int = int(res.get("price", 0))
			if paid > 0:
				bits.append("收了 %d 铜" % paid)
		else:
			bits.append("钱袋空了，这杯只好作罢")
	elif no_stock:
		bits.append("你手头没有能拿出来的东西")

	for r: Variant in (t.get("receive", []) as Array):
		if not (r is Dictionary):
			continue
		var d: Dictionary = r as Dictionary
		var rid: String = str(d.get("id", ""))
		var n: int = int(d.get("count", 1))
		if rid == "" or n <= 0 or not ItemDB.has(rid):
			continue
		Inventory.add(rid, n)
		bits.append("收到了「%s」×%d" % [ItemDB.item_name(rid), n])

	_note(bits)
	_finish_trade(not bits.is_empty())


## 把一件东西交出去。pay = 收钱（真顾客走他的钱袋，站桩 NPC 按标价现收）。
func _hand_over(id: String, pay: bool) -> Dictionary:
	if pay:
		var is_wine: bool = str((ItemDB.items.get(id, {}) as Dictionary).get("kind", "")) == "wine"
		# 顾客（Customer）有自己的钱袋和偏好价，交给他卖才扣得对
		if is_wine and trade_payer != null and is_instance_valid(trade_payer) \
				and trade_payer.has_method("sell"):
			var p: int = int(trade_payer.call("sell", id))
			return {"ok": p > 0, "price": p}
		var price: int = ItemDB.price(id)
		if not Inventory.remove(id, 1):
			return {"ok": false, "price": 0}
		Inventory.earn(price)
		if Revenue != null:
			Revenue.note_wine_sold(id, 1)
		return {"ok": true, "price": price}
	if not Inventory.remove(id, 1):
		return {"ok": false, "price": 0}
	return {"ok": true, "price": 0}


## 把"递了什么、收了几个钱、拿到了什么"补在当前这句末尾 —— 玩家的操作看得见。
func _note(bits: Array[String]) -> void:
	if bits.is_empty() or _text_label == null:
		return
	var base: String = str(_entry(_index).get("text", ""))
	var shown: String = base + "（" + "，".join(bits) + "）"
	_text_label.text = shown
	_full_len = shown.length()
	_revealed = float(_full_len)
	_text_label.visible_characters = -1


func _finish_trade(did_something: bool) -> void:
	_freeze_player(true)   # 选物窗关闭时会解冻玩家，对话还开着，重新冻上
	_paused = false
	_trade_done[_index] = true
	# 什么都没发生（没东西可交、也没收到东西）：别让玩家白按一下
	if not did_something:
		_advance_index()


func _on_key(keycode: int) -> bool:
	if _paused:
		# 选物窗开着：对话先别响应 E（让事件落到选物窗上）
		return false
	if keycode != KEY_E and keycode != KEY_SPACE and keycode != KEY_ENTER \
			and keycode != KEY_KP_ENTER:
		return false
	_advance()
	return true


func _input(event: InputEvent) -> void:
	# 选物窗开着时，键盘（E 选物 / Esc 取消）全交给选物窗；
	# 否则 Esc 会把整个对话一起关掉（两个面板都在 modal 组里抢键）。
	if _paused:
		return
	super._input(event)
