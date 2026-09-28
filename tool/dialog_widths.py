"""Size every dialog figure in the docs to its share of the app window.

Dialog screenshots are cropped to the dialog, so shown at full width they look
several times larger than they are in the app. This sets each dialog figure's
``:width:`` to the dialog's width as a fraction of the 1440 px window the
full-screen screenshots are taken at, and centres it. Run after regenerating
the screenshots:

    uv run --no-project --with pillow python tool/dialog_widths.py
"""

from __future__ import annotations

import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SHOTS = ROOT / "docs" / "_static" / "screenshots"
# The full-screen captures: 1440 logical pixels at a pixel ratio of 2.
WINDOW_PX = 2880

FIGURE = re.compile(
    r"(\.\. figure:: \.\./_static/screenshots/(dialog_[a-z_]+)\.png\n"
    r"(?:   :[a-z]+:.*\n(?:         .*\n)*)*)"
)


def _options(image: str) -> str:
    width = Image.open(SHOTS / f"{image}.png").width
    percent = max(20, min(100, round(width / WINDOW_PX * 100)))
    return f"   :width: {percent}%\n   :align: center\n"


def _resize(match: re.Match[str]) -> str:
    block = match.group(1)
    kept = [
        line
        for line in block.splitlines(keepends=True)
        if not line.startswith(("   :width:", "   :align:"))
    ]
    return "".join(kept) + _options(match.group(2))


def main() -> int:
    for page in (ROOT / "docs").rglob("*.rst"):
        text = page.read_text(encoding="utf-8")
        resized = FIGURE.sub(_resize, text)
        if resized != text:
            page.write_text(resized, encoding="utf-8", newline="\n")
            print(f"  {page.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
