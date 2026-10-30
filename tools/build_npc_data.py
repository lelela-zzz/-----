"""生成 data/npcs.json（NPC 唯一数据源）。

角色资料按 character/人物行走 的 19 张图集一条条写死在 CHARACTERS 里 ——
名字/身份/台词都是创作内容，不适合从文件名猜，所以放在这里维护，
跑一次脚本产出 JSON，游戏只读 JSON。

用法：python tools/build_npc_data.py
"""
from __future__ import annotations

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "npcs.json")
SHEET_DIR = "res://assets/actors/npc/"

# id, 图集文件名(不含扩展名), 名字, 身份, 台词, 出场点
# 出场点 = (场景, x, y, 朝向, 游荡半径)；不在场景里出现就留空列表。
CHARACTERS = [
    # 萃歌不在 character/ 的 19 张里：图集是占位简笔人（tools/make_cuige_placeholder.py），
    # 用户拿到正式图后直接同名覆盖 assets/actors/npc/酒馆老板娘_萃歌.png 即可。
    ("tavern_cuige", "酒馆老板娘_萃歌", "萃歌", "酒馆老板娘",
     ["开张头一天，手脚都麻利点。",
      "材料不够就去集市找凯瑟琳，她给你留了货。"],
     [{"scene": "world", "pos": [295, 160], "facing": "right", "wander": 0.0,
       # 老板娘在「吧台外」的餐厅区绕圈踱步（绕圆桌 1 一圈）：
       # 北侧走道(295,160)→东(480,160)→南下圆桌中缝(480,250)→西回(295,250)→北。
       # 全程轴对齐（相邻点 x 或 y 相同，四方向移动才走得直），
       # 且都避开了吧台、长桌/圆桌/酒桶碰撞框与顾客服务带（北侧贴酒桶下沿外侧走）。
       # ghost = 关掉脚底碰撞，玩家/顾客可穿身而过，绝不挡路。
       "patrol_route": [[295, 160], [480, 160], [480, 250], [295, 250]],
       "ghost": True}]),

    ("knight_ringe", "人类骑士_林格", "林格", "人类骑士",
     ["这镇子夜里很安静，火一直有人看着。",
      "你要出门就把斗篷系紧，风从山口来。"],
     [("world", 352, 274, "down", 0.0)]),

    ("elf_emt", "半妖精_EMT", "EMT", "半妖精",
     ["我第一次来这里，菜单上写的都是我没听过的东西。",
      "……可以先给我一杯热的吗？"],
     []),

    ("lich_wiz", "巫妖_维兹", "维兹", "巫妖",
     ["别怕，我只是路过。骨头不咬人，酒才咬人。",
      "……玩笑。给我一杯淡的就好。"],
     []),

    ("broker_chiss", "情报贩子_奇斯", "奇斯", "情报贩子",
     ["消息和酒一样，新鲜的才卖得上价。",
      "你今天想知道点什么？先说好，我只卖给识货的。"],
     []),

    ("spring_nymph", "泉水精灵_宁芙", "宁芙", "泉水精灵",
     ["水缸里那口泉水，是我从山上带来的。",
      "喝之前先闻一闻，它会告诉你今天好不好。"],
     []),

    ("ronin_himura", "流浪剑士_绯村", "绯村", "流浪剑士",
     ["剑挂在墙上就别去碰，坐下吧。",
      "这火比路边的柴堆暖，我多待一会儿。"],
     []),

    ("thief_eris", "盗贼少年_俄莉斯", "俄莉斯", "厄里斯神",
     ["我什么都没拿！……真的。",
      "你那杯放桌边会洒，我帮你往里挪一点。"],
     []),

    ("dwarf_cook_kaito", "矮人厨师_凯多", "凯多", "矮人厨师",
     ["锅里的汤再炖一刻钟，别催。",
      "矮人做菜讲究火候，跟打铁一个道理。"],
     [("world", 300, 236, "up", 0.0)]),

    ("dwarf_war_edward", "矮人战士_爱德华", "爱德华", "矮人战士",
     ["盔甲擦过了，酒别溅上来。",
      "……好吧，溅上也不算大事。"],
     []),

    ("dwarf_hand_kaijin", "矮人杂工_凯金", "凯金", "矮人杂工",
     ["地窖的木箱我搬完了，腿都软了。",
      "老板，能不能先记我账上一杯？"],
     []),

    ("dwarf_serv_kain", "矮人杂役_凯恩", "凯恩", "矮人杂役",
     ["桌角那块有点晃，我垫了纸片。",
      "要是又晃了，喊我一声就行。"],
     []),

    ("miner_simon", "矿工少年_西蒙", "西蒙", "矿工少年",
     ["矿洞里今天很干，出来一身灰。",
      "先洗把脸再喝，不然一杯就上头。"],
     []),

    ("bartender_iori", "调酒专家_伊织", "伊织", "调酒专家",
     ["配方在架上第二排，别翻乱。",
      "新酿的还在发酵，急不得——好酒都这样。"],
     [("world", 466, 150, "down", 0.0)]),

    ("brewer_greym", "酿酒专家_灰毛小姐", "灰毛小姐", "酿酒专家",
     ["这批麦芽发得漂亮，闻着有点甜。",
      "再过两天开缸，你先欠我一杯。"],
     [("world", 556, 158, "left", 16.0)]),

    ("fisher_sasaki", "钓鱼佬_佐佐木", "佐佐木", "钓鱼佬",
     ["今天河里没咬钩，就钓上来一尾小的。",
      "小的留着做汤，大的明天再来。"],
     [("world", 560, 242, "left", 14.0)]),

    ("market_catherine", "集市管理员_凯瑟琳", "凯瑟琳", "集市管理员",
     # 默认台词 = 她在**酒馆里**（作为顾客 / 站桩）说的。
     ["集市收了摊我才得空进来。",
      "要买料明早来，我给你留好的。"],
     # placement 第 6 项 = 该位置专用台词；有就覆盖默认台词（见 main()）。
     # 集市摊位上她说的必须是摊主口吻 —— 以前两处共用一套，站在集市里却说
     # 「集市收了摊我才得空进来」，等于把酒馆台词搬到了集市。
     [("world", 600, 296, "up", 0.0),
      ("village", 300, 782, "down", 0.0,
       ["拜登？来得正好，今早的货刚摆开。",
        "生姜、野莓、麦子、草药都在架上，要哪样自己挑。",
        "……别一回扛太多，山路滑。"])]),

    ("explorer_lucy", "雪山探险家_哈特菲利亚", "哈特菲利亚", "FAIRY TAIL 魔导士",
     ["山上雪线又往下压了一截。",
      "脚上这双靴子，走过三个冬天了。"],
     []),

    ("reception_icarus", "魔法接待员_伊卡洛斯", "伊卡洛斯", "魔法接待员",
     ["登记簿在柜台上，名字写清楚就行。",
      "……你写字真好看。"],
     []),

    ("dragon_theresia", "龙人_特蕾西亚", "特蕾西亚", "龙人",
     ["别盯着角看，会不好意思。",
      "屋子里暖和，我把尾巴收一收。"],
     []),

    # 第三章反派：古代生物卡兹。正式图未到，先用「巫妖_维兹」做同骨架换色
    # （tools/make_kaz_actor.py：棕发→近黑、裙摆→苍白肤色、深色布→炭黑），
    # 拿到正式图后同名覆盖 assets/actors/npc/古代生物_卡兹.png 即可。
    ("ancient_kaz", "古代生物_卡兹", "卡兹", "古代生物",
     ["……", "（他没有瞳孔的眼睛扫过来，你听见自己的呼吸被攥住了。）"],
     []),
]


