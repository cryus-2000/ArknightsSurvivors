"""Q 版半身像素小人，逐人手绘（11-08 用户：照用户给的参考小人格子标准；不要套模板，一个个单独做，保留每名干员的发型和特色）。
用法：python tools/chibi/chibi_grids.py <输出目录> [--install] [--only a,b]
  → 每人 op_<id>_chibi.png（1 格 = 1 像素）+ 总览 preview.png；--install 拷到 game/art/operators/<id>/。
格子：头约 14–16 格宽，整张约 18–20 格宽、17–19 格高（双马尾 / 帽檐 / 角可以伸出头外）；不用黑描边，最深发色当轮廓。
配色取 PRTS 立绘（build/prts_ref/<id>/，有取色表的按 build/prts_ref/_colors）。
分享卡相框左下角的小队成员用（share_card.chibi，外加一格相框描边色轮廓）。
每人：pal 字符 → 颜色；rows 每行一个字符串（短的行右侧补空），'.' = 透明。"""
import sys, os, shutil
from PIL import Image, ImageDraw

SKIN = {"S": "fbe9dc", "B": "f2bdb2", "E": "1e1418"}

CHIBI = {
    # 德克萨斯：深灰长发、狼耳、琥珀眼，黑领 + 白衬衫 + 红斜带
    "texas": {
        "pal": {"D": "23252d", "H": "41485e", "L": "6b7184", "X": "b9a99a", "E": "1a1418", "I": "e08a3c",
                "C": "1c1c22", "W": "f1efec", "G": "c9c6c3", "R": "b5303a", "K": "2a2a30"},
        "rows": [
            ".D............D.", ".DD..........DD.", ".DXD........DXD.", ".DXHDDDDDDDDHXD.", "DHHHHHHLLHHHHHHD", "DHHHLLLHHHHHHHHD",
            "DHHHHHHHHHHDHHHD", "DHHHHHHDSSSSSHHD", "DHHHHHDSESSSESHD", "DHHHHDSSISSSISHD", "DHHDHHSBSSSSSBHD", "DHHDHDSSSSSSSSHD",
            "DHHDDCCCCCCCCDHD", "DHHDWWCCCCCCWWHD", "DHHWWWRWCCWWWWHD", ".DHWGWWRWWWWWGHD", ".DHWGWWWRWWWWGD.", "..DKKKKKKRKKKKD.",
        ],
    },
    # 能天使：酒红短发、淡金光环、琥珀橙眼、小翅膀，黑外套 + 白内衬 + 洋红饰边
    "exusiai": {
        "pal": {"D": "4a1a2a", "H": "8a3350", "L": "b85a78", "Y": "f0d27a", "y": "fff3c8", "E": "2a1418", "I": "cd885e",
                "J": "2a2630", "W": "ece8e4", "G": "bdb6b0", "M": "d92768", "F": "f6e3c0", "K": "1e1c22"},
        "rows": [
            "....yYYYYYYy....", "...YY......YY...", "....YYYYYYYY....", "....DDDDDDDD....", "..DDHHHHHHHHDD..", ".DHHHLLLHHHHHHD.",
            "DHHHLLHHHHHHHHHD", "DHHHHHHHHHHDHHHD", "HDDSSSDHHHHHHHDH", "DHDSESSDHHHHHHHD", "DHDSISSSDHHHHHHD", "DHHBSSSSSBHHDHHD",
            "D.DHSSSSSSHD.HD.", "F.JJJWWWWWWJJJ.F", "FFJJWWMWWWWWJJFF", ".FJJWGWWWWWGJJF.", "..JJWGWWWWWGJJ..", "..JKKKKKKKKKKJ..",
        ],
    },
    # 安洁莉娜：浅棕卷发双马尾、狐耳、红白条纹发箍、红眼、齐刘海；白羽绒外套 + 红夹克 + 黑内衫 + 青色项圈
    "angelina": {
        "pal": {"D": "6f463d", "H": "a17b6f", "L": "c6a59b", "X": "f0d0c4", "R": "c0302a", "w": "f4eee8", "I": "b8433a",
                "C": "2a2422", "T": "3fc0c0", "W": "ece6e0", "G": "c9beb6", "J": "9a2a22", "K": "2a2a30"},
        "rows": [
            "....D..........D....",
            "...DXD........DXD...",
            "...DXXD......DXXD...",
            "...DHXDDDDDDDDXHD...",
            "..DRwRwRwRwRwRwRwD..",
            "..DHHHLLHHHHHHHHHD..",
            ".DHHHHHHHHHHHHHHHHD.",
            "DHHDHHHHHHHHHHHHDHHD",
            "DHHDHSSSSSSSSSSHDHHD",
            "DHHDHSESSSSSSESHDHHD",
            "DHHDHSISSSSSSISHDHHD",
            "DLHDHBSSSSSSSSBHDHLD",
            "DHHHDDSSSSSSSSDDHHHD",
            "DHLHD.CTTTTTTC.DHLHD",
            "DHHHWWJCCCCCCJWWHHHD",
            ".DHHWWJCCCCCCJWWHHD.",
            ".DHDWGJCCCCCCJGWDHD.",
            "..D.WGWJJJJJJWGW.D..",
        ],
    },
    # 艾雅法拉：棕色蓬发 + 呆毛、左上小揪揪（红发圈）、卷曲羊角、粉色垂耳、大粉眼；白褶领 + 黑外套 + 红带
    "eyjafjalla": {
        "pal": {"D": "6b4436", "H": "a06d5c", "L": "c99886", "O": "e2d6c4", "P": "9c8a78", "Q": "f0b0a8", "q": "c47f7a", "r": "d03030",
                "I": "d4687a", "C": "2b2422", "W": "f6eee8", "G": "d5c4bc", "R": "c43a3a", "K": "2a2422"},
        "rows": [
            "........DD..........",
            "..DrD...DHD.........",
            "..DHHDDDDHDDDDDD....",
            ".OODHHHLLHHHHHHHDOO.",
            "OPODHHLLHHHHHHHHDOPO",
            "OOPDHHHHHHHHHHHHDPOO",
            "QOODHDHHHHDHHHDHDOOQ",
            "QQDHHSSDHHSSSDSHHDQQ",
            "qQDHSSESSSSSESSSHDQq",
            ".qDHSSIISSSSIISSHDq.",
            "..DHSBSSSSSSSSBSHD..",
            "..DHHSSSSSSSSSSHHD..",
            "...DHCCWWWWWWCCHD...",
            "...DCCWWRWWWWWCCD...",
            "...CCCWWWRWWWWCCC...",
            "...CCCWGWWRWWGCCC...",
            "...KKKKKKKKKKKKKK...",
        ],
    },
    # 歌蕾蒂娅：宽檐黑帽（斜戴）、银白长发、红眼（露一只），深色礼服 + 白领 + 红胸针
    "gladiia": {
        "pal": {"T": "181824", "t": "3a3a52", "D": "9797a8", "H": "dcdcec", "L": "ffffff", "I": "c4202a",
                "C": "ebebf4", "W": "2b2a38", "G": "181824", "A": "c01828", "K": "10101f"},
        "rows": [
            "..........TT........",
            "......TTTTTTT.......",
            ".....TTtTTTTTT......",
            "....TTtttTTTTTT.....",
            "....TTTTTTTTTTTT....",
            "..TTTTTTTTTTTTTTTTTT",
            "TTTDDDDDDDDDDDDTTT..",
            "..DHHHHHHHHHHHHD....",
            ".DHHHLHHHHHHHDHHD...",
            ".DHHHHHHDSSSSSHHD...",
            ".DHHHHHDSESSSEHHD...",
            ".DHHHHDSSISSSIHHD...",
            ".DHHHHSSBSSSSBHHD...",
            ".DHHHHDSSSSSSSHHD...",
            ".DHHHWWCCCCCCWWHHD..",
            ".DHHWWWCCACCWWWHHD..",
            ".DHHWWGWWWWWWGWWHHD.",
            "..DHKKKKKKKKKKKKHD..",
            "..DH............HD..",
        ],
    },
    # 星熊：墨绿长直发、额侧一只鬼角、侧分刘海、金眼、张嘴笑；黑皮背心
    "hoshiguma": {
        "pal": {"D": "1f3c38", "H": "35665c", "L": "5f9a8a", "O": "f0dfd4", "o": "b8a89c", "I": "d8a73c", "M": "8a2a2a",
                "C": "0f1719", "W": "2b2e30", "G": "1b1c1e", "A": "86aa9a", "K": "0f0f10"},
        "rows": [
            ".............O......",
            "............OO......",
            "....DDDDDDDDoO......",
            "..DDHHHHHHHHHOD.....",
            ".DHHHHLLHHHHHHHD....",
            "DHHHLLHHHHHHHHHHD...",
            "DHHHHHHHHHHHHHDHD...",
            "DHHHHHHHDSSSSSSHD...",
            "DHHHHHHDSESSSESHD...",
            "DHHHHHDSSISSSISHD...",
            "DHHHDHHSSBSSSSBHD...",
            "DHHHDHSSSSSMSSSHD...",
            "DHHHDDSSSSSSSSDHHD..",
            "DHHHHCCCCCCCCCCHHD..",
            "DHHHWWWCCCCCCWWWHHD.",
            "DHHHWGWWWAWWWWGWHHD.",
            "DHHHWGWWWWWWWWGWHHD.",
            ".DHHKKKKKKKKKKKKHHD.",
            ".DHH............HHD.",
        ],
    },
    # 艾丽妮：银灰长发、头顶两只黑色尖饰（往外张）、灰紫眼、颊上红印、碎刘海；白上衣 + 黑领
    "irene": {
        "pal": {"D": "7d7a74", "H": "b8b5ad", "L": "e1dfd6", "T": "272625", "t": "5a5856", "I": "8a7fa0", "R": "c03040",
                "C": "272625", "W": "eae5db", "G": "c2bfb7", "A": "8a2a3a", "K": "2a2a30"},
        "rows": [
            "..T............T....",
            "..TT..........TT....",
            "..TtT.........TtT...",
            "..TttTDDDDDDDTttT...",
            "..TTHHHHHHHHHHTT....",
            ".DHHHHLLLHHHHHHHD...",
            "DHHHLLHHHHHHHHHHHD..",
            "DHHDHHDHHHDHHDHHHD..",
            "DHDSSSDSSSSDSSSSHD..",
            "DHDSESSSSSSSSESSHD..",
            "DHDSISSSSSSSSISSHD..",
            "DHHSBSSSSSSSSBRHHD..",
            "DHHHSSSSSSSSSSHHHD..",
            "DHHHWWWWWWWWWWHHHD..",
            "DHHWWWWCAACWWWWHHD..",
            "DHHWGWWWWWWWWGWHHD..",
            ".DHWGWWWWWWWWGWHD...",
            ".DHKKKKKKKKKKKKHD...",
        ],
    },
    # 凯尔希：浅青白波波头 + 齐刘海、猫耳（深色耳尖、黄绿内耳）、绿眼、黑项圈；露肩白外套 + 青柠色裙
    "kaltsit": {
        "pal": {"D": "9fa27e", "H": "d9dcc0", "L": "f6f7e8", "Q": "403a28", "X": "c8d040", "I": "5a8a2a",
                "C": "060605", "W": "f0f0e0", "G": "c8c8b0", "A": "b8d040", "a": "8fa030", "K": "060605"},
        "rows": [
            "...Q..........Q.....",
            "...QQ........QQ.....",
            "...DXD......DXD.....",
            "...DXHDDDDDDHXD.....",
            "..DHHHHHLLHHHHHD....",
            ".DHHHLLHHHHHHHHHD...",
            ".DHHHHHHHHHHHHHHD...",
            ".DHSSSSSSSSSSSSHD...",
            ".DHSSESSSSSSESSHD...",
            ".DHSSISSSSSSISSHD...",
            ".DHSBSSSSSSSSBSHD...",
            ".DHHSSSSSSSSSSHHD...",
            ".DHHHHHSSSSHHHHHD...",
            "..DHWWSSCCSSWWHD....",
            "..WWWAAAAAAAAWWW....",
            "..WGWAaAAAAaAWGW....",
            "..WGWAAAAAAAAWGW....",
            "..KKKKKKKKKKKKKK....",
        ],
    },
    # 拉普兰德：白色乱翘短发 + 呆毛、狼耳（右耳带黑色发夹）、灰绿眼、右眼一道疤；黑色高领大衣
    "lappland": {
        "pal": {"D": "8f8d8c", "H": "e9e7e6", "L": "ffffff", "X": "3a3838", "k": "1e1d1d", "I": "9ba08a", "R": "c06060",
                "C": "1e1d1d", "W": "3a3939", "G": "292828", "K": "141414"},
        "rows": [
            "........DD..........",
            ".D.....D..D......D..",
            ".DD.....DD......DD..",
            ".DXD..DDDDDDD..DXkD.",
            ".DXHDDHHHHHHHDDHXkD.",
            "DHHHHHLLHHHHHHHHHHD.",
            "DHHLLHHHHHHDHHHHHHHD",
            "DHDHHHDHHHDSDHHHDHHD",
            "DHDSSSSSSSSSSRSSHDHD",
            "DHDSESSSSSSSERSSHDHD",
            "DHDSISSSSSSSIRSSHDHD",
            "DHHSBSSSSSSSBSSHHD..",
            "D.DHCCCCCCCCCCCHD.D.",
            "..DCCCCCCCCCCCCCD...",
            "..CCWWWCCCCCWWWCC...",
            "..CCWGWWWWWWWGWCC...",
            "..CCWGWWWWWWWGWCC...",
            "..KKKKKKKKKKKKKKK...",
        ],
    },
    # 逻各斯：银紫短发、头两侧黑色锯齿状角、尖耳、红眼；黑衣 + 蓝色点缀
    "logos": {
        "pal": {"D": "6f7180", "H": "a9aab7", "L": "d6d7e0", "T": "131315", "t": "3a3a42", "I": "c42a2a",
                "C": "131315", "W": "303032", "G": "1c1c20", "A": "2a7fc0", "K": "040404"},
        "rows": [
            ".T..T........T..T...",
            ".TT.TT......TT.TT...",
            "..TTtT......TtTT....",
            "T..TttTDDDDDTttT..T.",
            "TTTTTDHHHHHHHDTTTTT.",
            ".TTDHHHLLLHHHHHDTT..",
            "..DHHLLHHHHHHHHHHD..",
            "..DHHHDHHHHDHHHDHD..",
            "..DHDSSSDSSSSDSSHD..",
            "..DHSSESSSSSSESSHD..",
            "..DHSSISSSSSSISSHD..",
            "..DHSBSSSSSSSSBSHD..",
            "...DHSSSSSSSSSSHD...",
            "...DCCCSSSSCCCD.....",
            "..CCWWCCCCCCCWWCC...",
            "..CCWGWWAWWWWGWCC...",
            "..CCWGWWWAWWWGWCC...",
            "..KKKKKKKKKKKKKKK...",
        ],
    },
    # 流明：深藏青短发 + 呆毛、发梢渐蓝、浅色鳍状尖耳、橙眼、青色项圈；白羽领 + 白衬衫 + 蓝领巾 + 深色外套
    "lumen": {
        "pal": {"D": "141a24", "H": "26303f", "L": "3b4a60", "U": "3a8ad0", "F": "d8e4ec", "f": "6ea8d0", "I": "d8853a",
                "C": "2a8a8a", "W": "f1f1ef", "w": "ffffff", "J": "2f3a4c", "A": "3a8ad0", "K": "141a24"},
        "rows": [
            ".........D..........",
            "........D...........",
            "....DDDDDDDDD.......",
            "..DDHHHHHHHHHDD.....",
            ".DHHHLLHHHHHHHHD....",
            "DHHLLHHHHHHHHHHHD...",
            "DHHHHHHHHHHHDHHHD...",
            "DHHHHHHDSSSSSDHHD...",
            "FDHHHHDSESSSESHHDF..",
            "FFDHHHDSISSSISHHDFF.",
            "fUDHHHUSSBSSSBHUDUf.",
            ".UUDUHUSSSSSSSUHUU..",
            "..U.UCCCCCCCCUU.....",
            "..JJwwwWWWWwwwJJ....",
            "..JJJwWWAAWWwJJJ....",
            "..JJJWWWAAWWWJJJ....",
            "..JJJWWWWAWWWJJJ....",
            "..KKKKKKKKKKKKKK....",
        ],
    },
    # 水月：浅蓝短发（侧分盖住一只眼）、藏青贝雷帽 + 蓝色水母徽、粉眼；白水手领 + 藏青领 + 黄领带
    "mizuki": {
        "pal": {"T": "1c1f5a", "t": "2a3a9a", "M": "4a8ae0", "D": "6f8aa8", "H": "a8c8e0", "L": "e4f2f8", "I": "e08aa8",
                "C": "2a3ab0", "Y": "e0c040", "W": "f4f6f8", "G": "c1c9d0", "K": "373d5e"},
        "rows": [
            "....TTTTTTTT........",
            "..TTtTTMMTTTTT......",
            ".TTtTTMTTMTTTTT.....",
            ".TTTTTTMMTTTTTTT....",
            "..DDDDDDDDDDDDDD....",
            ".DHHHHLLLHHHHHHHD...",
            "DHHHLLHHHHHHHHHHHD..",
            "DHHDDHHHHHHHHHHHHD..",
            "DHDSSSSSSSDHHHHHHD..",
            "DHDSESSSESDHHHHHHD..",
            "DHDSISSSISSDHHHHHD..",
            "DHHBSSSSSBHHHHDHHD..",
            ".DHHSSSSSSHHDHHD....",
            "..CCCWWWWWWCCC......",
            "..CCWWWYYWWWCC......",
            "..KWWGWWYWWGWWK.....",
            "..KWWGWWWWWGWWK.....",
            "..KKKKKKKKKKKKK.....",
        ],
    },
    # 塞雷娅：银白长发、两侧向后弯的深色龙角（橙色纹）、橙眼；白色高领 + 黑色交叉带 + 橙色条
    "saria": {
        "pal": {"D": "77706f", "H": "c8c0b8", "L": "f0e8de", "O": "4e4040", "o": "7a5a50", "Y": "e06a2a", "I": "d07a3a",
                "C": "ebe1d4", "W": "f0eae2", "G": "c2b9b1", "k": "2a2424", "K": "2a2424"},
        "rows": [
            "...OO........OO.....",
            "..OYO........OYO....",
            "..OoO.DDDDDD.OoO....",
            "..OO.DHHHHHHD.OO....",
            "..ODDHHLLLHHHHDDO...",
            "..DHHLLHHHHHHHHHD...",
            ".DHHHHHHHHHHHHHHHD..",
            ".DHHHDHHHHHHDHHHHD..",
            ".DHHDSSSSSSSSDHHHD..",
            ".DHHDSESSSSESSDHHD..",
            ".DHHDSISSSSISSDHHD..",
            ".DHHDBSSSSSSBSDHHD..",
            ".DHHHDSSSSSSSDHHHD..",
            ".DHHCCCkCCkCCCHHD...",
            ".DHHWWWWkkWWWWHHD...",
            ".DHHWGWkWWkWWGHHD...",
            ".DHHWGkWWWWkWYGHD...",
            "..DHKKKKKKKKKKKHD...",
        ],
    },
    # 推进之王：金棕色蓬乱长发（鬃毛感）、狮耳、琥珀眼、黑项圈；白上衣 + 白毛领 + 黑皮夹克
    "siege": {
        "pal": {"D": "8a6a3a", "H": "c9a66a", "L": "e6cf9a", "X": "6a5030", "I": "c08a30",
                "C": "1b1a1a", "W": "f2efec", "G": "cfc8c0", "F": "efe6d8", "f": "d8cebe", "J": "1b1a1a", "j": "3a3838", "K": "1b1a1a"},
        "rows": [
            "......D.D..D........",
            "..DD.DHDHDDHD.DD....",
            ".DXHDHHHHHHHHDHXD...",
            ".DXHHHHLLLHHHHHXD...",
            "DHHHHLLHHHHHHHHHHD..",
            "DHHHHHHHHHHHHHHHHHD.",
            "DHHDHHHDHHHHDHHHDHD.",
            "DHHHDSDSSSSSDSDHHHHD",
            "DHHHDSESSSSESSDHHHHD",
            "DHHHDSISSSSISSDHHHHD",
            "HHHHDBSSSSSSBSDHHHHH",
            "HDHHHDSSSSSSSDHHHDHD",
            "D.DHHHSSSCSSSHHHD.D.",
            ".FFFFFSSSSSSSFFFFF..",
            "JFFfFWWWWWWWWWFfFFJ.",
            "JJjFWWGWWWWWGWFjJJ..",
            "JJjJWWGWWWWWGWJjJJ..",
            ".JJJKKKKKKKKKKJJJ...",
        ],
    },
    # 斯卡蒂：黑色宽檐帽（帽檐下蓝色、帽上三块白菱形）、灰色长发 + 刘海中间一缕白、红眼
    "skadi": {
        "pal": {"T": "1a1c22", "U": "1b6287", "w": "f4f4f4", "D": "6a6868", "H": "a09e9e", "L": "d8d6d6", "Z": "f8f8f8", "I": "d01818",
                "C": "2a2a30", "W": "383538", "G": "262628", "A": "7a2a3a", "K": "1a1a1e"},
        "rows": [
            ".......TTTTT........",
            ".....TTTTTTTTT......",
            "....TTwTTwTTwTT.....",
            "...TTTTTTTTTTTTT....",
            "UUTTTTTTTTTTTTTTTTT.",
            ".UUUUDDDDDDDDDDDTTTT",
            "...DHHHHHZHHHHHD....",
            "..DHHHHHZZZHHHHHD...",
            "..DHHHHDZZZDHHHHD...",
            "..DHHDSSDZDSSDHHD...",
            "..DHDSESSSSSESDHD...",
            "..DHDSISSSSSISDHD...",
            "..DHDBSSSSSSSBDHD...",
            "..DHHDSSSSSSSDHHD...",
            "..DHHCCWWWWWCCHHD...",
            "..DHCCWWAWWWWCCHD...",
            "..DHCCWGWWWWGCCHD...",
            "..DHKKKKKKKKKKKHD...",
            "..DH.........HD.....",
        ],
    },
    # 浊心斯卡蒂：斜戴的黑色尖顶女巫帽（青绿帽饰 + 冠饰）、银白长发、红眼；露肩红裙 + 黑项圈
    "skalter": {
        "pal": {"T": "1a1a1e", "t": "2e8a7a", "Y": "8aaac8", "D": "6e6f71", "H": "b4b6b8", "L": "ece6e4", "I": "c0202a",
                "C": "1a1a1e", "R": "ae282f", "r": "7a161c", "K": "3a0e10"},
        "rows": [
            "......T.............",
            ".....TT.......Y.Y...",
            ".....TTT.....tYYY...",
            "......TTTTTTtttt....",
            ".....TTTTTTTtTTTT...",
            "...TTTTTTTTTTTTTTTT.",
            "....DDDDDDDDDDDDD...",
            "...DHHHHLLHHHHHHHD..",
            "..DHHHLLHHHHHHHHHHD.",
            "..DHHHHDHHHHDHHHHHD.",
            "..DHHDSSSSSSSSDHHHD.",
            "..DHHDSESSSSESDHHHD.",
            "..DHHDSISSSSISDHHHD.",
            "..DHHDBSSSSSSBDHHHD.",
            "..DHHHDSSSSSSDHHHHD.",
            "..DHHSSSSCCSSSSHHHD.",
            "..DHRRRRrCCrRRRRHHD.",
            "..DHRRRRRrrRRRRRHHD.",
            "..DHKKKKKKKKKKKKHHD.",
        ],
    },
    # 归溟幽灵鲨：白色海盗帽（黑色帽带与饰物）、银白长发、红眼；黑衣 + 白扣 + 蓝色腰带
    "specter_unchained": {
        "pal": {"T": "e8e2dc", "t": "b8b2ac", "k": "1e1e24", "D": "6a7484", "H": "b0b4b8", "L": "e8e2dc", "I": "c0303a",
                "C": "e8e2dc", "W": "252a37", "G": "14151b", "A": "2a5ab0", "K": "09080c"},
        "rows": [
            "..........kk.k......",
            "......TTTTkkkTT.....",
            "....TTTTTTTTkTTTT...",
            "..TTTTkkkkkkkkkTTTT.",
            ".TtTTTTTTTTTTTTTTtT.",
            "Tt..DDDDDDDDDDD..tT.",
            "...DHHHHLLHHHHHD....",
            "..DHHHLLHHHHHHHHD...",
            "..DHHHHHHHDHHHHHD...",
            "..DHHDSSSSDSSSDHD...",
            "..DHDSESSSSSESDHD...",
            "..DHDSISSSSSISDHD...",
            "..DHDBSSSSSSSBDHD...",
            "..DHHDSSSSSSSDHHD...",
            "..DHHWCCCCCCCWHHD...",
            "..DHWWWWCWWWWWWHD...",
            "..DHWAAAAAWWWWWHD...",
            "..DHKKKKKKKKKKKHD...",
            "..DH.........HD.....",
        ],
    },
    # 铃兰：浅金发、大狐耳（粉色内耳）、浅蓝发箍、齐刘海、绿眼、侧边小辫；米白衣 + 蓝色点缀
    "suzuran": {
        "pal": {"D": "b09858", "H": "e8d29a", "L": "fbf3d0", "X": "f4c8c8", "U": "4a9ad8", "I": "8ab83a",
                "C": "ccc9b8", "W": "fbf7e4", "G": "dfccaf", "A": "4a9ad8", "K": "8e9186"},
        "rows": [
            "...D............D...",
            "...DD..........DD...",
            "...DXD........DXD...",
            "...DXXD......DXXD...",
            ".DDDXXHDDDDDDHXXDDD.",
            ".DHUUUUUUUUUUUUUUHD.",
            ".DHHHHLLLHHHHHHHHHD.",
            ".DHHLLHHHHHHHHHHHHD.",
            ".DHHHHHHHHHHHHHHHHD.",
            ".DHHSSSSSSSSSSSSHHD.",
            ".DHHSSESSSSSSESSHHD.",
            ".DHHSSISSSSSSISSHHD.",
            ".DHHSBSSSSSSSSBSHHD.",
            ".DHHHSSSSSSSSSSHHHD.",
            "..DHHCWWWWWWWWCHHD..",
            "..DLHWWWAAAWWWWHD...",
            "..DLDWGWWAWWWGWD....",
            "...LDKKKKKKKKKKD....",
            "...L................",
        ],
    },
    # 乌尔比安：黑色大帽（左侧蓝色鳍状帽檐 + 红色鳍饰）、灰发、红眼、下半脸黑面罩；黑衣
    "ulpianus": {
        "pal": {"T": "2b2c34", "U": "1e4a6a", "u": "2f6a90", "R": "9a1030", "D": "65696d", "H": "9a928a", "L": "c8beb5", "I": "c01020",
                "M": "15181d", "C": "15181d", "W": "2b2c34", "G": "15181d", "A": "820d2e", "K": "0f0f12"},
        "rows": [
            "..........R.........",
            ".........RR.........",
            "......TTTRRTTT......",
            ".....TTTTRTTTTT.....",
            "UU..TTTTTTTTTTTTT...",
            ".UUuTTTTTTTTTTTTTTT.",
            "..UUUuuTTTTTTTTTTTTT",
            "....DDDDDDDDDDDD....",
            "...DHHHHLLHHHHHHD...",
            "..DHHHHHHHHDHHHHHD..",
            "..DHHDSSSSDSSSSDHD..",
            "..DHDSESSSSSSESDHD..",
            "..DHDSISSSSSSISDHD..",
            "..DHDMMMMMMMMMMDHD..",
            "...DDMMMMMMMMMMDD...",
            ".CCCCWWWWWWWWWWCCCC.",
            ".CCCWWGWWAAWWGWWCCC.",
            ".KKKKKKKKKKKKKKKKKK.",
        ],
    },
    # 维什戴尔：断开的暗红光环、一对黑色小角、银白乱发、橙红眼、咧嘴笑；红外套 + 黑内衣
    "wisadel": {
        "pal": {"R": "b02028", "r": "e04848", "T": "1a1618", "D": "7a7676", "H": "d4d0d0", "L": "f4f2f2", "I": "e0702a",
                "C": "191718", "W": "b82028", "w": "801820", "G": "2a2628", "K": "191718"},
        "rows": [
            "....rRRR..RRRr......",
            "...R..........R.....",
            "....RRRR..RRRR......",
            "..T....DDDDD....T...",
            "..TT.DDHHHHHDD.TT...",
            "...TDHHHLLHHHHDT....",
            "...DHHLLHHHHHHHD....",
            "..DHHHHDHHHHHDHHHD..",
            "..DHHDSSDSSSSDSHHD..",
            "..DHDSESSSSSSESDHD..",
            "..DHDSISSSSSSISDHD..",
            "..DHDBSSSCCSSSBDHD..",
            "..DHHDSSSSSSSSDHHD..",
            "..DHWWCCCCCCCCWWHD..",
            ".DHWWWwCCCCCCwWWWHD.",
            ".DHWwWWGGGGGGWWwWHD.",
            ".DHWwWWGGGGGGWWwWHD.",
            "..DKKKKKKKKKKKKKKD..",
        ],
    },
}


