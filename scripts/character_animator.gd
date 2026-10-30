class_name CharacterAnimator
extends AnimatedSprite2D
## 四方向行走动画组件。
##
## 从一张「columns 列 × rows 行」的行走图集，运行时用 AtlasTexture 切格构建
## SpriteFrames（避免手写 .tres 的 UID），再按「朝向 dir + 是否移动 moving」
## 切换行走 / 待机（待机 = 定格在 idle_frame）。
##
## 行序约定（本图集实测）：0=下(正面) 1=左 2=右 3=上(背面)。
## 像素不糊：依赖图集按项目默认 Nearest 导入，本组件不做任何平滑缩放。
##
## 用法：把本脚本挂到一个 AnimatedSprite2D 上，指定 sheet，然后每帧调用
##   update_anim(facing, is_moving)

## 行序号 → 动画名。顺序必须与图集的行顺序一致。
## 第 4 行（索引 4）= 坐姿（sit），仅当图集是 5 行时才存在；4 行图集不会访问到它。
const ROW_ANIM: Array[String] = ["walk_down", "walk_left", "walk_right", "walk_up", "sit"]

@export var sheet: Texture2D
@export var columns: int = 4
@export var rows: int = 4
## 行走动画帧率（帧/秒）。
@export var fps: float = 9.0
## 待机定格帧（行走循环里挑一个最接近站姿的帧）。
@export var idle_frame: int = 0

var _built: bool = false
var _last_row: int = 0


func _ready() -> void:
	_build()
	_apply(_last_row, false)


## 供控制器每帧调用：dir 为四方向单位向量，moving 为是否在走。
func update_anim(dir: Vector2i, moving: bool) -> void:
	if not _built:
		_build()
	_apply(_row_for(dir), moving)


## 由朝向求行号。dir 为四方向单位向量；零向量时沿用上一朝向。
func _row_for(dir: Vector2i) -> int:
	if dir == Vector2i.ZERO:
		return _last_row
	if dir.y > 0:
		return 0   # 下 / 正面
	if dir.y < 0:
		return 3   # 上 / 背面
	if dir.x < 0:
		return 1   # 左
	return 2       # 右


func _build() -> void:
	if _built or sheet == null:
		return
	var cw: float = float(sheet.get_width()) / float(columns)
	var ch: float = float(sheet.get_height()) / float(rows)
	var frames: SpriteFrames = SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for r in range(rows):
		var anim_name: String = ROW_ANIM[r]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, fps)
		frames.set_animation_loop(anim_name, true)
		for c in range(columns):
			var at: AtlasTexture = AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(c * cw, r * ch, cw, ch)
			frames.add_frame(anim_name, at)
	sprite_frames = frames
	_built = true


func _apply(row: int, moving: bool) -> void:
	if sprite_frames == null:
		return
	_last_row = row
	var anim_name: String = ROW_ANIM[row]
	if moving:
		# 换方向或刚起步才重播；同向持续行走时保持循环，避免每帧回到第 0 帧
		if animation != anim_name or not is_playing():
			play(anim_name)
	else:
		if animation != anim_name:
			animation = anim_name
		pause()
		frame = clampi(idle_frame, 0, maxi(0, columns - 1))


## 定格在任意行的某一帧（坐姿等静态姿态用）。
## 若该 row 对应的动画不存在（比如图集还没补第 5 行坐姿帧），退回普通待机（站立 idle），
## 这样"尚未补真坐姿帧"的阶段也能跑、不报错——等真帧就位后自动生效。
func play_pose(row: int, frame_index: int, fallback_dir: Vector2i = Vector2i.DOWN) -> void:
	if sprite_frames == null:
		return
	var name: String = ROW_ANIM[row] if row < ROW_ANIM.size() else ""
	if name == "" or not sprite_frames.has_animation(name):
		update_anim(fallback_dir, false)
		return
	_last_row = row
	animation = name
	pause()
	# 注意：参数绝不能叫 `frame` —— 那会遮蔽 AnimatedSprite2D 的 `frame` 属性，
	# `frame = clampi(...)` 只改局部变量、精灵永远停在第 0 帧（坐姿一直显示正/背
	# 占位稿、朝向怎么改都一样的元凶）。用 self.frame 明确写属性。
	self.frame = clampi(frame_index, 0, maxi(0, sprite_frames.get_frame_count(name) - 1))
