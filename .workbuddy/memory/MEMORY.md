# 炉火镇（game2）· 项目长期记忆

## 工程基线
- Godot 4.7.2：`C:\exe\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`；工程根=仓库根
- Python：`C:/Users/了了啦/AppData/Local/Python/pythoncore-3.14-64/python.exe`
- 改 PNG / 新 class_name 后必须 `--headless --import`；headless 验收，截图须窗口模式 + `--quit-after 9000`，输出重定向到文件
- viewport 1280×768 / 逻辑 640×384；相机 zoom=WindowScale.render_scale().x；HUD/UIRoot=640×384 scale=render_scale

## autoload / 经济
- ItemDB·Inventory(起始60铜)·BrewingService·QuestLog·MapGraph·QuestGuide·Story·SideStory·ChapterStory·Chapter2Story·SeatRegistry·WindowScale·Revenue·GameClock
- 酒价=料成本×2.0/×2.5 偶数；材料 1u=2铜（龙息晶25例外）。酒:河鲜淡啤12/好友麦茶16/清口米酿18/焦麦烈啤20/暖身姜酒28
- 顾客预算:凯瑟琳85/西蒙100/哈特菲利亚110/爱德华125（tools/build_npc_data.py 生成 npcs.json）
- Revenue 口径：total(累计,雪山解锁判据≥150)/total_wines_by_id/session_total/best_session/session_wines_by_id
- E键三主(锅/集市/NPC)；UiPanel 进 modal_ui 组

## 时钟/营业
- 30现实秒=1游戏小时；07:30起床；T 挂招牌 07:30–18:00 开张；22:00强制关张；23:00跨天→day+1跳07:30（GameClock._roll_over_curfew）；GameClock.day static 兜底跨场景
- 客流倍率:07:30-11=0.4/11-14=0.9/14-18=1.1/18-21=1.4/21-22=0.9/22后=0
- 打烊不扣开支；自动弹 DayReportPanel；`tavern_open()`=force_disable or (stage==OPEN and business_open)；`Story.in_tavern()`=当前场景 world.tscn

## 任务指引
- 链路：QuestLog.set_tracked(**切换语义,同id再传=取消**) → MapGraph.route() 有向 BFS → QuestGuide.waypoint() → GuideArrow
- dest 命名：章节临时 `Sorted/Npc_beat_<id>`；常驻 `Sorted/Npc_<id>`；静态 `Sorted/BrewingPot`。写错静默退 pos 兜底。world 的 NpcSpawner 关闭（萃歌也是 Npc_beat）
- ChapterStory._sync_objective 每幕都 set_dest；travel 幕必须 _mark_step_done
- 换场景必须 `_recover_after_scene_change()`（否则 autoload 状态残留=剧情死锁）

## 常客 / 顾客判定（2026-10-30）
- autoload **Regulars**：`已认识 = 玩家真对过话`（`Npc._open_dialogue` 最前面 `mark_known`）；`BASE_KNOWN`=首发4常客(哈/西/爱/凯)预置(否则开张日无人来)；`NOT_CUSTOMER`=萃歌/卡兹 + 林格/宁芙/伊织/特蕾西亚
- CustomerSpawner：`_all_defs`(全部NPC定义) + `_candidates`(有图集且 allows_customer) + `roster()`=已认识∩候选；`spawn_random` 只放已认识 + `_in_scene` 去重(支线访客还在场不重复摆)；`defs()` 仍只返回显式4人(旧语义/verify_customers 钉死 size==4)
- 无 customer 块的角色用 `Customer.DEFAULT_PROFILE`(预算90+通用招呼/买后/离场)
- Phase2 待办：已认识角色当顾客本就 spawn 在 ENTRY(320,300) 再走位，"后续到来从门口进来"基本已满足；首次剧情登场仍原地(用户要保留)
- **营业框第三行**：`预计客流 N 人`（N=`CustomerSpawner.daily_customer_cap()`=roster().size()，每人每天最多买一次）；营业中追加 `· 已来 M`（`arrived_today()`，static `_arrived_day`，进店即记）；BusinessHud HEIGHT 54
- 验收 verify_regulars 12 / ui_panels 15 / customers 23；persist13/rush3/day_cycle11/chapter1-3 全绿

