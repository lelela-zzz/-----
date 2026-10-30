class_name MineSlimeSpawner
extends RefCounted
## 矿井史莱姆的**摆放工具**（纯静态，无状态）。
##
## 第一/第三章的矿井幕都要往洞里摆史莱姆，而"摆哪儿才不会穿墙"这套判定
## 只该有一份实现，所以抽到这里，两个导演都调它。
##
## 判定的关键：**用整个精灵框，不是脚下的小圆**。
## 史莱姆精灵 55×57、原点在脚底、身子全在原点**上方**，只测脚下半径 13px 的圆
## 完全测不出"脚踩在地上、半个身子插进岩壁"——那正是之前看着卡墙的原因。

## 精灵框半宽 / 高度（与 slime.gd 的 MOVE_HALF_W / MOVE_HEIGHT、WORLD_SCALE 0.07 对得上）。
const HALF_W: float = 28.0
const HEIGHT: float = 58.0


## 读 props.json 里可阻挡的 collision_rect（跳过 no_collision 的纯装饰件）。
static func load_collision_rects(sorted_node: Node) -> Array:
	var path: String = "res://assets/mine/v1/objects/props.json"
	if sorted_node != null:
		var p: Variant = sorted_node.get("props_path")
		if p is String and str(p) != "":
			path = str(p)
	var out: Array = []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for entry: Variant in (parsed as Dictionary).get("props", []):
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry as Dictionary
		if bool(d.get("no_collision", false)):
			continue
		var cr: Variant = d.get("collision_rect", null)
		if cr is Array and (cr as Array).size() >= 4:
			var a: Array = cr as Array
			out.append(Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])))
	return out


## 场景的可行走边界（Static.walkable），取不到就给矿井默认值。
static func walkable_bounds(scene: Node) -> Rect2:
	if scene != null:
		var st: Node = scene.get_node_or_null("Static")
		if st != null:
			var w: Variant = st.get("walkable")
			if w is Rect2 and (w as Rect2).size.x > 0.0:
				return w as Rect2
	return Rect2(8, 8, 1008, 1008)


## 该点放不放得下一只**整只**史莱姆（精灵框 vs 碰撞矩形 + 边界）。
static func box_blocked(rects: Array, bounds: Rect2, p: Vector2,
		half_w: float = HALF_W, height: float = HEIGHT) -> bool:
	var l: float = p.x - half_w
	var r: float = p.x + half_w
	var t: float = p.y - height
	var b: float = p.y
	if bounds.size.x > 0.0:
		if l < bounds.position.x or r > bounds.end.x \
				or t < bounds.position.y or b > bounds.end.y:
			return true
	for entry: Variant in rects:
		var rr: Rect2 = entry as Rect2
		if l < rr.end.x and r > rr.position.x and t < rr.end.y and b > rr.position.y:
			return true
	return false


## 投放点若压着岩壁，就螺旋外扩找最近的空地（避免"出生即埋进石头"）。
static func free_point(rects: Array, bounds: Rect2, p: Vector2) -> Vector2:
	if not box_blocked(rects, bounds, p):
		return p
	for ring: int in range(1, 10):
		var rad: float = float(ring) * 12.0
		for k: int in 24:
			var ang: float = TAU * float(k) / 24.0
			var q: Vector2 = p + Vector2(cos(ang), sin(ang)) * rad
			if not box_blocked(rects, bounds, q):
				return q
	return p
