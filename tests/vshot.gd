extends Node
## 村庄验收入口（引导层）。
##
## 真传送流会调用 change_scene_to_file，它会替换 current_scene——
## 如果验收逻辑直接写在主场景里，第一次传送就会把自己一起释放掉。
## 所以：本文件只负责「把检查器挂到场景树根、把村庄设为当前场景」，
## 真正的检查全部在 vcheck.gd（root 子节点，不受场景切换影响）。

const VILLAGE_SCENE := "res://scenes/village.tscn"
const CHECKER_SCRIPT := "res://tests/vcheck.gd"


func _ready() -> void:
	TestView.logic_resolution()
	StoryDirector.force_disable = true
	await get_tree().process_frame
	var village: Node = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(village)
	get_tree().current_scene = village
	var checker: Node = (load(CHECKER_SCRIPT) as GDScript).new()
	get_tree().root.add_child(checker)
	queue_free()