# ---- 初期顾客（雪山线的哈特菲利亚/西蒙/爱德华 + 集市管理员凯瑟琳）----------------
# 只给这四位挂 customer 块：spawner 只认带 customer 的人当顾客，其余 NPC 仍是路人。
# wine_pref 现在全是空的 = 什么酒都按原价收；以后想区分口味就往里填
# {"wine_warm_ginger": 1.4} 这样的倍数（1.0 常规价，<1 压价，>1.4 算"特别喜欢"）。
CUSTOMERS = {
    "explorer_lucy": {
        "budget": 110,
        "greet": ["拜登老板，我想要一壶能扛住山上寒气的酒。",
                  "队员们在雪线下面等着，越快越好。"],
        "bought": ["就是这个味道……暖到骨头里了。",
                   "我记下了，下次还找你。"],
        "leave": ["我先回营地了，路上小心。"],
        "wine_pref": {},
    },
    "miner_simon": {
        "budget": 100,
        "greet": ["拜登老板，来点烈的。",
                  "矿洞里潮，喝淡的没劲。"],
        "bought": ["够劲！这才叫酒。",
                   "下趟我给你带矿上出的好料。"],
        "leave": ["走了，别送。"],
        "wine_pref": {},
    },
    "dwarf_war_edward": {
        "budget": 125,
        "greet": ["听说你这儿的酒有能耐。",
                  "矮人喝酒不兴小口抿。"],
        "bought": ["好酒。盔甲都擦亮了三分。",
                   "我记住了，回头带朋友来。"],
        "leave": ["我回集市那边了。"],
        "wine_pref": {},
    },
    "market_catherine": {
        "budget": 85,
        "greet": ["收摊了，来你这儿歇一脚。",
                  "给我来一杯不烈的。"],
        "bought": ["正好，解乏。",
                   "明天集市有新鲜的，记得来。"],
        "leave": ["我该回去了，账明天再算。"],
        "wine_pref": {},
    },
}


def _placement(p) -> dict:
    """(scene, x, y, facing, wander[, lines]) 或 完整字典 -> placement 字典。

    元组第 6 项可选：该位置专用台词。同一个角色在不同场景说不同的话时用它
    （例：凯瑟琳在集市是摊主口吻，在酒馆是顾客口吻）。没有就用顶层的 lines。

    也可以直接传字典，用于需要扩展字段（wander_rect 矩形游荡区、ghost 不挡路等）
    的位置。字典里只挑已知键，缺的补默认值。
    """
    if isinstance(p, dict):
        d = {"scene": p.get("scene", "world"),
             "pos": list(p.get("pos", [0, 0])),
             "facing": p.get("facing", "down"),
             "wander": p.get("wander", 0.0)}
        for k in ("lines", "wander_rect", "patrol_route", "ghost"):
            if k in p:
                d[k] = p[k]
        return d
    d = {"scene": p[0], "pos": [p[1], p[2]], "facing": p[3], "wander": p[4]}
    if len(p) > 5 and p[5]:
        d["lines"] = list(p[5])
    return d


def main() -> None:
    npcs = []
    for cid, sheet_name, name, title, lines, placements in CHARACTERS:
        entry = {
            "id": cid,
            "name": name,
            "title": title,
            "sheet": SHEET_DIR + sheet_name + ".png",
            "cell": [60, 120],
            "foot": [30, 120],
            "scale": 0.5,
            "lines": lines,
            "placement": [_placement(p) for p in placements],
        }
        if cid in CUSTOMERS:
            entry["customer"] = CUSTOMERS[cid]
        npcs.append(entry)
    data = {"npcs": npcs}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    placed = sum(len(n["placement"]) for n in npcs)
    print(f"{len(npcs)} npc, {placed} placement, {len(CUSTOMERS)} 顾客 -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
