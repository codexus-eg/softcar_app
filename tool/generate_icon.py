"""Generates the SoftCar app icon (1024x1024) from the brand logo.

Takes the user's logo (logo.webp) and places it centered on the charcoal
brand background to form the launcher icon and splash mark.
"""
import os
from PIL import Image

SIZE = 1024
INK = (11, 11, 13, 255)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "logo.webp")
OUT = os.path.join(ROOT, "assets/icon/icon_raw.png")
LOGO_OUT = os.path.join(ROOT, "assets/logo/logo.png")


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    os.makedirs(os.path.dirname(LOGO_OUT), exist_ok=True)

    logo = Image.open(LOGO).convert("RGBA")

    # In-app logo asset (keeps transparency, crisp 3x for @3x devices).
    logo_512 = logo.resize((512, 512), Image.LANCZOS)
    logo_512.save(LOGO_OUT)
    print(f"in-app logo written to {LOGO_OUT}")

    # Launcher icon: charcoal rounded square + logo centered.
    target = int(SIZE * 0.78)
    logo_icon = logo.resize((target, target), Image.LANCZOS)

    icon = Image.new("RGBA", (SIZE, SIZE), INK)
    x = (SIZE - target) // 2
    y = (SIZE - target) // 2
    icon.paste(logo_icon, (x, y), logo_icon)

    mask = Image.new("L", (SIZE, SIZE), 0)
    from PIL import ImageDraw

    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, SIZE - 1, SIZE - 1), radius=SIZE * 0.22, fill=255)
    icon.putalpha(mask)

    icon.save(OUT)
    print(f"launcher icon written to {OUT}")


if __name__ == "__main__":
    main()
