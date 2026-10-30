class_name RiftDoor
extends DoorArea
## 矿井深处的裂隙传送门（第三章专用）。
##
## 平时不存在：只有 Chapter3Story 打开闸门（`is_rift_open()`）之后，
## 这扇门才露出来并开始监听踩踏。这样第一、二章下矿时不会看到一团
## 凭空出现的漩涡，也不会误入终章地图。
##
## 视觉就是精灵本身：没开闸时整张图隐藏（不占碰撞、不发光）。

## 是否受第三章闸门控制（false = 一直开着，给回归用例用）。
@export var gated: bool = true

var _open: bool = false


func _ready() -> void:
	super()
	_open = not gated or _gate_open()
	_apply()


func _gate_open() -> bool:
	return Chapter3Story != null and Chapter3Story.is_rift_open()


func _process(_delta: float) -> void:
	if not gated:
		return
	var now: bool = _gate_open()
	if now != _open:
		_open = now
		_apply()


func _apply() -> void:
	monitoring = _open
	visible = _open
