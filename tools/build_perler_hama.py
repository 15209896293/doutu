# -*- coding: utf-8 -*-
"""从 maxcleme/beadcolors (MIT) 社区实测数据生成 Perler / Hama 色卡 JSON。

Perler: code 使用短序号 P01..P103（按产品线顺序），productCode 保留官方产品码 80-XXXXX。
Hama:   code 直接使用官方色号 H01..H119。
"""
import json
import os

PERLER_CSV = """
80-15179,#305545,Evergreen
80-15181,#B3BAB8,Light Grey
80-15182,#AF9FCE,Lavender
80-15199,#008F53,Shamrock
80-15200,#0065B1,Cobalt
80-15201,#2F3C55,Midnight
80-15202,#A9CDD5,Robin's Egg
80-15203,#F2AFB7,Flamingo
80-15204,#E1747A,Salmon
80-15205,#C9A385,Fawn
80-15206,#94A19D,Pewter
80-15207,#4F595A,Charcoal
80-15208,#DEDACE,Toasted Marshmallow
80-15210,#B1628E,Orchid
80-15211,#D14337,Tomato
80-15212,#D9593A,Spice
80-15213,#F5A168,Apricot
80-15214,#D8E47C,Sherbet
80-15215,#93B0BD,Mist
80-15216,#4AC0D8,Sky
80-15217,#00A4AC,Lagoon
80-15218,#047F8A,Teal
80-15219,#7F971A,Fern
80-15220,#696E31,Olive
80-15239,#C8B693,Mocha
80-15240,#B3EED5,Mint
80-15241,#A3DE6F,Sour Apple
80-15242,#F479B0,Cotton Candy
80-15243,#503B9C,Grape
80-15244,#D25D72,Rose
80-15245,#4E56A3,Iris
80-15246,#FD5918,Tangerine
80-15247,#005D57,Forest
80-15248,#6F3255,Eggplant
80-15249,#DA8C2C,Honey
80-15250,#7E5446,Gingerbread
80-15251,#8C8CA7,Thistle
80-15252,#5E6D7B,Slate Blue
80-15253,#4C6388,Denim
80-15254,#9AA98E,Sage
80-15255,#EFB79B,Orange Cream
80-15256,#CA3B65,Fruit Punch
80-15257,#CB59B9,Fuchsia
80-15258,#714875,Mulberry
80-15259,#C8C85C,Slime
80-15260,#988C8C,Stone
80-15261,#14313B,Dark Spruce
80-15262,#392928,Cocoa
80-15263,#BED4A6,Celery
80-15265,#C685B1,Twilight Plum
80-15266,#6CC8AD,Caribbean Sea
80-15267,#CDB7C3,Frosted Lilac
80-15268,#DEBA0B,Sunflower
80-15269,#F6D901,Lemon
80-15272,#FF9A8B,Coral
80-15273,#FC9574,Brick
80-15274,#F6CA69,Rich Butter
80-15275,#0090AC,Peacock
80-15276,#F8C7C9,Carnation Pink
80-15089,#406AE1,Neon Blue
80-15961,#9D2B3A,Cherry
80-19001,#EAEFEE,White
80-19002,#E1E2BB,Creme
80-19003,#E7CE3E,Yellow
80-19004,#EB7B31,Orange
80-19005,#B0353C,Red
80-19006,#D8729A,Bubblegum
80-19007,#684B86,Purple
80-19008,#0E5092,Dark Blue
80-19009,#278CC9,Light Blue
80-19010,#007B4E,Dark Green
80-19011,#18C7B1,Light Green
80-19012,#674C44,Brown
80-19017,#909497,Grey
80-19018,#323234,Black
80-19020,#995043,Rust
80-19021,#936848,Light Brown
80-19033,#E9BFB9,Peach
80-19035,#C5AC90,Tan
80-19038,#E04284,Magenta
80-19052,#4A9CCF,Pastel Blue
80-19053,#6DCC94,Pastel Green
80-19054,#937FBF,Pastel Lavender
80-19056,#E9E290,Pastel Yellow
80-19057,#FBB146,Cheddar
80-19058,#96D1D4,Toothpaste
80-19059,#DD595B,Hot Coral
80-19060,#A75D9D,Plum
80-19061,#69B845,Kiwi Lime
80-19062,#0098C5,Turquoise
80-19063,#F99297,Blush
80-19070,#6683B7,Periwinkle
80-19079,#E1BCCE,Light Pink
80-19080,#4DAB64,Green
80-19083,#D45496,Pink
80-19088,#983864,Raspberry
80-19090,#DA9964,Butterscotch
80-19091,#009188,Parrot Green
80-19092,#585C61,Dark Grey
80-19093,#85A8E3,Blueberry Creme
80-19096,#843947,Cranapple
80-19097,#BBC938,Prickly Pear
80-19098,#E5BE9E,Sand
"""

