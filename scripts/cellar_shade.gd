extends Polygon2D
## 跨层阴影：同一张图里，另一层（玩家不在的那间房）压一层冷暗色，把上下两层分开。
##
## 为什么要有它：酒馆和地窖现在是同一张图（world.tscn，地窖贴在酒馆上方）。
## 同框出现时，不在的那一层跟眼前的这一层一样亮，看起来像"同一个房间的上下两块"，
## 而不是"我这一层看得见的那间房"。压一层阴影把两层分开：人在哪层、哪层亮，另一层暗。
##
## 用法（world.tscn 里挂两个 Polygon2D，都用本脚本）：
##   · `CellarShade`  ：铺满 world y<=0（地窖），invert=false → 玩家在店堂里时压暗地窖；
##   · `TavernShade`  ：铺满 world y>=0（店堂），invert=true  → 玩家在地窖里时压暗店堂。
##
## 何时亮/暗（按玩家脚下 y，越大越靠南=越在店堂里）：
##   默认（invert=false，压地窖）：
##     y >= full_at_y  → 阴影拉满（玩家在店堂里）
##     y <= clear_at_y → 阴影收干（站到门口、要上楼了）
##   反向（invert=true，压店堂）：
##     y <= full_at_y  → 阴影拉满（玩家在地窖里）
##     y >= clear_at_y → 阴影收干（回到店堂里）
##   中间线性过渡，再按 fade_speed 平滑，避免边界处闪。
## 收干要卡在门洞附近：玩家头还探在另一层时如果还压着，会被盖一块黑。

## 玩家。留空则退回 player 组。
@export var player_path: NodePath = ^"../Sorted/Player"
## 拉满时的不透明度。0.5 上下：够压出层次，又不至于看不出那层里有什么。
@export var dark_alpha: float = 0.5
## 压暗"北边那层"（y 小）还是"南边那层"（y 大）。
## false = 玩家在南边（店堂，y 大）→ 压北边（地窖）；true = 玩家在北边（地窖，y 小）→ 压南边（店堂）。
@export var invert: bool = false
## 玩家 y 越过这里 → 阴影拉满（invert=false 时 y>=它=在店堂；invert=true 时 y<=它=在地窖）。
@export var full_at_y: float = 110.0
## 玩家 y 到这侧 → 阴影收干（invert=false 时 y<=它=在门口；invert=true 时 y>=它=回店堂）。
@export var clear_at_y: float = 55.0
## 平滑速度（越大越跟手）。
@export var fade_speed: float = 3.2

var _player: Node2D = null
var _alpha: float = 0.0


func _ready() -> void:
	_bind()
	_alpha = target_alpha()
	_apply(_alpha)


## 当前该有多暗（0 = 完全不压，1 = 拉满）。
func target_alpha() -> float:
	if _player == null:
		return dark_alpha
	var k: float
	if invert:
		# 压南边（店堂）：玩家在更北（y 小=地窖）→ 拉满；回到南边（y 大=店堂）→ 收干
		var span: float = maxf(clear_at_y - full_at_y, 1.0)
		k = clampf((clear_at_y - _player.global_position.y) / span, 0.0, 1.0)
	else:
		# 压北边（地窖）：玩家在更南（y 大=店堂）→ 拉满；上到北边 → 收干
		var span: float = maxf(full_at_y - clear_at_y, 1.0)
		k = clampf((_player.global_position.y - clear_at_y) / span, 0.0, 1.0)
	return dark_alpha * k


func _process(delta: float) -> void:
	_bind()
	_alpha = lerpf(_alpha, target_alpha(), clampf(delta * fade_speed, 0.0, 1.0))
	_apply(_alpha)


func _apply(a: float) -> void:
	var c: Color = color
	c.a = a
	color = c


func _bind() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = get_node_or_null(player_path) as Node2D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