## 剧情/多人同台纪律
- **多人对话全员同场**：两章导演 `_freeze_wanderers()`/`_held_npcs`（跳过顾客）、`_clear_beat_npcs` 先 resume_wander、`_face_cast`；Npc.hold()/resume_wander()/_stored_wander
- extra 透传：extra 字典除 npc/spawn/offset 外键（如 no_interact）透传 Npc.configure；SideStory `try_play` 播前 `_spawn_arc_extras`(offset 相对说话人)+冻结
- `Npc.no_interact`：无 [E] 提示、按 E 无效、不参与 _is_nearest
- **wait_day**（Chapter2Story）：`_day_mark` 在 begin/每次 _index+1 时取当天；`_beat_ready` 要求 `_game_day() > _day_mark`；`_game_day()` 必须取**当前场景的 Clock**（组里第一个会撞孤儿时钟），无 Clock 退 `GameClock._shared_day`
- 幕模型：wait_for_talk=true 等玩家按 E；npc+spawn(+facing)；同幕多人 extras:[{npc,spawn/offset,facing}]
- 数据口径：entries 每个非空 speaker（除拜登=玩家）必须在场
- 俄莉斯追奇斯两幕轮流登场是用户拍板节奏，勿改
- ⚠ 死支线待办：sasaki_river_fish（佐佐木）无 customer 键无 spawn 永不触发（待用户拍板；设计稿「河边奇遇·第二幕」正文待补）。dwarves_dispatch 已修
- 剧情道具交易 trade{give,pay,receive}；GiveWinePanel；canon：拜登(人族商人)+萃歌(丰收神明)经营银辉酒馆

## 场景/碰撞
- world.tscn=640×782(y∈[-398,384])；地窖门洞(106,28)-(147,83)；碰撞改 props.json；遮挡改 sort_y；map_graph 有向 6 图
- 角色脚盒 Feet 10×6（可站立判定 [x-5,y-6]..[x+5,y]）；NPC/顾客无碰撞检测（纯折线）→ 路线必须按 props.json collision_rect 线段相交验收
- 顾客离场 Customer.build_leave_path()：凳子→反序 seat.path→_exit_tail(CORNER_C→B→A→ENTRY)，不能直奔 (320,200)
- map_graph 耗时：village↔tavern_exterior 往返各 10 分钟（直连段 8+2）

## 传送点（改门必须同步 map_graph.json 的 spawn）
- mine_entrance(1024²)/spring(768²,props size 定基准)/snow(512²)
- mine_entrance SnowPath(452,1004)→雪山；spring SnowPath(660,716)→雪山
- snow Doors：MineReturn(325,478) spawn→mine (500,962)；SpringPath(250,200) spawn→spring (692,620)；落雪山 (250,475)
- 判路网：颜色阈值取土路连通块+ASCII 网格+碰撞叠加（勿骨架化）

## 512² 小图标准（snow/ext 同款）与相机
- 小图（512）相机行为：视口 640>512 → x 恒钉 256 居中，y 夹 [192,320]
- tavern_exterior 512²：建筑碰撞(34,0,462,321) sort_y=320；门 TavernDoor(230,345)→world(319,360)；RoadEast/West(507,433)/(5,433)→village(630,700)；world.ExitSouth→(230,363)、village.TavernDoor→(230,467)（与 map_graph 一致，verify_map_graph 钉）
- 底图管道：make_snow_bg.py <源图>→1x/2x png+网格预览；NEAREST 整数抽取（勿 LANCZOS）；自带去水印；换 png 即换画面
- 调色 make_snow_cool.py：逐色族定向重映射，勿全局滤镜
- ⚠ snow 遗留：props.json 33 条碰撞按旧图失效（<100 红，需 make_snow_collision.py 重算，被 _validate_bridge 旧桥硬编码拦）

## 第三章「龙王传说」（终章，2026-10-30 落地）
- 解锁：`Story.REVENUE_THRESHOLD_CH3=400` + `_ch2_done`（Chapter2Story.finished → _on_ch2_finished）；导演 `Chapter3Story`（autoload，QID ch3_dragon_king）
- 数据 `data/story_chapter3.json` 10 幕：奇斯密函→西蒙带路→矿道入口→矿井史莱姆(rift)→travel→龙巢 4 幕(爱德华/龙醒林格/圣剑 whiteout/醒来告别)→酒馆尾声；travel 幕的 dest 指 **Doors/LairGate**
- **龙巢不在 map_graph**：矿井八边形石室东墙 `Doors/LairGate`（RiftDoor，ch3_mine_slime 播完才 visible+monitoring，落点 lair (480,700)）；lair `Doors/BackToMine`(480,840)→mine(500,790)
- 龙巢 `dragon_lair.tscn` **960²**（源图 1920 = ×2，2x 即原图、1x NEAREST ÷2）：`tools/make_dragon_bg.py` / `make_dragon_collision.py`（亮度≥24+32px 60% 格，32 条岩壁；盘龙 (268,196,336,444)、骸骨 (208,288,104,234)）
- 白幕：幕加 `whiteout:true` → `_run_whiteout()`（0.35 淡入+3s+0.9 淡出，期间 _pump 停）；终章 `game_finished=true`
- 卡兹 = `ancient_kaz`，占位图由 `tools/make_kaz_actor.py` 从巫妖_维兹定向换色（正式图同名覆盖即可）；林格/特蕾西亚复用既有 NPC

