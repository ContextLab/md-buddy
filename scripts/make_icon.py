"""Generate the MD Buddy app icon (all macOS sizes) into App/Assets.xcassets."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "App" / "Assets.xcassets" / "AppIcon.appiconset"
S = 1024


def icon() -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Squircle-ish rounded background with a vertical gradient (macOS icon grid: 824px body).
    body = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(body)
    top, bottom = (72, 132, 255), (118, 72, 222)
    for y in range(S):
        t = y / S
        d.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([100, 100, 924, 924], radius=185, fill=255)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([100, 116, 924, 940], radius=185, fill=(0, 0, 0, 90))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    img.paste(body, (0, 0), mask)

    d = ImageDraw.Draw(img)
    # White document with a folded corner.
    x0, y0, x1, y1, fold = 262, 210, 762, 814, 120
    d.polygon([(x0, y0), (x1 - fold, y0), (x1, y0 + fold), (x1, y1), (x0, y1)], fill=(255, 255, 255, 255))
    d.polygon([(x1 - fold, y0), (x1 - fold, y0 + fold), (x1, y0 + fold)], fill=(214, 222, 245, 255))

    # Markdown mark: "M" and a down arrow, drawn as strokes.
    ink = (52, 62, 110, 255)
    w = 44
    mx0, my0, my1 = 318, 470, 690
    d.line([(mx0, my1), (mx0, my0), (mx0 + 85, my0 + 105), (mx0 + 170, my0), (mx0 + 170, my1)],
           fill=ink, width=w, joint="curve")
    ax = 640
    d.line([(ax, my0), (ax, my1 - 40)], fill=ink, width=w)
    d.polygon([(ax - 72, my1 - 90), (ax + 72, my1 - 90), (ax, my1 + 6)], fill=ink)

    # Text lines above the mark.
    for i, width in enumerate((280, 220)):
        yy = 300 + i * 62
        d.rounded_rectangle([330, yy, 330 + width, yy + 26], radius=13, fill=(200, 208, 232, 255))
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    base = icon()
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            base.resize((px, px), Image.LANCZOS).save(OUT / name)
            images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
    (OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2))
    (OUT.parent / "Contents.json").write_text(json.dumps({"info": {"version": 1, "author": "xcode"}}, indent=2))
    base.save(OUT.parent.parent.parent / "docs" / "icon.png") if (OUT.parent.parent.parent / "docs").exists() else None


if __name__ == "__main__":
    main()
