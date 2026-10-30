extends CanvasLayer
## 漆黑空间 —— 厄里斯把主角拉进的那个"漆黑房间"（覆盖层）。
##
## 与「灰空间 dark_space」位置场景（nymph 那场戏）相互独立：本脚本只负责
## 厄里斯戏的"被拉进黑暗"视觉，由 StoryDialogue 的 dark_space:"on/off" 触发。
##
## 照明沿用**酒馆火炉的观感**：一张暖白径向光斑，中心亮、边沿平滑过渡到 0。
## 用 smoothstep 生成、alpha 抖动去 banding 的 `dark_space_glow.png`（512²）当光斑，
## 而不是原来那张 128² 的贴图 —— 后者的 alpha 是台阶式的（255→230→178→153…），
## ADD 叠在纯黑上会看到一圈圈"光圈边界"。新贴图两端导数为 0、边缘 alpha→0，
## 所以光斑是"化开"的，没有边界。
##
## 左右对称：两人分居中线两侧、等距；光斑中心就在两人间隔的中点（x=324）。
## 光斑叠在两人之上（ADD），于是中心那点亮光既照亮两张脸、也从两人缝隙里透出来。
##
## 画在 layer=5：盖住世界（layer 0），但在 HUD（layer 10，含对话框）之下。
## 由 StoryDialogue 在支线某句出现（dark_space:"on"）/ 退场（"off"）时创建与销毁。

const DESIGN := Vector2(640, 384)
const GLOW_TEX := "res://assets/lighting/dark_space_glow.png"
const PLAYER_SHEET := "res://通用方法/walk_v5.png"
const ERIS_SHEET := "res://assets/actors/npc/盗贼少年_俄莉斯.png"

## 两人站位（对称于 x = 324 这条中线）。
const POS_LEFT := Vector2(292, 213)    # 拜登
const POS_RIGHT := Vector2(356, 213)   # 厄里斯
const CENTER := Vector2(324, 207)      # 光源中心 = 两人间隔中点

var _root: Control = null


func _ready() -> void:
	layer = 5
	# 报给 BGM 总控（Music）：「此刻在黑房间」→ 切黑房间曲，free 掉自动切回
	add_to_group("dark_room")
	_root = Control.new()
	_root.size = DESIGN
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# 与 HUD 同样按内部分辨率缩放（生产 2× / 测试 1×），640 坐标才铺满视口
	var s: Vector2 = Vector2.ONE
	if WindowScale != null:
		s = WindowScale.render_scale()
	_root.scale = s

	_build_black()
	# 拜登：第 2 行（面向右）第 0 帧
	_build_actor(PLAYER_SHEET, Rect2(0, 248, 56, 124), POS_LEFT)
	# 厄里斯：第 1 行（面向左）第 0 帧
	_build_actor(ERIS_SHEET, Rect2(0, 120, 60, 120), POS_RIGHT)
	# 光斑最后画：既压亮两人，又在缝里透出一点光
	_build_glow()

	# 淡入：被拉进黑暗的一瞬
	_root.modulate = Color(1, 1, 1, 0)
	var tw: Tween = create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.45)


func _build_black() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.position = Vector2.ZERO
	bg.size = DESIGN
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)


func _build_glow() -> void:
	var tex: Texture2D = load(GLOW_TEX) as Texture2D
	if tex == null:
		return
	var sp: Sprite2D = Sprite2D.new()
	sp.texture = tex
	sp.centered = true
	sp.position = CENTER
	sp.scale = Vector2(0.55, 0.55)   # 512 * 0.55 ≈ 281px，罩住两人与中间那道缝
	sp.modulate = Color(0.68, 0.84, 1.0, 0.30)   # 冷蓝白、再压暗一档（更偏冷）
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sp.material = mat
	_root.add_child(sp)


func _build_actor(sheet_path: String, region: Rect2, pos: Vector2) -> void:
	if not ResourceLoader.exists(sheet_path):
		return
	var tex: Texture2D = load(sheet_path) as Texture2D
	if tex == null:
		return
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = tex
	at.region = region
	var sp: Sprite2D = Sprite2D.new()
	sp.texture = at
	sp.centered = true
	sp.position = pos
	sp.scale = Vector2(0.5, 0.5)
	# 略暗的本色；再由上面的暖光斑压亮，读起来就是"被这盏光照着"
	sp.modulate = Color(0.80, 0.80, 0.86)
	_root.add_child(sp)


## 退场：淡出后自毁（回到酒馆）。
func fade_out_and_free() -> void:
	if _root == null or not is_inside_tree():
		queue_free()
		return
	var tw: Tween = create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)
