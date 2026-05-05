import sys
import configparser
from pathlib import Path

from PIL import Image, ImageGrab
try:
    import win32gui
except ImportError:
    win32gui = None


BASE_SCREEN_W = 2560
BASE_GRID_X = 21
BASE_GRID_Y = 216
BASE_CELL_W = 67
BASE_CELL_H = 67
GRID_COLS = 12
GRID_ROWS = 12

TARGET = (0xE7, 0xB4, 0x77)
TOLERANCE = 24
SIDE_SAMPLES = 7
SIDE_MIN_HITS = 3
SIDE_THICKNESS = 3
CONTENT_MARGIN = 8
CONTENT_MIN_RATIO = 0.02
EMPTY_CENTER_RGB = (7, 7, 7)
EMPTY_CENTER_TOLERANCE = 10
EMPTY_CENTER_RADIUS = 4
EMPTY_CENTER_MIN_RATIO = 0.65
GAME_WINDOW_TITLE = "流放之路"


def parse_hex_rgb(value, default):
    text = str(value or "").strip().lstrip("#").lstrip("0x").lstrip("0X")
    if len(text) != 6:
        return default
    try:
        return tuple(int(text[i : i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return default


def load_settings(settings_path):
    global TARGET, EMPTY_CENTER_RGB

    parser = configparser.ConfigParser()
    parser.read(settings_path, encoding="utf-8-sig")
    if parser.has_section("Detection"):
        TARGET = parse_hex_rgb(parser.get("Detection", "BorderColor", fallback=""), TARGET)
        EMPTY_CENTER_RGB = parse_hex_rgb(
            parser.get("Detection", "CenterColor", fallback=""), EMPTY_CENTER_RGB
        )
    debug_mode = False
    if parser.has_section("General"):
        debug_mode = parser.get("General", "DebugMode", fallback="0").strip() == "1"
    return debug_mode


def cell_name(c, r):
    return chr(64 + c) + str(r)


def range_name(c, r, w, h):
    a = cell_name(c, r)
    b = cell_name(c + w - 1, r + h - 1)
    return a if a == b else a + ":" + b


def covered_cells(c, r, w, h):
    cells = []
    for rr in range(r, r + h):
        for cc in range(c, c + w):
            cells.append(cell_name(cc, rr))
    return " ".join(cells)


def near(rgb):
    return all(abs(rgb[i] - TARGET[i]) <= TOLERANCE for i in range(3))


def green_border(rgb):
    red, green, blue = rgb
    return green >= 85 and red <= 120 and blue <= 95 and green - red >= 20 and green - blue >= 30


def clusters(counts, threshold):
    result = []
    start = None
    vals = []
    for i, value in enumerate(counts):
        if value >= threshold:
            if start is None:
                start = i
                vals = []
            vals.append((i, value))
        elif start is not None:
            total = sum(v for _, v in vals)
            center = sum(i * v for i, v in vals) / total
            result.append({"center": center, "weight": total, "start": start, "end": i - 1})
            start = None
    if start is not None:
        total = sum(v for _, v in vals)
        center = sum(i * v for i, v in vals) / total
        result.append({"center": center, "weight": total, "start": start, "end": len(counts) - 1})
    return result


def fit_grid_lines(line_clusters, cells, min_pos, max_pos):
    best = None

    for spacing_i in range(5500, 8001, 25):
        spacing = spacing_i / 100.0
        for cluster in line_clusters:
            for k in range(cells + 1):
                start = cluster["center"] - k * spacing
                end = start + cells * spacing
                if start < min_pos or end > max_pos:
                    continue

                matched = set()
                score = 0
                max_error = max(2.8, spacing * 0.055)
                for line_index in range(cells + 1):
                    expected = start + line_index * spacing
                    local_best = None
                    for idx, c in enumerate(line_clusters):
                        err = abs(c["center"] - expected)
                        if err <= max_error and (local_best is None or err < local_best[0]):
                            local_best = (err, idx, c)
                    if local_best is not None and local_best[1] not in matched:
                        matched.add(local_best[1])
                        score += local_best[2]["weight"] / (1 + local_best[0])

                candidate = (len(matched), score, start, spacing)
                if best is None or candidate > best:
                    best = candidate

    if best is None or best[0] < 5:
        return None

    _, _, start, spacing = best
    return [round(start + i * spacing, 2) for i in range(cells + 1)], spacing, best[0]


def fit_border_pair(line_clusters, cells):
    best = None
    ordered = sorted(line_clusters, key=lambda c: c["center"])
    for i, first in enumerate(ordered):
        for second in ordered[i + 1 :]:
            span = second["center"] - first["center"]
            spacing = span / cells
            if 55 <= spacing <= 80:
                score = first["weight"] + second["weight"]
                candidate = (score, first["center"], second["center"], spacing)
                if best is None or candidate > best:
                    best = candidate

    if best is None:
        return None

    _, start, end, spacing = best
    return [round(start + i * spacing, 2) for i in range(cells + 1)], spacing


def detect_grid_lines_from_green_border(im):
    width, height = im.size
    search_x2 = min(width, max(1, int(width * 0.43)), 1100)
    search_y1 = 100
    search_y2 = min(height - 80, int(height * 0.9))

    x_counts = [0] * search_x2
    y_counts = [0] * height

    for y in range(search_y1, search_y2):
        for x in range(search_x2):
            if green_border(im.getpixel((x, y))):
                x_counts[x] += 1
                y_counts[y] += 1

    if not x_counts or not y_counts or max(x_counts) < 150 or max(y_counts) < 150:
        return None

    x_threshold = max(120, int(max(x_counts) * 0.45))
    y_threshold = max(120, int(max(y_counts) * 0.45))
    x_clusters = clusters(x_counts, x_threshold)
    y_clusters = clusters(y_counts, y_threshold)

    x_fit = fit_border_pair(x_clusters, GRID_COLS)
    y_fit = fit_border_pair(y_clusters, GRID_ROWS)
    if not x_fit or not y_fit:
        return None

    return (
        x_fit[0],
        y_fit[0],
        x_fit[1],
        y_fit[1],
        "green_border",
        len(x_clusters),
        len(y_clusters),
        2,
        2,
    )


def detect_grid_lines(im):
    width, height = im.size
    green_fit = detect_grid_lines_from_green_border(im)
    if green_fit:
        return green_fit

    left_limit = min(width, max(1, int(width * 0.48)))

    x_counts = [0] * left_limit
    y_counts = [0] * height

    for y in range(60, min(height - 80, int(height * 0.9))):
        for x in range(0, left_limit):
            if near(im.getpixel((x, y))):
                x_counts[x] += 1
                y_counts[y] += 1

    x_threshold = max(45, int(max(x_counts) * 0.12))
    y_threshold = max(45, int(max(y_counts) * 0.12))
    x_clusters = clusters(x_counts, x_threshold)
    y_clusters = clusters(y_counts, y_threshold)

    x_lines = fit_grid_lines(x_clusters, GRID_COLS, 0, left_limit)
    y_lines = fit_grid_lines(y_clusters, GRID_ROWS, 80, min(height - 80, int(height * 0.9)))

    if not x_lines or not y_lines:
        scale = width / BASE_SCREEN_W
        x0 = round(BASE_GRID_X * scale)
        y0 = round(BASE_GRID_Y * scale)
        cell = BASE_CELL_W * scale
        return (
            [round(x0 + i * cell, 2) for i in range(GRID_COLS + 1)],
            [round(y0 + i * cell, 2) for i in range(GRID_ROWS + 1)],
            cell,
            cell,
            "fixed_fallback",
            len(x_clusters),
            len(y_clusters),
            0,
            0,
        )

    return (
        x_lines[0],
        y_lines[0],
        x_lines[1],
        y_lines[1],
        "gold_histogram",
        len(x_clusters),
        len(y_clusters),
        x_lines[2],
        y_lines[2],
    )


def parse_items(im):
    im = im.convert("RGB")
    width, height = im.size
    x_lines, y_lines, cell_w, cell_h, grid_source, x_cluster_count, y_cluster_count, x_matched, y_matched = detect_grid_lines(im)
    grid_x = x_lines[0]
    grid_y = y_lines[0]
    scale = cell_w / BASE_CELL_W

    def pixel(x, y):
        x = int(x + 0.5)
        y = int(y + 0.5)
        if x < 0 or y < 0 or x >= width or y >= height:
            return False
        return near(im.getpixel((x, y)))

    def near_line(x, y, vertical):
        for offset in range(-SIDE_THICKNESS, SIDE_THICKNESS + 1):
            if vertical:
                if pixel(x + offset, y):
                    return True
            else:
                if pixel(x, y + offset):
                    return True
        return False

    def side_highlighted(c, r, side):
        x1 = x_lines[c - 1]
        y1 = y_lines[r - 1]
        x2 = x_lines[c]
        y2 = y_lines[r]
        hits = 0

        for pos in range(SIDE_SAMPLES):
            ratio = 0.5 if SIDE_SAMPLES == 1 else pos / (SIDE_SAMPLES - 1)
            if side in ("T", "B"):
                x = round(x1 + 8 * scale + ratio * (cell_w - 16 * scale))
                y = y1 if side == "T" else y2
                if near_line(x, y, False):
                    hits += 1
            else:
                x = x1 if side == "L" else x2
                y = round(y1 + 8 * scale + ratio * (cell_h - 16 * scale))
                if near_line(x, y, True):
                    hits += 1

        return hits >= SIDE_MIN_HITS

    def has_item_content(c, r, w, h):
        x1 = int(x_lines[c - 1] + CONTENT_MARGIN * scale + 0.5)
        y1 = int(y_lines[r - 1] + CONTENT_MARGIN * scale + 0.5)
        x2 = int(x_lines[c + w - 1] - CONTENT_MARGIN * scale + 0.5)
        y2 = int(y_lines[r + h - 1] - CONTENT_MARGIN * scale + 0.5)

        total = 0
        content = 0
        step = 2
        for y in range(y1, max(y1, y2), step):
            for x in range(x1, max(x1, x2), step):
                red, green, blue = im.getpixel((x, y))
                high = max(red, green, blue)
                low = min(red, green, blue)
                total += 1
                if (high > 75) or (high - low > 35 and high > 50):
                    content += 1

        if total == 0:
            return 0

        ratio = content / total
        return ratio

    def center_empty_stats(c, r, w, h):
        cx = int((x_lines[c - 1] + x_lines[c + w - 1]) / 2 + 0.5)
        cy = int((y_lines[r - 1] + y_lines[r + h - 1]) / 2 + 0.5)
        radius = max(2, int(EMPTY_CENTER_RADIUS * scale + 0.5))

        total = 0
        empty_like = 0
        step = 1
        for y in range(cy - radius, cy + radius + 1, step):
            for x in range(cx - radius, cx + radius + 1, step):
                if x < 0 or y < 0 or x >= width or y >= height:
                    continue
                red, green, blue = im.getpixel((x, y))
                total += 1
                if (
                    abs(red - EMPTY_CENTER_RGB[0]) <= EMPTY_CENTER_TOLERANCE
                    and abs(green - EMPTY_CENTER_RGB[1]) <= EMPTY_CENTER_TOLERANCE
                    and abs(blue - EMPTY_CENTER_RGB[2]) <= EMPTY_CENTER_TOLERANCE
                ):
                    empty_like += 1

        if total == 0:
            return False, 0, (0, 0, 0)

        center_rgb = im.getpixel((cx, cy))
        empty_ratio = empty_like / total
        return empty_ratio >= EMPTY_CENTER_MIN_RATIO, empty_ratio, center_rgb

    top = [[False] * (GRID_COLS + 1) for _ in range(GRID_ROWS + 1)]
    bottom = [[False] * (GRID_COLS + 1) for _ in range(GRID_ROWS + 1)]
    left = [[False] * (GRID_COLS + 1) for _ in range(GRID_ROWS + 1)]
    right = [[False] * (GRID_COLS + 1) for _ in range(GRID_ROWS + 1)]

    for r in range(1, GRID_ROWS + 1):
        for c in range(1, GRID_COLS + 1):
            top[r][c] = side_highlighted(c, r, "T")
            bottom[r][c] = side_highlighted(c, r, "B")
            left[r][c] = side_highlighted(c, r, "L")
            right[r][c] = side_highlighted(c, r, "R")

    def is_item_rect(c, r, w, h):
        x2 = c + w - 1
        y2 = r + h - 1

        for cc in range(c, c + w):
            if not top[r][cc] or not bottom[y2][cc]:
                return False

        for rr in range(r, r + h):
            if not left[rr][c] or not right[rr][x2]:
                return False

        for cc in range(c, c + w - 1):
            for rr in range(r, r + h):
                if right[rr][cc] or left[rr][cc + 1]:
                    return False

        for rr in range(r, r + h - 1):
            for cc in range(c, c + w):
                if bottom[rr][cc] or top[rr + 1][cc]:
                    return False

        is_empty_center, _, _ = center_empty_stats(c, r, w, h)
        return not is_empty_center

    items = []
    seen = set()
    for r in range(1, GRID_ROWS + 1):
        for c in range(1, GRID_COLS + 1):
            for h in range(1, GRID_ROWS - r + 2):
                found_at_this_height = False
                for w in range(1, GRID_COLS - c + 2):
                    if is_item_rect(c, r, w, h):
                        key = (c, r, w, h)
                        if key not in seen:
                            seen.add(key)
                            x1 = x_lines[c - 1]
                            y1 = y_lines[r - 1]
                            cx = round(x1 + w * cell_w / 2)
                            cy = round(y1 + h * cell_h / 2)
                            content_ratio = has_item_content(c, r, w, h)
                            maybe_empty, center_empty_ratio, center_rgb = center_empty_stats(c, r, w, h)
                            items.append(
                                {
                                    "c": c,
                                    "r": r,
                                    "w": w,
                                    "h": h,
                                    "range": range_name(c, r, w, h),
                                    "cells": covered_cells(c, r, w, h),
                                    "cx": cx,
                                    "cy": cy,
                                    "content": round(content_ratio, 4),
                                    "center_rgb": f"{center_rgb[0]:02X}{center_rgb[1]:02X}{center_rgb[2]:02X}",
                                    "center_empty_ratio": round(center_empty_ratio, 4),
                                    "maybe_empty": int(maybe_empty),
                                }
                            )
                        found_at_this_height = True
                        break
                if found_at_this_height:
                    break

    sample_hits = 0
    for r in range(1, GRID_ROWS + 1):
        for c in range(1, GRID_COLS + 1):
            if pixel(x_lines[c - 1], y_lines[r - 1]):
                sample_hits += 1

    debug = {
        "screen": f"{width}x{height}",
        "grid_x": grid_x,
        "grid_y": grid_y,
        "cell_w": round(cell_w, 3),
        "cell_h": round(cell_h, 3),
        "grid_source": grid_source,
        "x_clusters": x_cluster_count,
        "y_clusters": y_cluster_count,
        "x_matched_lines": x_matched,
        "y_matched_lines": y_matched,
        "x_lines": ",".join(str(round(v, 2)) for v in x_lines),
        "y_lines": ",".join(str(round(v, 2)) for v in y_lines),
        "corner_sample_hits": sample_hits,
        "detected": len(items),
        "content_min_ratio": CONTENT_MIN_RATIO,
        "empty_center_rgb": f"{EMPTY_CENTER_RGB[0]:02X}{EMPTY_CENTER_RGB[1]:02X}{EMPTY_CENTER_RGB[2]:02X}",
        "empty_center_tolerance": EMPTY_CENTER_TOLERANCE,
        "empty_center_min_ratio": EMPTY_CENTER_MIN_RATIO,
    }
    return items, debug


def apply_screen_offset(items, capture_meta):
    origin_x = 0
    origin_y = 0
    rect = capture_meta.get("window_rect", "")
    if rect:
        try:
            origin_x, origin_y, _, _ = (int(v) for v in rect.split(","))
        except ValueError:
            origin_x = 0
            origin_y = 0

    for item in items:
        item["screen_x"] = round(item["cx"] + origin_x)
        item["screen_y"] = round(item["cy"] + origin_y)


def write_items(path, items):
    lines = [
        "index\tc\tr\tw\th\trange\tcells\tcx\tcy\tcontent\tcenter_rgb\tcenter_empty_ratio\tmaybe_empty\tscreen_x\tscreen_y"
    ]
    for index, item in enumerate(items, 1):
        lines.append(
            "\t".join(
                [
                    str(index),
                    str(item["c"]),
                    str(item["r"]),
                    str(item["w"]),
                    str(item["h"]),
                    item["range"],
                    item["cells"],
                    str(item["cx"]),
                    str(item["cy"]),
                    str(item.get("content", "")),
                    str(item.get("center_rgb", "")),
                    str(item.get("center_empty_ratio", "")),
                    str(item.get("maybe_empty", "")),
                    str(item.get("screen_x", item["cx"])),
                    str(item.get("screen_y", item["cy"])),
                ]
            )
        )
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_debug(path, data, error=None):
    lines = []
    for key, value in data.items():
        lines.append(f"{key}={value}")
    if error:
        lines.append(f"error={error}")
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def grab_foreground_window():
    if win32gui is None:
        return ImageGrab.grab(), {"capture_source": "screen_no_win32gui"}

    hwnd = win32gui.GetForegroundWindow()
    title = win32gui.GetWindowText(hwnd) if hwnd else ""
    if GAME_WINDOW_TITLE not in title:
        found = []

        def enum_handler(candidate, _):
            if win32gui.IsWindowVisible(candidate) and GAME_WINDOW_TITLE in win32gui.GetWindowText(candidate):
                found.append(candidate)

        win32gui.EnumWindows(enum_handler, None)
        if found:
            hwnd = found[0]

    if not hwnd:
        return ImageGrab.grab(), {"capture_source": "screen_no_foreground"}

    title = win32gui.GetWindowText(hwnd)
    left, top, right, bottom = win32gui.GetWindowRect(hwnd)
    if right <= left or bottom <= top:
        return ImageGrab.grab(), {"capture_source": "screen_bad_window", "window_title": title}

    im = ImageGrab.grab(bbox=(left, top, right, bottom))
    meta = {
        "capture_source": "foreground_window",
        "window_title": title,
        "window_rect": f"{left},{top},{right},{bottom}",
    }
    return im, meta


def main():
    if len(sys.argv) < 3:
        print("usage: market_detect_items.py OUT_TSV DEBUG_TXT [IMAGE_PATH]", file=sys.stderr)
        return 2

    out_path = Path(sys.argv[1])
    debug_path = Path(sys.argv[2])
    capture_path = out_path.with_name("market_discount_capture.png")

    try:
        settings_path = debug_path.with_name("settings.ini")
        debug_mode = load_settings(settings_path)
        if len(sys.argv) >= 4:
            im = Image.open(sys.argv[3])
            capture_meta = {"capture_source": "file"}
        else:
            im, capture_meta = grab_foreground_window()
        if debug_mode:
            im.save(capture_path)
        items, debug = parse_items(im)
        debug.update(capture_meta)
        if debug_mode:
            debug["capture"] = str(capture_path)
        debug["settings"] = str(settings_path)
        apply_screen_offset(items, capture_meta)
        write_items(out_path, items)
        if debug_mode:
            write_debug(debug_path, debug)
        return 0
    except Exception as exc:
        write_items(out_path, [])
        try:
            settings_path = debug_path.with_name("settings.ini")
            debug_mode = load_settings(settings_path)
        except Exception:
            debug_mode = True
        if debug_mode:
            write_debug(debug_path, {"detected": 0}, repr(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
