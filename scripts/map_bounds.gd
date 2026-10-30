class_name MapBounds
extends StaticBody2D
## 大地图外边界：给定可行走矩形，四面自动生成厚墙（无门洞）。
##
## 室内的 room_collision.gd 管的是"四面墙 + 底部门洞"；大地图没有门洞
## （进出地图走 DoorArea 传送），所以退化成最简单的四条厚墙。
## 障碍物（水/围栏/货箱）不在这里——它们跟物件数据同源，走 props.json。

@export_group("Map")
## 可行走矩形（x, y, w, h）。墙从它的四边向外顶出。
@export var walkable: Rect2 = Rect2(8.0, 8.0, 850.0, 850.0)
## 墙厚，只影响碰撞体，不影响画面；取大值防高速穿角。
@export var thickness: float = 64.0
## 打开后描出可行走框（青）。
@export var show_debug: bool = false

@export_group("Door")
## 顶部门洞：顶墙在此 x 范围开口（世界坐标，左右缘），用于"上方房间"通过洞口接入。
## 设为空向量 = 不开口。
@export var top_gap_x: Vector2 = Vector2.ZERO


func _ready() -> void:
	var b: Rect2 = walkable
	var t: float = thickness
	var rects: Array[Rect2] = []
	# 顶墙（可能开门洞）
	rects += _split_h_wall(b.position.x - t, b.position.y - t, b.size.x + t * 2.0, t, top_gap_x, b.position.x, b.end.x)
	# 底墙
	rects.append(Rect2(b.position.x - t, b.end.y, b.size.x + t * 2.0, t))
	# 左右墙
	rects.append(Rect2(b.position.x - t, b.position.y, t, b.size.y))
	rects.append(Rect2(b.end.x, b.position.y, t, b.size.y))
	for r: Rect2 in rects:
		_add_box(r)
	queue_redraw()


## 把一条水平墙按门洞列表切成若干段（门洞内留空）。
func _split_h_wall(x0: float, y0: float, w: float, h: float, gap: Vector2, lo: float, hi: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if gap == Vector2.ZERO or gap.x >= gap.y:
		out.append(Rect2(x0, y0, w, h))
		return out
	# gap 在 [lo,hi] 坐标系；转换到墙的本地 x（墙从 lo-t 开始）
	var gx0: float = (lo + gap.x) - x0
	var gx1: float = (lo + gap.y) - x0
	out.append(Rect2(x0, y0, gx0, h))
	out.append(Rect2(x0 + gx1, y0, w - gx1, h))
	return out


func _add_box(r: Rect2) -> void:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = r.size
	var col: CollisionShape2D = CollisionShape2D.new()
	col.shape = shape
	col.position = r.position + r.size * 0.5
	add_child(col)


func _draw() -> void:
	if not show_debug:
		return
	draw_rect(walkable, Color(0.2, 1.0, 1.0, 0.85), false, 1.0)