## 灰空间
- `dark_space.tscn`=位置场景（三件套 Sorted/Player/HUD·UIRoot 必备）；`dark_room.tscn`=厄里斯覆盖层(story_dialogue dark_space:on/off)
- 走不到的场景走 SCRIPTED_JUMP_PLACES+_try_scripted_jump；幕可写 jump_spawn 定落点
- 一次性空间站位：Player.facing 写死在 tscn；间距要短

## 工作流
- 改碰撞只动 props.json；改图先备份再重导入
- ⚠ **编辑器并行存盘**：用户开着 Godot 编辑器会回写 .tscn/测试脚本；批量回归前确认盘上稳定，改断言前先 grep 现值
- ⚠ **headless 测试时序铁律**：①行为在物理帧→采样前 await physics_frame；②非 await verify 函数保持全同步（加 await 会与后续检查并发互踩）
- 回归基线(2026-10-30 晚)：38 套件全绿 exit=0（map_graph77/chapter1 35/chapter2 31/npc15/guide15/sidestory18/void17/customers23/give_wine20/persist13/day_cycle11 等）；唯一例外 verify_snow 1 红（岩壁碰撞 33<100 旧遗留）

## 音频 / BGM（2026-10-30）
- autoload **`Music`**（`scripts/music_director.gd`）：双播放器 1.2s 交叉淡入淡出，靠 `current_scene.scene_file_path` 判场景；`SCENE_TRACK` 一张表定映射，`TRACK_FILE` 定文件。未登记场景保持当前曲（不静音）；换场景空窗（current_scene=null）不动作。
- 曲目：`assets/audio/bgm/{tavern,town,mine,spring,snow,lair,dark}.wav`（源 WAV 141MB，导入 QOA→约 26MB 内存）。**循环靠 `.import` 的 `edit/loop_mode=2`（Forward）**，改图/重导后要确认没被重置。
- 映射：world=tavern｜village+tavern_exterior=town｜mine=mine｜snow_mountain+mine_entrance=snow｜spring=spring｜dragon_lair=lair｜dark_space+dark_room覆盖层=dark。
- 黑房间覆盖层走组 `"dark_room"`（dark_room.gd 自己 add_to_group），覆盖层在场即压 dark 曲。
- 音量存 `user://audio.cfg`（`music_volume`，默认 0.7、BASE_DB=-4、SILENT=-80dB）；F10 面板第 4 行「音乐音量」，10% 一档。
- 验收 `tests/verify_music.tscn`（89 项）+ 截图 `tests/bgm_shot.tscn`。
- headless 退出偶报 "resources still in use at exit"：dummy 音频驱动 flush 不及，窗口模式无此提示，非 bug。

## 开始界面 / 主菜单（2026-10-30）
- `project.godot` main_scene = **`scenes/title.tscn`**（world 不再直接启动）；脚本 `scripts/ui/title_screen.gd`（root=Node2D，界面全在代码里搭）
- **尺度口径**：标题屏按 **1280×768 原生渲染**排版，不跟 640 逻辑网格；字号只取 12 的整数倍（96 标题 / 36 菜单 / 24 小字）。验收/截图**不要**对它调 TestView.logic_resolution()
- 底图 `assets/title/v1/title_bg_2x.png` 由 `tools/make_title_bg.py` 生成：酒馆外观黄昏 512² NEAREST ×2 → CROP_Y=84 裁上 768 行 → 左 256 镜像接边 + smoothstep 压黑(240→720) → 暖色调 + 门/壁灯/窗 9 团高斯暖光 → 暗角 + 顶/底压暗
- 菜单五项：**继续游戏 / 读取存档**（`needs_save`；`_has_save()` = `FileAccess.file_exists("user://hearthvale_save.cfg")`，没存档→置灰 + 同行「暂无存档」，按 E 只 flash_note 不动作）/ 开始游戏 / 设置 / 退出游戏；无存档默认停在「开始游戏」(index=2)
- 存档系统接上后：写 SAVE_PATH + 在 `_continue_game()` / `_load_game()` 接读档，两行会自动亮
- 交互：W/S/↑↓ 环绕、E/Enter/Space 确认、鼠标悬停/点击；设置面板直接实例化 `scenes/ui/settings_panel.tscn` 挂 CanvasLayer(10)
- Music.SCENE_TRACK 增 `title.tscn → tavern`；验收 `tests/verify_title.tscn`（25 项），观感 `tests/title_shot.tscn`（9 张）
