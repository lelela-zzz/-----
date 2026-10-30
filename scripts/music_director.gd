extends Node
## BGM 总控（autoload：Music）
##
## 【职责单一】按"当前所在场景"换背景乐，双播放器交叉淡入淡出。
## 场景 → 曲目的对应关系写在 SCENE_TRACK 里；曲目文件写在 TRACK_FILE 里。
## 换场景由 DoorArea / 剧情脚本各自 change_scene，本脚本只**观察**
## get_tree().current_scene，不去接管传送逻辑 —— 谁切场景都不用通知它。
##
## 【为什么用双播放器】单播放器换曲必然有一个"先停再起"的空档，酒馆⇄小镇
## 这种高频往返会听出咔哒。两个 AudioStreamPlayer 轮换：新的从 -80dB 淡入、
## 旧的淡出到 -80dB 再 stop，中间没有静音瞬间。
##
## 【场景切换的静默期】change_scene 的过程中 current_scene 会短暂为 null，
## 这时**保持当前曲目**不做任何事，否则每次进门都会掉一次音乐。
##
## 【未登记场景】不认识就保持现状（不静音），新加场景忘了登记时音乐至少不会断。
##
## 【黑房间覆盖层】厄里斯那场戏是 dark_room.tscn 挂在当前场景上（不改场景），
## 所以另外看一个约定：任何节点 add_to_group("dark_room") 就切到黑房间曲；
## 覆盖层 free 掉，组里没人了，就切回场景本该有的曲目。

## 曲目键 → 音频文件
const TRACK_FILE: Dictionary = {
	"tavern": "res://assets/audio/bgm/tavern.wav",
	"town": "res://assets/audio/bgm/town.wav",
	"mine": "res://assets/audio/bgm/mine.wav",
	"spring": "res://assets/audio/bgm/spring.wav",
	"snow": "res://assets/audio/bgm/snow.wav",
	"lair": "res://assets/audio/bgm/lair.wav",
	"dark": "res://assets/audio/bgm/dark.wav",
}

## 场景路径 → 曲目键
##   · 酒馆内 / 酒馆门口与小镇共用"月痕镇"的市井气
##   · 矿道入口在雪山半腰，跟着雪山走
##   · 灰空间（dark_space）就是黑房间
const SCENE_TRACK: Dictionary = {
	"res://scenes/title.tscn": "tavern",
	"res://scenes/world.tscn": "tavern",
	"res://scenes/tavern_exterior.tscn": "town",
	"res://scenes/village.tscn": "town",
	"res://scenes/mine.tscn": "mine",
	"res://scenes/mine_entrance.tscn": "snow",
	"res://scenes/snow_mountain.tscn": "snow",
	"res://scenes/spring.tscn": "spring",
	"res://scenes/dragon_lair.tscn": "lair",
	"res://scenes/dark_space.tscn": "dark",
}

## 黑房间覆盖层认这个组名
const DARK_GROUP: String = "dark_room"

## 交叉淡入淡出时长（秒）
const FADE: float = 1.2
## 静音电平（-80dB 等于听不见，但没有 0 除）
const SILENT_DB: float = -80.0
## 总增益：曲目本身已经是成品混音，再压一点给音效留头
const BASE_DB: float = -4.0
## 音量档位（设置面板按这个步进）
const VOLUME_STEP: float = 0.1
const DEFAULT_VOLUME: float = 0.7

const CONFIG_PATH: String = "user://audio.cfg"
const CFG_SECTION: String = "audio"
const CFG_VOLUME: String = "music_volume"

## 当前曲目键，"" = 静音
var _current: String = ""
## 0..1 的玩家音量（存盘）
var _volume: float = DEFAULT_VOLUME

var _active: AudioStreamPlayer
var _idle: AudioStreamPlayer
var _fade: Tween
## 已加载的 AudioStream 缓存（QOA 解压后很小，重复 load 也不便宜，缓存住）
var _cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_volume()

	_active = _make_player()
	_idle = _make_player()


func _make_player() -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.bus = "Master"
	p.volume_db = SILENT_DB
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


func _process(_delta: float) -> void:
	var want: String = desired_track()
	if want != _current:
		play(want)


# ---- 查询 ------------------------------------------------------------------

## 此刻"应该"放的曲目：黑房间覆盖层优先，其次看当前场景。
## 未登记的场景返回 _current（= 保持不变）。
func desired_track() -> String:
	for n: Node in get_tree().get_nodes_in_group(DARK_GROUP):
		if is_instance_valid(n) and n.is_inside_tree():
			return "dark"

	var scene: Node = get_tree().current_scene
	if scene == null:
		return _current
	var path: String = scene.scene_file_path
	if path.is_empty():
		return _current
	if SCENE_TRACK.has(path):
		return str(SCENE_TRACK[path])
	return _current


