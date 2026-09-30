"""Render local HTML documents to PDF with headless Chromium.

Each document's own @page rules drive paper size and margins, so the guide prints
Letter portrait and the wiring reference prints Letter landscape without any
per-file switches here.

Usage:
    python scripts/Convert-HtmlToPdf.py <input.html> <output.pdf> [...pairs]
"""

import pathlib
import sys

from playwright.sync_api import sync_playwright


def convert(page, src: pathlib.Path, dst: pathlib.Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    page.goto(src.resolve().as_uri(), wait_until="networkidle")
    page.emulate_media(media="print")
    page.wait_for_timeout(400)
    page.pdf(
        path=str(dst),
        print_background=True,
        prefer_css_page_size=True,
        display_header_footer=False,
    )
    print(f"{dst.name:46} {dst.stat().st_size / 1024:8,.0f} KB")


def main(argv: list[str]) -> int:
    if len(argv) < 2 or len(argv) % 2:
        print(__doc__)
        return 2

    pairs = [(pathlib.Path(argv[i]), pathlib.Path(argv[i + 1])) for i in range(0, len(argv), 2)]
    missing = [str(s) for s, _ in pairs if not s.is_file()]
    if missing:
        print("not found: " + ", ".join(missing))
        return 1

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        try:
            page = browser.new_page()
            for src, dst in pairs:
                convert(page, src, dst)
        finally:
            browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
