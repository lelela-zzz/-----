class_name SceneBootstrap
extends Node2D
## 场景入口引导：把跨场景传送的出生点应用到玩家身上。
##
## 两个世界场景（酒馆 / 村庄）的根节点都挂它：
## DoorArea 切场景前把出生点写进静态变量，本脚本在 _ready 里取走。
## 传送落点要走整数像素（与 PixelCamera 的取整纪律一致）。
##
## 2026-10-30 起多一条：**读档落点优先**。SaveGame 读档时没法直接写位置
## （change_scene 之后新场景还没 ready，拿不到 Player / Clock），只能把
## 「坐标 + 时钟」塞进 pending，由这里在 _ready 取走。存档比传送门落点更权威，
## 所以先看它。

@export_group("Wiring")
@export var player_path: NodePath = ^"Sorted/Player"


func _ready() -> void:
	# 读档：落点 + 时钟都来自存档，把 DoorArea 那套残留一并清掉
	if SaveGame.has_pending_spawn():
		_apply_save_spawn(SaveGame.consume_pending_spawn())
		return
	var clock: GameClock = get_node_or_null("Clock") as GameClock
	if clock != null and DoorArea.pending_hour >= 0:
		clock.set_time(DoorArea.pending_hour, DoorArea.pending_minute)
		DoorArea.pending_hour = -1
	if DoorArea.has_pending == false:
		return
	var player: Player = get_node_or_null(player_path) as Player
	if player == null:
		push_warning("SceneBootstrap：没找到玩家 %s，出生点未应用" % player_path)
		return
	player.global_position = DoorArea.consume_pending().round()
	var camera: PixelCamera = player.get_node_or_null("Camera") as PixelCamera
	if camera != null:
		camera.snap_now()


## 应用存档里的落点与时刻。
## day 走 GameClock 的 setter（会同步写 static _shared_day），这样后面换场景
## 起来的新时钟接的还是同一天。
func _apply_save_spawn(data: Dictionary) -> void:
	DoorArea.has_pending = false
	DoorArea.pending_hour = -1

	var clock: GameClock = get_node_or_null("Clock") as GameClock
	if clock != null:
		clock.day = int(data.get("day", 1))
		clock.set_time(int(data.get("hour", 7)), int(data.get("minute", 30)))

	var player: Player = get_node_or_null(player_path) as Player
	if player == null:
		push_warning("SceneBootstrap：读档落点没找到玩家 %s" % player_path)
		return
	player.teleport_to(data.get("pos", Vector2.ZERO) as Vector2)
	player.face(data.get("facing", Vector2i.DOWN) as Vector2i)
	print("[SceneBootstrap] 读档落位 %s（第 %d 天）" % [player.global_position,
			int(data.get("day", 1))])