func current_track() -> String:
	return _current


func current_stream() -> AudioStream:
	if _active == null:
		return null
	return _active.stream


func is_playing() -> bool:
	return _active != null and _active.playing


## 设置面板用的显示值（0..100 的整数）
func volume_percent() -> int:
	return roundi(_volume * 100.0)


func volume() -> float:
	return _volume


## 正在放的那个播放器的实际电平（验收/调试用；淡入淡出过程中是中间值）
func volume_db_now() -> float:
	return _active.volume_db if _active != null else SILENT_DB


# ---- 播放 ------------------------------------------------------------------

## 换曲（同曲直接返回，不会重头播）。fade < 0 用默认 FADE。
func play(track: String, fade: float = -1.0) -> void:
	if track == _current:
		return
	if fade < 0.0:
		fade = FADE

	if _fade != null and _fade.is_valid():
		_fade.kill()

	_current = track

	if track.is_empty():
		var out: AudioStreamPlayer = _active
		if out.stream == null:
			return
		_fade = create_tween()
		_fade.tween_property(out, "volume_db", SILENT_DB, fade)
		_fade.tween_callback(out.stop)
		return

	var stream: AudioStream = _stream_for(track)
	if stream == null:
		# 记住这个键（而不是清空），否则 desired_track() 每帧都会重试 + 刷警告
		push_warning("Music：曲目 %s 没有可用音频，先静音" % track)
		return

	# 轮换：上一首转为淡出方
	var tmp: AudioStreamPlayer = _active
	_active = _idle
	_idle = tmp

	_active.stream = stream
	_active.volume_db = SILENT_DB
	_active.play()

	_fade = create_tween().set_parallel(true)
	_fade.tween_property(_active, "volume_db", _target_db(), fade)
	_fade.tween_property(_idle, "volume_db", SILENT_DB, fade)
	_fade.chain().tween_callback(_idle.stop)


func _stream_for(track: String) -> AudioStream:
	if _cache.has(track):
		return _cache[track] as AudioStream
	if not TRACK_FILE.has(track):
		return null
	var path: String = str(TRACK_FILE[track])
	if not ResourceLoader.exists(path):
		return null
	var st: AudioStream = load(path) as AudioStream
	if st == null:
		return null
	# 循环点写在 .import（edit/loop_mode=Forward）；这里兜一层，
	# 万一资源被重导成不循环也不至于放完就安静。
	if st is AudioStreamWAV and (st as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var wav: AudioStreamWAV = st as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
	_cache[track] = st
	return st


# ---- 音量 ------------------------------------------------------------------

func set_volume(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	# 值没变就别写盘：鼠标拖动音量条时这个函数会被高频调用，
	# 每次都落一次 cfg 既费 IO 也可能把 SSD 磨出响声（而且毫无意义）。
	if is_equal_approx(v, _volume):
		return
	_volume = v
	_save_volume()
	_apply_volume()


## 按档位加减（设置面板 A/D 用）
func nudge_volume(steps: int) -> void:
	set_volume(snappedf(_volume + float(steps) * VOLUME_STEP, VOLUME_STEP))


func _apply_volume() -> void:
	if _active == null:
		return
	# 淡入淡出进行中就直接接管，免得 tween 把旧音量再写回去
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if _current.is_empty():
		_active.volume_db = SILENT_DB
		return
	_active.volume_db = _target_db()
	_idle.volume_db = SILENT_DB
	if not _active.playing:
		_active.play()


func _target_db() -> float:
	if _volume <= 0.001:
		return SILENT_DB
	return linear_to_db(_volume) + BASE_DB


# ---- 存盘 ------------------------------------------------------------------

func _load_volume() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		_volume = DEFAULT_VOLUME
		return
	_volume = clampf(float(cfg.get_value(CFG_SECTION, CFG_VOLUME, DEFAULT_VOLUME)), 0.0, 1.0)


func _save_volume() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(CFG_SECTION, CFG_VOLUME, _volume)
	cfg.save(CONFIG_PATH)


## 退出时松手：播放器还攥着 AudioStream 的话，引擎收尾会报
## "resources still in use at exit"（只在 --quit 的验收里看得见，但是噪音）。
func _exit_tree() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	for p: AudioStreamPlayer in [_active, _idle]:
		if p != null and is_instance_valid(p):
			p.stop()
			p.stream = null
	_cache.clear()