MIRROR = {"exusiai", "mizuki"}            # 原来朝左的，先整体翻成朝右
SCAR = {"lappland": "R"}                  # 眼上下各一格疤
ONE_EYE = {"exusiai"}                     # 原作刘海就遮着一只眼的；其余双眼（11-08 用户：参考图是遮一只眼，但别每个人都只露一只；水月也是双眼）
NARROW = {"ulpianus"}                     # 细长眼 + 眉（男性干员，11-08 用户：乌尔比安像女生）


def face_right(op, rows):
    """11-08 用户：全员跟德克萨斯一样朝右、眼睛要看得见——脸统一改成朝右的 3/4 侧脸：
    刘海从左上斜盖下来，只露右边一只 2 × 2 的大眼（上瞳孔、下瞳色），右颊腮红；发型 / 头饰 / 面罩 / 嘴不动。"""
    rows = [list(r) for r in rows]
    w = max(len(r) for r in rows)
    for r in rows:
        r.extend("." * (w - len(r)))
    if op in MIRROR:
        rows = [r[::-1] for r in rows]
    ey = next(i for i, r in enumerate(rows) if "E" in r)
    if op not in ONE_EYE:
        return eyes_only(op, rows, ey)
    block = range(ey - 1, ey + 3)
    xs = [x for y in list(block) + [ey + 3] for x, ch in enumerate(rows[y]) if ch in "SBEI"]
    a, b = min(xs), max(xs)
    face = set("SBEIHDL")

    def put(y, x, ch):
        if a <= x <= b and rows[y][x] in face:
            rows[y][x] = ch

    two = op not in ONE_EYE
    plan = [  # 每行：刘海盖到哪一格（D 为刘海边），之后是皮肤；双眼的刘海只盖额头，露出远处那只眼
        (ey - 1, b - 2 if not two else b - 7),
        (ey, b - 4 if not two else b - 7),
        (ey + 1, b - 5 if not two else b - 8),
        (ey + 2, b - 7 if not two else b - 9),
    ]
    for y, edge in plan:
        if not any(ch in "SBEI" for ch in rows[y]) and y != ey - 1:
            continue   # 整行是面罩（乌尔比安）
        for x in range(a, b + 1):
            if x < edge:
                put(y, x, "H")
            elif x == edge:
                put(y, x, "D")
            else:
                put(y, x, "S")
    put(ey, b - 2, "E"); put(ey, b - 1, "E")
    put(ey + 1, b - 2, "I"); put(ey + 1, b - 1, "I")
    if two:   # 远处那只眼：同样 2 × 2（11-08 用户：两只眼大小要一样），贴着刘海边，两眼间隔 2 格
        put(ey, b - 6, "E"); put(ey, b - 5, "E")
        put(ey + 1, b - 6, "I"); put(ey + 1, b - 5, "I")
    if op in NARROW:   # 细长眼：眼位上一行画眉，眼只留一行瞳色
        for x in ([b - 2, b - 1] + ([b - 6, b - 5] if two else [])):
            rows[ey - 1][x] = "D" if rows[ey - 1][x] in face else rows[ey - 1][x]
            rows[ey][x] = "I"
            rows[ey + 1][x] = "S"
    if any(ch == "S" for ch in rows[ey + 2]) and op not in NARROW:
        put(ey + 2, b - 6 if two else b - 5, "B"); put(ey + 2, b, "B")
    if op in SCAR:
        for y in (ey - 1, ey + 2):
            if rows[y][b - 1] in face:
                rows[y][b - 1] = SCAR[op]
    return ["".join(r) for r in rows]


