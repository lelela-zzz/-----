class_name DayReportPanel
extends UiPanel
## 打烊结算（22:00 强制关张 / 玩家自己收招牌时弹出）。
##
## 以前只有一条 toast，飘过去就没了 —— 但"今天赚了多少、卖了几瓶、
## 离雪山委托还差多少"正是玩家做下一天计划要看的三个数。做成一张小结卡，
## 也是"一天结束"这个节拍的落点。
##
## 数据由 Story.close_business() 塞进 report 再 add_child（纯数据，不回头查）。

## 比原来矮 20：原来多一行"雪山委托(累计)"，那行已经搬进任务栏了。
const FRAME: Rect2 = Rect2(176, 88, 288, 188)

## { "day": int, "revenue": int, "wines": int, "best": int,
##   "threshold": int, "forced": bool }
var report: Dictionary = {}


func _build() -> void:
	_frame = UiStyle.framed(self, FRAME)

	var title: Label = UiStyle.label("打烊", UiStyle.FIRE_CORE, UiStyle.TITLE_SIZE)
	title.position = Vector2(16, 12)
	_frame.add_child(title)

	var day: int = int(report.get("day", 1))
	var why: String = "22:00 到点" if bool(report.get("forced", false)) else "自己收的招牌"
	var sub: Label = UiStyle.label("第 %d 天 · %s" % [day, why], UiStyle.LINEN_DARK)
	sub.position = Vector2(16 + _width("打烊", UiStyle.TITLE_SIZE) + 10, 20)
	_frame.add_child(sub)

	UiStyle.divider(_frame, 10, 46, int(FRAME.size.x) - 20)

	var revenue: int = int(report.get("revenue", 0))
	var wines: int = int(report.get("wines", 0))
	var best: int = int(report.get("best", 0))

	var y: int = 56
	_row("今日进账", "%d 铜" % revenue, y, UiStyle.GOLD)
	_row("卖出", "%d 瓶" % wines, y + 20, UiStyle.LINEN)
	_row("单次最高", "%d 铜" % best, y + 40, UiStyle.LINEN)
	_row("营业时长", "%d 小时" % int(report.get("hours", 0)), y + 60, UiStyle.LINEN)

	# 解锁进度（累计营业额 / 该认识谁）已搬到任务栏的「准备清单」——
	# 结账卡只管"今晚赚了多少"，不再兼职当进度条（2026-10-30 用户要求）。
	var hint: Label = UiStyle.label("明早 07:30 再开张 · [Esc] 知道了", UiStyle.LINEN_DARK)
	hint.position = Vector2(16, int(FRAME.size.y) - 26)
	_frame.add_child(hint)


func _row(name: String, value: String, y: int, color: Color) -> void:
	var k: Label = UiStyle.label(name, UiStyle.LINEN_DARK)
	k.position = Vector2(20, y)
	_frame.add_child(k)
	var v: Label = UiStyle.label(value, color)
	v.position = Vector2(110, y)
	v.size = Vector2(int(FRAME.size.x) - 130, 14)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame.add_child(v)


func _width(text: String, size: int) -> int:
	var f: Font = UiStyle.theme().default_font
	return int(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
