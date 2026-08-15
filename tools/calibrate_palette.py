#!/usr/bin/env python3
"""实物校色管线：用实测颜色更新色卡 JSON 的 rgb/hex。

色卡 JSON 里的 Lab 值在 App 运行时由 rgb 实时计算，因此只需更新 rgb/hex。

用法：
  python tools/calibrate_palette.py \
    --palette lib/core/palettes/mard_221.json \
    --calibration calibration.csv \
    --out lib/core/palettes/mard_221.json

校准文件两种格式：
  CSV（可带表头 code,hex）：
    code,hex
    A01,#FAF4C8
    B07,61,175,128
  JSON：
    {"A01": "#FAF4C8", "B07": [61,175,128]}
"""

import argparse
import csv
import json
import sys


def parse_color(value):
    """解析 '#RRGGBB' / 'r,g,b' / [r,g,b]，返回 (r,g,b,hex)。"""
    if isinstance(value, (list, tuple)):
        r, g, b = int(value[0]), int(value[1]), int(value[2])
        return r, g, b, f"#{r:02X}{g:02X}{b:02X}"
    s = str(value).strip()
    if s.startswith("#"):
        s = s.lstrip("#")
        if len(s) != 6:
            raise ValueError(f"hex 需为 6 位：{value}")
        r, g, b = int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)
        return r, g, b, f"#{s.upper()}"
    parts = [p.strip() for p in s.split(",") if p.strip() != ""]
    if len(parts) != 3:
        raise ValueError(f"无法解析颜色：{value}")
    r, g, b = int(parts[0]), int(parts[1]), int(parts[2])
    return r, g, b, f"#{r:02X}{g:02X}{b:02X}"


def load_calibration(path):
    if path.endswith(".json"):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        out = {}
        for code, v in data.items():
            r, g, b, h = parse_color(v)
            out[code] = (r, g, b, h)
        return out

    out = {}
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or not row[0].strip():
                continue
            if row[0].strip().lower() == "code":
                continue  # 表头
            code = row[0].strip()
            if len(row) == 2:
                r, g, b, h = parse_color(row[1])
            elif len(row) >= 4:
                r, g, b, h = parse_color([row[1], row[2], row[3]])
            else:
                print(f"跳过无法解析的行：{row}", file=sys.stderr)
                continue
            out[code] = (r, g, b, h)
    return out


def main():
    ap = argparse.ArgumentParser(description="实物校色：更新色卡 rgb/hex")
    ap.add_argument("--palette", required=True, help="色卡 JSON 路径")
    ap.add_argument("--calibration", required=True, help="校准 CSV/JSON 路径")
    ap.add_argument("--out", required=True, help="输出 JSON 路径")
    args = ap.parse_args()

    with open(args.palette, encoding="utf-8") as f:
        entries = json.load(f)

    cal = load_calibration(args.calibration)
    by_code = {e["code"]: e for e in entries}

    updated = 0
    for code, (r, g, b, h) in cal.items():
        if code not in by_code:
            print(f"警告：色卡中不存在色号 {code}，已跳过", file=sys.stderr)
            continue
        by_code[code]["rgb"] = [r, g, b]
        by_code[code]["hex"] = h
        updated += 1

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False)

    print(f"完成：更新 {updated}/{len(cal)} 个色号 → {args.out}")


if __name__ == "__main__":
    main()