HAMA_CSV = """
H01,#E5ECF1,White
H02,#E4E4C5,Cream
H03,#E9C704,Yellow
H04,#D14803,Orange
H05,#B4060E,Red
H06,#EA8AA5,Pink
H07,#712297,Purple
H08,#0239A3,Blue
H09,#025BC3,Light Blue
H10,#027643,Green
H11,#19CDA7,Light Green
H12,#3E271A,Brown
H13,#C02435,Transp. Red
H14,#E4AA32,Transp. Yellow
H15,#487ED5,Transp. Blue
H16,#37B876,Transp. Green
H17,#838F98,Grey
H18,#141315,Black
H19,#D8D2CE,Clear
H20,#8D2A0F,Reddish Brown
H21,#BE6C21,Light Brown
H22,#91020A,Dark Red
H24,#683E9A,Transp. Purple
H25,#87593D,Transp. Brown
H26,#E8A498,Matt Rose
H27,#DCB18E,Beige
H28,#1E2C1C,Dark Green
H29,#BF0142,Claret
H30,#4E0C1B,Burgundy
H31,#489AB9,Turquoise
H32,#FF208D,Neon Fuchsia
H33,#FF3956,Cerise
H34,#E5EF13,Neon Yellow
H35,#FF2833,Neon Red
H36,#2353B0,Neon Blue
H37,#06B73C,Neon Green
H38,#FD8600,Neon Orange
H39,#F1F21C,Fluor. Yellow
H40,#FE630B,Fluor. Orange
H41,#2659B2,Fluor. Blue
H42,#0CBD51,Fluor. Green
H43,#E7E45A,Pastel Yellow
H44,#F96160,Pastel Red
H45,#8E69CD,Pastel Purple
H46,#51AEE4,Pastel Blue
H47,#80DF96,Pastel Green
H48,#D67AD1,Pastel Pink
H49,#0FACD1,Azure
H55,#FAF8ED,Green (glow)
H56,#EDBF9F,Red (glow)
H57,#C4D0E3,Blue (glow)
H60,#F0981E,Teddybear Brown
H61,#D99350,Gold
H62,#48474A,Silver
H63,#42312F,Bronze
H64,#EFEBE4,Pearl
H70,#A5B3C0,Light Grey
H71,#445059,Dark Grey
H72,#F097B0,Transp. Pink
H73,#59AEF5,Transp. Aqua
H74,#5B55BD,Transp. Lilac
H75,#B78C6D,Tan
H76,#8A5937,Nougat
H77,#CED1C8,Cloudy White
H78,#F7C1AA,Light Peach
H79,#F87633,Apricot
H82,#91175A,Plum
H83,#037A9F,Petrol Blue
H84,#687836,Olive Green
H95,#DD9BA3,Pastel Rose
H96,#B491AD,Pastel Lilac
H97,#8AAFC2,Pastel Ice Blue
H98,#94CCA4,Pastel Mint
H101,#A9C39B,Eucalyptus
H102,#356B2D,Forest Green
H103,#FFE660,Light Yellow
H104,#BCD122,Lime
H105,#FFAC78,Light Apricot
H106,#CCC5ED,Light Lavender
H107,#6A87C1,Lavender
H108,#2A2536,Aubergine
H109,#8A847F,Cloudy Grey
H110,#838956,Matcha
H111,#835854,Dark Blush
H112,#AD8A82,Blush
H113,#5F887B,Aqua
H114,#9A2C31,Cherry Red
H115,#6E975F,Bright Green
H116,#222838,Midnight Blue
H117,#777169,Taupe Grey
H118,#612932,Maroon Red
H119,#4167B4,Sky Blue
"""


def hex_to_rgb(hexv):
    hexv = hexv.lstrip("#")
    return [int(hexv[0:2], 16), int(hexv[2:4], 16), int(hexv[4:6], 16)]


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "lib", "core", "palettes")
    os.makedirs(out_dir, exist_ok=True)

    # Perler: P01..P103 序号 + 官方产品码
    perler = []
    for i, line in enumerate([l for l in PERLER_CSV.strip().split("\n") if l.strip()]):
        code, hexv, name = [x.strip() for x in line.split(",")]
        perler.append({
            "code": f"P{i + 1:02d}",
            "productCode": code,
            "name": name,
            "hex": hexv.upper(),
            "rgb": hex_to_rgb(hexv),
        })
    assert len(perler) == 103, f"perler {len(perler)}"

    # Hama: 官方色号
    hama = []
    for line in [l for l in HAMA_CSV.strip().split("\n") if l.strip()]:
        code, hexv, name = [x.strip() for x in line.split(",")]
        hama.append({
            "code": code,
            "name": name,
            "hex": hexv.upper(),
            "rgb": hex_to_rgb(hexv),
        })
    assert len(hama) == 92, f"hama {len(hama)}"

    with open(os.path.join(out_dir, "perler.json"), "w", encoding="utf-8") as f:
        json.dump(perler, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(out_dir, "hama.json"), "w", encoding="utf-8") as f:
        json.dump(hama, f, ensure_ascii=False, separators=(",", ":"))

    print(f"perler={len(perler)} hama={len(hama)}")
    print("perler sample:", perler[0])
    print("hama sample:", hama[0], hama[-1])


if __name__ == "__main__":
    main()
