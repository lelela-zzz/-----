class_name GatherSpot
extends InteractZone
## 野外采集点：矿道入口、河岸、废弃哨塔这类"走上去按 E 拿一份"的地点。
##
## 继承 InteractZone 而不是重写一遍，是为了白拿三样东西：
## 走近才浮出的 [E] 提示、和 NPC/锅之间的"近者优先"仲裁、以及模态面板开着时不响应。
## 这里只补两件采集点独有的事：**出什么**（读 ItemDB）、**多久一出**（冷却）。
##
## 数据驱动：只要在场景里填 map_name + spot，池子会自己去 ItemDB 里查
## obtain=mine/gather 且地点匹配的原料；清单里加了新产地，这里不用改代码。
##
## 用法（将来放地图上）：
##   GatherSpot 节点 → map_name="黑松山脉"、spot="矿道入口"
##   → 摆到矿洞口，配个 CollisionShape2D，完事。

## 地图名，对应 items.json 的 map 字段
@export var map_name: String = ""
## 地点名，对应 items.json 的 spot 字段
@export var spot: String = ""
## 一次采几份
@export var amount: int = 1
## 采完之后多久再长出来（游戏分钟；90 分钟 = 45 现实秒）
@export var cooldown_minutes: float = 90.0
## 手填池子；留空 = 按 map_name/spot 从数据里自动取
@export var pool: Array[String] = []

var _cooldown: float = 0.0
var _next: int = 0
var _flash: Label = null
var _flash_frames: int = 0


func _init() -> void:
	# 场景里没改过的话就用"采集"当提示词；改过的话场景值会覆盖掉这里
	prompt_text = "采集"


func _ready() -> void:
	super._ready()
	_resolve_pool()
	_flash = UiStyle.outlined_label("", UiStyle.LINEN)
	_flash.size = Vector2(180, 16)
	_flash.position = prompt_offset + Vector2(-90, -18)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.z_index = 200
	_flash.visible = false
	add_child(_flash)


func _resolve_pool() -> void:
	if not pool.is_empty():
		return
	if map_name != "":
		pool = ItemDB.ids_at(map_name, spot)


func _process(delta: float) -> void:
	super._process(delta)
	if _cooldown > 0.0:
		var clock: GameClock = get_tree().get_first_node_in_group("game_clock") as GameClock
		if clock != null and clock.running and clock.seconds_per_hour > 0.0:
			_cooldown = maxf(0.0, _cooldown - delta * 60.0 / clock.seconds_per_hour)
	if _flash_frames > 0:
		_flash_frames -= 1
		if _flash_frames == 0 and _flash != null:
			_flash.text = ""


## 采集一份。成功返回物品 id，冷却中或池子空返回空串。
## 直接调这个方法就是"采集"，所以验收脚本不用模拟按键。
func gather() -> String:
	if pool.is_empty():
		_flash_say("这里采不到东西", UiStyle.METAL_DARK)
		return ""
	if _cooldown > 0.0:
		_flash_say("还没长好，再等 %d 分钟" % ceili(_cooldown), UiStyle.METAL_DARK)
		return ""
	var id: String = pool[_next % pool.size()]
	_next = (_next + 1) % pool.size()
	Inventory.add(id, amount)
	_cooldown = cooldown_minutes
	_flash_say("+%d %s" % [amount, ItemDB.item_name(id)], UiStyle.LINEN)
	return id


func cooldown_remaining() -> float:
	return _cooldown


## 清掉冷却。调试用；将来读档恢复采集点状态时也用得上。
func reset_cooldown() -> void:
	_cooldown = 0.0


## 覆盖父类的开面板：采集点没有面板，按 E 就是直接采一下。
func _open() -> void:
	gather()


func _flash_say(text: String, color: Color) -> void:
	if _flash == null:
		return
	_flash.text = text
	_flash.add_theme_color_override("font_color", color)
	_flash.visible = true
	_flash_frames = 90
