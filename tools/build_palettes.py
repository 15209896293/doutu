# -*- coding: utf-8 -*-
"""从公开参考仓库数据生成 MARD 色卡 JSON。

数据来源：
- Jett-Wu/Perler_Beads_Generator (MIT)  src/palette.ts  —— MARD 基础 221 色 + 扩展 70 色
- Zippland/perler-beads (AGPL, 仅事实型色号对照数据, clean-room) —— 色号对照校验

色号格式统一为 3 位（A01），与 dev-plan.md 示例一致。
"""
import json
import os
import sys

BASE_CSV = """
A1,#FAF4C8
A2,#FFFFD5
A3,#FEFF8B
A4,#FBED56
A5,#F4D738
A6,#FEAC4C
A7,#FE8B4C
A8,#FFDA45
A9,#FF995B
A10,#F77C31
A11,#FFDD99
A12,#FE9F72
A13,#FFC365
A14,#FD543D
A15,#FFF365
A16,#FFFF9F
A17,#FFE36E
A18,#FEBE7D
A19,#FD7C72
A20,#FFD568
A21,#FFE395
A22,#F4F57D
A23,#E6C9B7
A24,#F7F8A2
A25,#FFD67D
A26,#FFC830
B1,#E6EE31
B2,#63F347
B3,#9EF780
B4,#5DE035
B5,#35E352
B6,#65E2A6
B7,#3DAF80
B8,#1C9C4F
B9,#27523A
B10,#95D3C2
B11,#5D722A
B12,#166F41
B13,#CAEB7B
B14,#ADE946
B15,#2E5132
B16,#C5ED9C
B17,#9BB13A
B18,#E6EE49
B19,#24B88C
B20,#C2F0CC
B21,#156A6B
B22,#0B3C43
B23,#303A21
B24,#EEFCA5
B25,#4E846D
B26,#8D7A35
B27,#CCE1AF
B28,#9EE5B9
B29,#C5E254
B30,#E2FCB1
B31,#B0E792
B32,#9CAB5A
C1,#E8FFE7
C2,#A9F9FC
C3,#A0E2FB
C4,#41CCFF
C5,#01ACEB
C6,#50AAF0
C7,#3677D2
C8,#0F54C0
C9,#324BCA
C10,#3EBCE2
C11,#28DDDE
C12,#1C334D
C13,#CDE8FF
C14,#D5FDFF
C15,#22C4C6
C16,#1557A8
C17,#04D1F6
C18,#1D3344
C19,#1887A2
C20,#176DAF
C21,#BEDDFF
C22,#67B4BE
C23,#C8E2FF
C24,#7CC4FF
C25,#A9E5E5
C26,#3CAED8
C27,#D3DFFA
C28,#BBCFED
C29,#34488E
D1,#AEB4F2
D2,#858EDD
D3,#2F54AF
D4,#182A84
D5,#B843C5
D6,#AC7BDE
D7,#8854B3
D8,#E2D3FF
D9,#D5B9F8
D10,#361851
D11,#B9BAE1
D12,#DE9AD4
D13,#B90095
D14,#8B279B
D15,#2F1F90
D16,#E3E1EE
D17,#C4D4F6
D18,#A45EC7
D19,#D8C3D7
D20,#9C32B2
D21,#9A009B
D22,#333A95
D23,#EBDAFC
D24,#7786E5
D25,#494FC7
D26,#DFC2F8
E1,#FDD3CC
E2,#FEC0DF
E3,#FFB7E7
E4,#E8649E
E5,#F551A2
E6,#F13D74
E7,#C63478
E8,#FFDBE9
E9,#E970CC
E10,#D33793
E11,#FCDDD2
E12,#F78FC3
E13,#B5006D
E14,#FFD1BA
E15,#F8C7C9
E16,#FFF3EB
E17,#FFE2EA
E18,#FFC7DB
E19,#FEBAD5
E20,#D8C7D1
E21,#BD9DA1
E22,#B785A1
E23,#937A8D
E24,#E1BCE8
F1,#FD957B
F2,#FC3D46
F3,#F74941
F4,#FC283C
F5,#E7002F
F6,#943630
F7,#971937
F8,#BC0028
F9,#E2677A
F10,#8A4526
F11,#5A2121
F12,#FD4E6A
F13,#F35744
F14,#FFA9AD
F15,#D30022
F16,#FEC2A6
F17,#E69C79
F18,#D37C46
F19,#C1444A
F20,#CD9391
F21,#F7B4C6
F22,#FDC0D0
F23,#F67E66
F24,#E698AA
F25,#E54B4F
G1,#FFE2CE
G2,#FFC4AA
G3,#F4C3A5
G4,#E1B383
G5,#EDB045
G6,#E99C17
G7,#9D5B3E
G8,#753832
G9,#E6B483
G10,#D98C39
G11,#E0C593
G12,#FFC890
G13,#B7714A
G14,#8D614C
G15,#FCF9E0
G16,#F2D9BA
G17,#78524B
G18,#FFE4CC
G19,#E07935
G20,#A94023
G21,#B88558
H1,#FDFBFF
H2,#FEFFFF
H3,#B6B1BA
H4,#89858C
H5,#48464E
H6,#2F2B2F
H7,#000000
H8,#E7D6DB
H9,#EDEDED
H10,#EEE9EA
H11,#CECDD5
H12,#FFF5ED
H13,#F5ECD2
H14,#CFD7D3
H15,#98A6A8
H16,#1D1414
H17,#F1EDED
H18,#FFFDF0
H19,#F6EFE2
H20,#949FA3
H21,#FFFBE1
H22,#CACAD4
H23,#9A9D94
M1,#BCC6B8
M2,#8AA386
M3,#697D80
M4,#E3D2BC
M5,#D0CCAA
M6,#B0A782
M7,#B4A497
M8,#B38281
M9,#A58767
M10,#C5B2BC
M11,#9F7594
M12,#644749
M13,#D19066
M14,#C77362
M15,#757D78
"""

