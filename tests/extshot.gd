extends Node
## 酒馆外观验收入口（引导层）。
##
## 与 vshot.gd 同理：真传送流会替换 current_scene，检查器必须挂在
## 场景树根上才不会被一起释放。真正检查在 extcheck.gd。

const EXTERIOR_SCENE := "res://scenes/tavern_exterior.tscn"
const CHECKER_SCRIPT := "res://tests/extcheck.gd"


func _ready() -> void:
	TestView.logic_resolution()
	StoryDirector.force_disable = true
	await get_tree().process_frame
	var exterior: Node = (load(EXTERIOR_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(exterior)
	get_tree().current_scene = exterior
	var checker: Node = (load(CHECKER_SCRIPT) as GDScript).new()
	get_tree().root.add_child(checker)
	queue_free()
