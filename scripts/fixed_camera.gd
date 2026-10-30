class_name FixedCamera
extends Camera2D
## 固定机位：整屏一屏的场景（酒馆室内）没有跟随需求，只要"刚好框住 640×384"。
##
## A 路线之后 viewport 是 1280×768，必须按 viewport/logic 的比例补 zoom，
## 否则房间只占屏幕左上角四分之一。位置由场景给（房间中心），这里只算 zoom。
## viewport 被测试降回 640×384 时，zoom 自然退回 1。

func _ready() -> void:
	zoom = WindowScale.render_scale()
	make_current()