EXTENDED_CSV = """
P1,#FCF7F8
P2,#B0A9AC
P3,#AFDCAB
P4,#FEA49F
P5,#EE8C3E
P6,#5FD0A7
P7,#EB9270
P8,#F0D958
P9,#D9D9D9
P10,#D9C7EA
P11,#F3ECC9
P12,#E6EEF2
P13,#AACBEF
P14,#337680
P15,#668575
P16,#FEBF45
P17,#FEA324
P18,#FEB89F
P19,#FFFEEC
P20,#FEBECF
P21,#ECBEBF
P22,#E4A89F
P23,#A56268
Q1,#F2A5E8
Q2,#E9EC91
Q3,#FFFF00
Q4,#FFEBFA
Q5,#76CEDE
R1,#D50D21
R2,#F92F83
R3,#FD8324
R4,#F8EC31
R5,#35C75B
R6,#238891
R7,#19779D
R8,#1A60C3
R9,#9A56B4
R10,#FFDB4C
R11,#FFEBFA
R12,#D8D5CE
R13,#55514C
R14,#9FE4DF
R15,#77CEE9
R16,#3ECFCA
R17,#4A867A
R18,#7FCD9D
R19,#CDE55D
R20,#E8C7B4
R21,#AD6F3C
R22,#6C372F
R23,#FEB872
R24,#F3C1C0
R25,#C9675E
R26,#D293BE
R27,#EA8CB1
R28,#9C87D6
T1,#FFFFFF
Y1,#FD6FB4
Y2,#FEB481
Y3,#D7FAA0
Y4,#8BDBFA
Y5,#E987EA
ZG1,#DAABB3
ZG2,#D6AA87
ZG3,#C1BD8D
ZG4,#96869F
ZG5,#8490A6
ZG6,#94BFE2
ZG7,#E2A9D2
ZG8,#AB91C0
"""


def parse(csv_text):
    entries = []
    for line in csv_text.strip().split("\n"):
        line = line.strip()
        if not line:
            continue
        code, hexv = line.split(",")
        code, hexv = code.strip(), hexv.strip().lstrip("#")
        r, g, b = int(hexv[0:2], 16), int(hexv[2:4], 16), int(hexv[4:6], 16)
        entries.append((code, hexv.upper(), [r, g, b]))
    return entries


def norm_code(code):
    """A1 -> A01；ZG1 -> ZG1；P12 -> P12。统一：字母 + 2 位数字。"""
    import re
    m = re.match(r"^([A-Za-z]+)(\d+)$", code)
    assert m, f"unexpected code {code}"
    return f"{m.group(1)}{int(m.group(2)):02d}"


def build(entries):
    out = []
    seen = set()
    for code, hexv, rgb in entries:
        ncode = norm_code(code)
        assert ncode not in seen, f"dup {ncode}"
        seen.add(ncode)
        out.append({"code": ncode, "hex": "#" + hexv, "rgb": rgb})
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "lib", "core", "palettes")
    os.makedirs(out_dir, exist_ok=True)

    base = build(parse(BASE_CSV))
    ext = build(parse(EXTENDED_CSV))
    full = base + ext

    assert len(base) == 221, f"base count {len(base)} != 221"
    assert len(full) == 291, f"full count {len(full)} != 291"

    with open(os.path.join(out_dir, "mard_221.json"), "w", encoding="utf-8") as f:
        json.dump(base, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(out_dir, "mard_291.json"), "w", encoding="utf-8") as f:
        json.dump(full, f, ensure_ascii=False, separators=(",", ":"))

    # 校验：221 色与 Zippland 映射一致（抽取其中 MARD 221 组）
    zipp = {
        "#FAF4C8": "A01", "#FFFFD5": "A02", "#FEFF8B": "A03", "#FBED56": "A04",
        "#F4D738": "A05", "#FEAC4C": "A06", "#FE8B4C": "A07", "#FFDA45": "A08",
        "#FF995B": "A09", "#F77C31": "A10", "#FFDD99": "A11", "#FE9F72": "A12",
        "#FFC365": "A13", "#FD543D": "A14", "#FFF365": "A15", "#FFFF9F": "A16",
        "#FFE36E": "A17", "#FEBE7D": "A18", "#FD7C72": "A19", "#FFD568": "A20",
        "#FFE395": "A21", "#F4F57D": "A22", "#E6C9B7": "A23", "#F7F8A2": "A24",
        "#FFD67D": "A25", "#FFC830": "A26",
    }
    for entry in base:
        if entry["hex"] in zipp:
            assert entry["code"] == zipp[entry["hex"]], (
                f"mismatch {entry['hex']}: {entry['code']} vs {zipp[entry['hex']]}")

    print(f"base={len(base)} full={len(full)}")
    print("sample:", base[0], base[-1])


if __name__ == "__main__":
    main()
