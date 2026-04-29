#!/usr/bin/env python3
"""
영수증 이미지를 A4 PDF로 합치는 스크립트.
JSON 설정 파일을 입력받아 월별/종류별로 A4 PDF 생성.

사용법:
    python3 combine_receipts.py config.json

config.json 형식:
{
  "src_dir": "/path/to/receipt/images",
  "out_dir": "/path/to/output",
  "pairs_per_page": 4,
  "groups": {
    "택시_2026년1월": {
      "title": "택시 영수증 — 2026년 1월",
      "pairs": [
        {
          "left": "file1.jpeg",
          "right": "file2.jpeg",
          "date": "01.14",
          "amount": "19,900원"
        }
      ]
    }
  }
}

left/right 없이 singles로도 가능:
{
  "groups": {
    "식비_1월": {
      "title": "식비 — 2026년 1월",
      "singles": [
        { "file": "receipt.jpeg", "date": "01.05", "amount": "12,000원" }
      ]
    }
  }
}
"""

import json
import math
import os
import sys
from PIL import Image, ImageDraw, ImageFont

# A4 300DPI
A4_W, A4_H = 2480, 3508
MARGIN = 50
COL_GAP = 30
ROW_GAP = 30
PAIR_GAP = 10
HEADER_H = 90
LABEL_H = 50
BG = (255, 255, 255)
HEADER_BG = (45, 50, 65)
HEADER_FG = (255, 255, 255)

