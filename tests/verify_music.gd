extends Node
## BGM 验收：
##   1) 七首曲目都真的导进来了（能 load、时长 > 30s、循环点 = Forward）；
##   2) 场景 → 曲目表覆盖全部场景，且表里没有错路径；
##   3) current_scene 一变，Music 就跟着换曲（酒馆 / 小镇 / 矿井 / 雪山 / 龙巢 …）；
##   4) 黑房间覆盖层（dark_room.tscn）在场时压成黑房间曲，撤掉自动回场景曲；
##   5) 音量档位能改、能存进 user://audio.cfg、0% 真的静音。
## 运行： "<godot>" --headless --path . res://tests/verify_music.tscn --quit-after 9000

const MIN_LENGTH: float = 30.0
const VOL_EPS: float = 0.01

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	StoryDirector.force_disable = true
	CustomerSpawner.force_disable = true
	await get_tree().process_frame

	_part_streams()
	_part_map()
	await _part_scene_switch()
	await _part_dark_overlay()
	_part_volume()
	await _part_real_scenes()

	print("[music] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---- 1) 曲目文件 ------------------------------------------------------------

func _part_streams() -> void:
	for key: String in Music.TRACK_FILE:
		var path: String = str(Music.TRACK_FILE[key])
		_report("曲目 %s 文件存在" % key, FileAccess.file_exists(path), path)
		if not FileAccess.file_exists(path):
			continue
		var st: AudioStream = load(path) as AudioStream
		_report("曲目 %s 能加载" % key, st != null, str(st))
		if st == null:
			continue
		_report("曲目 %s 时长 >= %ds" % [key, int(MIN_LENGTH)],
				st.get_length() >= MIN_LENGTH, "%.1fs" % st.get_length())
		var loop_mode: int = -1
		if st is AudioStreamWAV:
			loop_mode = (st as AudioStreamWAV).loop_mode
		_report("曲目 %s 循环 = Forward" % key,
				loop_mode == AudioStreamWAV.LOOP_FORWARD,
				"loop_mode=%d" % loop_mode)


# ---- 2) 场景映射表 ----------------------------------------------------------

func _part_map() -> void:
	var want: Array[String] = [
		"res://scenes/world.tscn",
		"res://scenes/tavern_exterior.tscn",
		"res://scenes/village.tscn",
		"res://scenes/mine.tscn",
		"res://scenes/mine_entrance.tscn",
		"res://scenes/snow_mountain.tscn",
		"res://scenes/spring.tscn",
		"res://scenes/dragon_lair.tscn",
		"res://scenes/dark_space.tscn",
	]
	for scene: String in want:
		_report("登记了 %s" % scene.get_file(), Music.SCENE_TRACK.has(scene),
				str(Music.SCENE_TRACK.get(scene, "—")))
	for scene: String in Music.SCENE_TRACK:
		_report("映射场景存在 %s" % scene.get_file(), FileAccess.file_exists(scene), scene)
		_report("映射曲目存在 %s" % str(Music.SCENE_TRACK[scene]),
				Music.TRACK_FILE.has(Music.SCENE_TRACK[scene]),
				str(Music.SCENE_TRACK[scene]))


# ---- 3) 场景切换自动换曲 ----------------------------------------------------

func _part_scene_switch() -> void:
	var cases: Array[Dictionary] = [
		{"scene": "res://scenes/village.tscn", "track": "town"},
		{"scene": "res://scenes/tavern_exterior.tscn", "track": "town"},
		{"scene": "res://scenes/world.tscn", "track": "tavern"},
		{"scene": "res://scenes/mine.tscn", "track": "mine"},
		{"scene": "res://scenes/mine_entrance.tscn", "track": "snow"},
		{"scene": "res://scenes/snow_mountain.tscn", "track": "snow"},
		{"scene": "res://scenes/spring.tscn", "track": "spring"},
		{"scene": "res://scenes/dragon_lair.tscn", "track": "lair"},
		{"scene": "res://scenes/dark_space.tscn", "track": "dark"},
	]
	for c: Dictionary in cases:
		var holder: Node2D = _enter(str(c["scene"]))
		await _frames(3)
		_report("进 %s 放 %s" % [str(c["scene"]).get_file(), str(c["track"])],
				Music.current_track() == str(c["track"]),
				"current=%s" % Music.current_track())
		_report("进 %s 有流在放" % str(c["scene"]).get_file(),
				Music.current_stream() != null and Music.is_playing(),
				"stream=%s playing=%s" % [Music.current_stream() != null, Music.is_playing()])
		_exit(holder)
		await _frames(2)


## 造一个"假装是某个场景"的替身：Node.scene_file_path 是 Music 唯一的判据，
## 所以不必真加载重场景。注意 current_scene 必须是 root 的直接子节点。
func _enter(scene_path: String) -> Node2D:
	var holder: Node2D = Node2D.new()
	holder.scene_file_path = scene_path
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	return holder


func _exit(holder: Node2D) -> void:
	if is_instance_valid(holder):
		holder.free()


# ---- 4) 黑房间覆盖层 --------------------------------------------------------

func _part_dark_overlay() -> void:
	var holder: Node2D = _enter("res://scenes/mine.tscn")
	await _frames(3)
	_report("覆盖层前 = 矿井曲", Music.current_track() == "mine", Music.current_track())

	var room: Node = (load("res://scenes/dark_room.tscn") as PackedScene).instantiate()
	holder.add_child(room)
	await _frames(3)
	_report("黑房间在场 → 换黑房间曲", Music.current_track() == "dark", Music.current_track())

	holder.remove_child(room)
	room.free()
	await _frames(3)
	_report("黑房间撤掉 → 回矿井曲", Music.current_track() == "mine", Music.current_track())

	_exit(holder)
	await _frames(2)


# ---- 5) 音量 ----------------------------------------------------------------

func _part_volume() -> void:
	Music.set_volume(0.7)
	_report("音量 70% 档位", Music.volume_percent() == 70, str(Music.volume_percent()))
	_report("70% 有增益", absf(Music.volume_db_now() - (linear_to_db(0.7) - 4.0)) <= VOL_EPS,
			"%.2fdB" % Music.volume_db_now())

	Music.nudge_volume(-1)
	_report("降一档 = 60%", Music.volume_percent() == 60, str(Music.volume_percent()))
	Music.nudge_volume(1)
	_report("升一档 = 70%", Music.volume_percent() == 70, str(Music.volume_percent()))

	Music.set_volume(0.0)
	_report("0% 静音", Music.volume_db_now() <= -79.0, "%.1fdB" % Music.volume_db_now())

	var cfg: ConfigFile = ConfigFile.new()
	var loaded: int = cfg.load("user://audio.cfg")
	_report("音量写盘", loaded == OK
			and absf(float(cfg.get_value("audio", "music_volume", -1.0))) <= VOL_EPS,
			"err=%d v=%s" % [loaded, cfg.get_value("audio", "music_volume", "—")])

	# 收尾：恢复默认，别把测试音量留给开发机
	Music.set_volume(Music.DEFAULT_VOLUME)
	_report("恢复默认音量", Music.volume_percent() == roundi(Music.DEFAULT_VOLUME * 100.0),
			str(Music.volume_percent()))


# ---- 6) 真场景自报路径 ------------------------------------------------------

## 前一段用"替身"验映射逻辑；这一段用真场景验 scene_file_path 对得上 ——
## 镜头里换场景靠的就是这个字段，写错名字这里会立刻红。
func _part_real_scenes() -> void:
	var cases: Array[Dictionary] = [
		{"scene": "res://scenes/world.tscn", "track": "tavern"},
		{"scene": "res://scenes/mine.tscn", "track": "mine"},
		{"scene": "res://scenes/spring.tscn", "track": "spring"},
	]
	for c: Dictionary in cases:
		var ps: PackedScene = load(str(c["scene"])) as PackedScene
		if ps == null:
			_report("真场景 %s 可加载" % str(c["scene"]).get_file(), false, "load 失败")
			continue
		var node: Node = ps.instantiate()
		get_tree().root.add_child(node)
		_report("真场景 %s 自报路径一致" % str(c["scene"]).get_file(),
				node.scene_file_path == str(c["scene"]), node.scene_file_path)
		get_tree().current_scene = node
		await _frames(3)
		_report("真场景 %s 放 %s" % [str(c["scene"]).get_file(), str(c["track"])],
				Music.current_track() == str(c["track"]), Music.current_track())
		get_tree().current_scene = null
		node.free()
		await _frames(2)


# ---- 工具 ------------------------------------------------------------------

func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _report(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s  (%s)" % [label, detail])
