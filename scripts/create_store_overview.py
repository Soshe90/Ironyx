from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/branding/store-screenshots/09-store-overview.png"
FEATURE_OUT = ROOT / "assets/branding/store-screenshots/feature-graphic.png"
SHOTS = ROOT / "assets/branding/store-screenshots"
FONTS = ROOT / "assets/fonts"
SIZE = (1080, 1920)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def screenshot_card(path: Path, width: int) -> Image.Image:
    screen = Image.open(path).convert("RGB")
    # Remove the phone's status and system navigation bars; preserve the app UI.
    screen = screen.crop((0, 112, screen.width, 2690))
    height = round(screen.height * width / screen.width)
    screen = screen.resize((width, height), Image.Resampling.LANCZOS)

    border = 9
    card = Image.new("RGBA", (width + 2 * border, height + 2 * border), (25, 42, 53, 255))
    mask = Image.new("L", card.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, card.width - 1, card.height - 1), radius=34, fill=255
    )
    card.putalpha(mask)
    screen_layer = Image.new("RGBA", screen.size, (0, 0, 0, 0))
    screen_layer.paste(screen, (0, 0))

    card.alpha_composite(screen_layer, (border, border))
    ImageDraw.Draw(card).rounded_rectangle(
        (0, 0, card.width - 1, card.height - 1),
        radius=34,
        outline=(80, 112, 123, 255),
        width=2,
    )
    return card


def place_card(canvas: Image.Image, path: Path, width: int, center: tuple[int, int], angle: float) -> None:
    card = screenshot_card(path, width)
    rotated = card.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    x = center[0] - rotated.width // 2
    y = center[1] - rotated.height // 2

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (x + 7, y + 18, x + rotated.width + 7, y + rotated.height + 18),
        radius=40,
        fill=(0, 0, 0, 165),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(rotated, (x, y))


def feature_card(path: Path, width: int, height: int) -> Image.Image:
    screen = Image.open(path).convert("RGB")
    screen = screen.crop((0, 112, screen.width, 2690))
    target_ratio = width / height
    crop_height = round(screen.width / target_ratio)
    top = (screen.height - crop_height) // 2
    screen = screen.crop((0, top, screen.width, top + crop_height))
    screen = screen.resize((width, height), Image.Resampling.LANCZOS)

    card = Image.new("RGBA", (width + 12, height + 12), (27, 45, 55, 255))
    card.alpha_composite(screen.convert("RGBA"), (6, 6))
    ImageDraw.Draw(card).rounded_rectangle(
        (0, 0, card.width - 1, card.height - 1),
        radius=28,
        outline=(80, 112, 123, 255),
        width=2,
    )
    mask = Image.new("L", card.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, card.width - 1, card.height - 1), radius=28, fill=255
    )
    card.putalpha(mask)
    return card


def feature_card_on(canvas: Image.Image, card: Image.Image, position: tuple[int, int], angle: float) -> None:
    rotated = card.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    x, y = position
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x + 5, y + 10, x + rotated.width + 5, y + rotated.height + 10),
        radius=26,
        fill=(0, 0, 0, 155),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(16)))
    canvas.alpha_composite(rotated, (x, y))


def create_feature_graphic() -> None:
    canvas = Image.new("RGBA", (1024, 500), (11, 22, 40, 255))
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((690, -230, 1190, 270), fill=(15, 54, 67, 255))
    draw.ellipse((-170, 350, 230, 750), fill=(13, 42, 58, 255))

    icon = Image.open(ROOT / "assets/branding/ironyx-icon-512-opaque.png").convert("RGB")
    icon = icon.resize((118, 118), Image.Resampling.LANCZOS)
    canvas.paste(icon, (66, 65))
    draw = ImageDraw.Draw(canvas)
    draw.text((207, 69), "IRONYX", font=font("Barlow-Bold.ttf", 61), fill=(245, 248, 250))
    draw.text((72, 226), "Your training, tracked.", font=font("Barlow-SemiBold.ttf", 41), fill=(56, 214, 192))
    draw.text((76, 293), "Log. Plan. Progress. Offline.", font=font("Barlow-Medium.ttf", 27), fill=(191, 207, 215))
    draw.rounded_rectangle((72, 365, 486, 424), radius=29, fill=(20, 54, 62), outline=(56, 214, 192), width=2)
    draw.text((279, 395), "OFFLINE WORKOUT TRACKER", font=font("Barlow-SemiBold.ttf", 19), fill=(56, 214, 192), anchor="mm")

    feature_card_on(canvas, feature_card(SHOTS / "04-program-detail.png", 223, 456), (572, 25), -4)
    feature_card_on(canvas, feature_card(SHOTS / "07-timer.png", 218, 446), (777, 48), 4)

    canvas.convert("RGB").save(FEATURE_OUT, format="PNG", optimize=True)
    size_mb = FEATURE_OUT.stat().st_size / (1024 * 1024)
    print(f"Wrote {FEATURE_OUT} (1024x500, {size_mb:.2f} MB)")


def main() -> None:
    canvas = Image.new("RGBA", SIZE, (11, 22, 40, 255))
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((790, -230, 1320, 300), fill=(15, 54, 67))
    draw.ellipse((-260, 1500, 300, 2060), fill=(13, 42, 58))

    draw.text((76, 64), "IRONYX  /  WORKOUT TRACKER", font=font("Barlow-Bold.ttf", 25), fill=(56, 214, 192))
    draw.text((72, 123), "Your training,", font=font("Barlow-SemiBold.ttf", 87), fill=(245, 248, 250))
    draw.text((72, 218), "tracked.", font=font("Barlow-SemiBold.ttf", 87), fill=(56, 214, 192))
    draw.text((78, 331), "Plan sessions. Log every set. Keep progressing.", font=font("Barlow-Medium.ttf", 34), fill=(191, 207, 215))

    # Secondary real app screens sit behind the main program detail.
    place_card(canvas, SHOTS / "06-library.png", 388, (200, 1310), -7)
    place_card(canvas, SHOTS / "07-timer.png", 388, (880, 1305), 7)
    place_card(canvas, SHOTS / "04-program-detail.png", 578, (540, 1210), 0)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((78, 1763, 1002, 1851), radius=44, fill=(20, 54, 62), outline=(56, 214, 192), width=2)
    draw.text((540, 1807), "WORKOUTS  ·  PROGRAMS  ·  300+ EXERCISES", font=font("Barlow-SemiBold.ttf", 25), fill=(56, 214, 192), anchor="mm")
    canvas.save(OUT, format="PNG", optimize=True)
    print(f"Wrote {OUT} ({SIZE[0]}x{SIZE[1]})")
    create_feature_graphic()


if __name__ == "__main__":
    main()