# Fonts
def load_fonts():
    paths = [
        "/System/Library/Fonts/AppleSDGothicNeo.ttc",
        "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    ]
    for p in paths:
        if os.path.exists(p):
            return (
                ImageFont.truetype(p, 44),
                ImageFont.truetype(p, 26),
                ImageFont.truetype(p, 20),
            )
    f = ImageFont.load_default()
    return f, f, f

FONT_H, FONT_D, FONT_S = load_fonts()


def fit(img, max_w, max_h):
    r = min(max_w / img.width, max_h / img.height)
    return img.resize((int(img.width * r), int(img.height * r)), Image.LANCZOS)


def make_pair_pages(pairs, title, src_dir, per_page=4):
    """각 항목이 left+right 쌍인 경우 (거래확인증+이용상세 등)."""
    cols = 2
    rows = per_page // cols

    usable_w = A4_W - 2 * MARGIN
    usable_h = A4_H - HEADER_H - 2 * MARGIN
    cell_w = (usable_w - COL_GAP * (cols - 1)) // cols
    cell_h = (usable_h - ROW_GAP * (rows - 1)) // rows
    each_img_w = (cell_w - PAIR_GAP) // 2

    num_pages = math.ceil(len(pairs) / per_page)
    pages = []

    for pi in range(num_pages):
        page = Image.new("RGB", (A4_W, A4_H), BG)
        draw = ImageDraw.Draw(page)

        # Header
        draw.rectangle([(0, 0), (A4_W, HEADER_H)], fill=HEADER_BG)
        label = f"{title}  ({pi + 1}/{num_pages})"
        bb = draw.textbbox((0, 0), label, font=FONT_H)
        draw.text(((A4_W - bb[2] + bb[0]) // 2, (HEADER_H - bb[3] + bb[1]) // 2),
                  label, fill=HEADER_FG, font=FONT_H)

        chunk = pairs[pi * per_page:(pi + 1) * per_page]

        for i, item in enumerate(chunk):
            col = i % cols
            row = i // cols
            cx = MARGIN + col * (cell_w + COL_GAP)
            cy = HEADER_H + MARGIN + row * (cell_h + ROW_GAP)

            # Date/amount label
            date_str = item.get("date", "")
            amount = item.get("amount", "")
            dlabel = f"2026.{date_str}  {amount}" if date_str else amount
            bb = draw.textbbox((0, 0), dlabel, font=FONT_D)
            draw.rounded_rectangle([(cx, cy), (cx + cell_w, cy + LABEL_H - 5)],
                                   radius=8, fill=(245, 245, 248))
            draw.text((cx + (cell_w - bb[2] + bb[0]) // 2, cy + 10),
                      dlabel, fill=(40, 40, 40), font=FONT_D)

            # Sub labels
            sl_y = cy + LABEL_H
            for j, sl_text in enumerate(["거래확인증", "이용상세"]):
                bb_s = draw.textbbox((0, 0), sl_text, font=FONT_S)
                x_off = j * (each_img_w + PAIR_GAP)
                draw.text((cx + x_off + (each_img_w - bb_s[2]) // 2, sl_y),
                          sl_text, fill=(150, 150, 150), font=FONT_S)

            img_y = sl_y + 28
            img_max_h = cell_h - LABEL_H - 28

            for j, key in enumerate(["left", "right"]):
                fpath = os.path.join(src_dir, item[key])
                if os.path.exists(fpath):
                    img = fit(Image.open(fpath), each_img_w, img_max_h)
                    x = cx + j * (each_img_w + PAIR_GAP) + (each_img_w - img.width) // 2
                    page.paste(img, (x, img_y))

            draw.rectangle([(cx - 5, cy - 5), (cx + cell_w + 5, cy + cell_h + 5)],
                          outline=(230, 230, 230), width=1)

        pages.append(page)
    return pages


def make_single_pages(singles, title, src_dir, per_page=6):
    """각 항목이 단일 이미지인 경우."""
    cols = 3
    rows = per_page // cols

    usable_w = A4_W - 2 * MARGIN
    usable_h = A4_H - HEADER_H - 2 * MARGIN
    cell_w = (usable_w - COL_GAP * (cols - 1)) // cols
    cell_h = (usable_h - ROW_GAP * (rows - 1)) // rows

    num_pages = math.ceil(len(singles) / per_page)
    pages = []

    for pi in range(num_pages):
        page = Image.new("RGB", (A4_W, A4_H), BG)
        draw = ImageDraw.Draw(page)

        draw.rectangle([(0, 0), (A4_W, HEADER_H)], fill=HEADER_BG)
        label = f"{title}  ({pi + 1}/{num_pages})"
        bb = draw.textbbox((0, 0), label, font=FONT_H)
        draw.text(((A4_W - bb[2] + bb[0]) // 2, (HEADER_H - bb[3] + bb[1]) // 2),
                  label, fill=HEADER_FG, font=FONT_H)

        chunk = singles[pi * per_page:(pi + 1) * per_page]

        for i, item in enumerate(chunk):
            col = i % cols
            row = i // cols
            cx = MARGIN + col * (cell_w + COL_GAP)
            cy = HEADER_H + MARGIN + row * (cell_h + ROW_GAP)

            date_str = item.get("date", "")
            amount = item.get("amount", "")
            dlabel = f"{date_str}  {amount}" if date_str else amount
            bb = draw.textbbox((0, 0), dlabel, font=FONT_D)
            draw.rounded_rectangle([(cx, cy), (cx + cell_w, cy + LABEL_H - 5)],
                                   radius=8, fill=(245, 245, 248))
            draw.text((cx + (cell_w - bb[2] + bb[0]) // 2, cy + 10),
                      dlabel, fill=(40, 40, 40), font=FONT_D)

            img_y = cy + LABEL_H + 5
            img_max_h = cell_h - LABEL_H - 5

            fpath = os.path.join(src_dir, item["file"])
            if os.path.exists(fpath):
                img = fit(Image.open(fpath), cell_w, img_max_h)
                page.paste(img, (cx + (cell_w - img.width) // 2, img_y))

            draw.rectangle([(cx - 5, cy - 5), (cx + cell_w + 5, cy + cell_h + 5)],
                          outline=(230, 230, 230), width=1)

        pages.append(page)
    return pages


def save_pdf(pages, path):
    if not pages:
        return
    pages[0].save(path, save_all=True,
                  append_images=pages[1:] if len(pages) > 1 else [],
                  resolution=300.0)
    print(f"  -> {os.path.basename(path)} ({len(pages)}페이지)")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 combine_receipts.py config.json")
        sys.exit(1)

    with open(sys.argv[1]) as f:
        config = json.load(f)

    src_dir = config["src_dir"]
    out_dir = config.get("out_dir", os.path.join(src_dir, "결과"))
    os.makedirs(out_dir, exist_ok=True)
    default_per_page = config.get("pairs_per_page", 4)

    for filename, group in config["groups"].items():
        title = group["title"]
        per_page = group.get("per_page", default_per_page)

        if "pairs" in group:
            pages = make_pair_pages(group["pairs"], title, src_dir, per_page)
        elif "singles" in group:
            pages = make_single_pages(group["singles"], title, src_dir, per_page)
        else:
            print(f"  [skip] {filename}: no pairs or singles")
            continue

        save_pdf(pages, os.path.join(out_dir, f"{filename}.pdf"))

    print("완료!")


if __name__ == "__main__":
    main()