def eyes_only(op, rows, ey):
    """双眼的干员：刘海保留各自手绘的样子（11-08 用户：刘海不要全都化成齐刘海），只在原来的脸上
    重放两只同样 2 × 2 的眼（偏右的 3/4 朝向，两眼间隔 2 格）和腮红；眼位被头发挡住的格子挖成皮肤。"""
    for y in (ey, ey + 1):
        rows[y] = ["S" if ch in "EI" else ch for ch in rows[y]]
    # 11-08 用户：眼挤在右边、左边空一块很怪——两眼按脸的实际宽度居中（脸 = 眼那一行与下一行的皮肤格）
    xs = [x for y in (ey, ey + 1) for x, ch in enumerate(rows[y]) if ch in "SB"]
    # 11-08 用户：都要往右看、透视别乱——两眼整体偏右 1 格（3/4 朝右），近侧（左）鬓发在眼那两行往里垂下盖住空出的脸颊
    lo = min(xs)
    c = min((lo + max(xs) + 1) // 2 + 1, max(xs) - 2)   # 近眼不出脸的右边缘（德克萨斯 / 星熊脸窄）
    far, near = [c - 3, c - 2], [c + 1, c + 2]
    b = near[1] + 1
    for y in (ey, ey + 1):
        for x in range(c - 3, c + 3):
            rows[y][x] = "S"
        for x in range(lo, far[0] - 2):
            rows[y][x] = "H" if x < far[0] - 3 else "D"
    if op in NARROW:   # 细长眼：上一行画眉，眼只留一行瞳色
        for x in near + far:
            rows[ey - 1][x] = "D"
            rows[ey][x] = "I"
    else:
        for x in near + far:
            rows[ey][x] = "E"
            rows[ey + 1][x] = "I"
    if op not in NARROW and ey + 2 < len(rows):
        for x in (far[0] - 1, near[1] + 1):
            if rows[ey + 2][x] == "S":
                rows[ey + 2][x] = "B"
    if op in SCAR:
        for y in (ey - 1, ey + 2):
            rows[y][b - 1] = SCAR[op]
    return ["".join(r) for r in rows]


def widen_eyes(op, rows):
    """11-08 用户：脸型和发型都还原成逐人手绘的样子（不再统一改朝向）；为了看得清、两眼一样大，
    每只眼只在原位横向加宽成 2 × 2（上瞳孔、下瞳色），往旁边的皮肤格加宽。乌尔比安细长眼 + 眉。"""
    rows = [list(r) for r in rows]
    w = max(len(r) for r in rows)
    for r in rows:
        r.extend("." * (w - len(r)))
    ey = next(i for i, r in enumerate(rows) if "E" in r)
    cols = [x for x, ch in enumerate(rows[ey]) if ch == "E"]
    for x in cols:
        dx = 1 if x + 1 < w and rows[ey][x + 1] == "S" and rows[ey + 1][x + 1] in "SI" else -1
        for xx in (x, x + dx):
            rows[ey][xx] = "E"
            rows[ey + 1][xx] = "I"
    if op in NARROW:
        for x in range(w):
            if rows[ey][x] == "E":
                rows[ey - 1][x] = "D"
                rows[ey][x] = "I"
                rows[ey + 1][x] = "S"
    return ["".join(r) for r in rows]


def render(op):
    d = CHIBI[op]
    rows = widen_eyes(op, d["rows"])
    w = max(len(r) for r in rows)
    pal = dict(SKIN)
    pal.update(d["pal"])
    im = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch == ".":
                continue
            if ch not in pal:
                raise SystemExit("%s：第 %d 行字符 %s 没有配色" % (op, y, ch))
            h = pal[ch]
            im.putpixel((x, y), (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255))
    return im.crop(im.getbbox())


if __name__ == "__main__":
    out = sys.argv[1]
    install = "--install" in sys.argv
    only = None
    for a in sys.argv:
        if a.startswith("--only="):
            only = a[7:].split(",")
    os.makedirs(out, exist_ok=True)
    ops = [o for o in CHIBI if not only or o in only]
    tiles = []
    for op in ops:
        im = render(op)
        p = os.path.join(out, "op_%s_chibi.png" % op)
        im.save(p)
        if install:
            dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "art", "operators", op)
            if os.path.isdir(dst):
                shutil.copy(p, os.path.join(dst, "op_%s_chibi.png" % op))
        big = im.resize((im.size[0] * 10, im.size[1] * 10), Image.NEAREST)
        bg = Image.new("RGBA", (240, 240), (205, 225, 245, 255))
        bg.alpha_composite(big, ((240 - big.size[0]) // 2, 240 - big.size[1] - 6))
        tiles.append((op, bg))
    cols = 5
    o = Image.new("RGB", (cols * 250 + 10, ((len(tiles) + cols - 1) // cols) * 270 + 10), (60, 62, 68))
    dr = ImageDraw.Draw(o)
    for i, (op, t) in enumerate(tiles):
        x, y = 10 + (i % cols) * 250, 10 + (i // cols) * 270
        o.paste(t, (x, y + 20))
        dr.text((x + 2, y + 4), op, fill=(230, 230, 230))
    o.save(os.path.join(out, "preview.png"))
    print("ok", len(tiles))
