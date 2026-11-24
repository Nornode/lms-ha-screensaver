#!/usr/bin/env python3
"""
Generate anti-aliased RGBA PNG weather & status icons for HAScreenSaver
using only Python standard library (4x supersampling for crisp rendering).

Covers all 15 official Home Assistant weather.* conditions in both standard
(dark-background) and *_dark.png (light-background / Bright Silver) palettes,
rendered natively at 56x56 for sharp 1:1 blitting on Squeezebox Radio & Controller.
"""

import math
import os
import struct
import zlib

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT_DIR, "radio-applet", "HAScreenSaver")

WEATHER_SIZE = 56
SCALE = WEATHER_SIZE / 44.0  # Scale existing 44x44 vector coordinates cleanly to 56x56


def write_png(path, width, height, rgba_bytes):
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", crc)

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type None
        raw.extend(rgba_bytes[y * stride : (y + 1) * stride])

    ihdr = struct.pack("!IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


class Canvas:
    """4x supersampled RGBA canvas for smooth anti-aliased icons."""

    def __init__(self, width, height, ss=4):
        self.w = width
        self.h = height
        self.ss = ss
        self.sw = width * ss
        self.sh = height * ss
        self.buf = [[0, 0, 0, 0] for _ in range(self.sw * self.sh)]

    def blend_pixel(self, x, y, r, g, b, a):
        if x < 0 or y < 0 or x >= self.sw or y >= self.sh or a <= 0:
            return
        idx = y * self.sw + x
        dst = self.buf[idx]
        sa = a / 255.0
        da = dst[3] / 255.0
        out_a = sa + da * (1.0 - sa)
        if out_a <= 0:
            return
        dst[0] = int((r * sa + dst[0] * da * (1.0 - sa)) / out_a)
        dst[1] = int((g * sa + dst[1] * da * (1.0 - sa)) / out_a)
        dst[2] = int((b * sa + dst[2] * da * (1.0 - sa)) / out_a)
        dst[3] = int(out_a * 255)

    def circle(self, cx, cy, rad, color):
        r, g, b, a = color
        cx *= self.ss
        cy *= self.ss
        rad *= self.ss
        x0 = max(0, int(math.floor(cx - rad - 1)))
        x1 = min(self.sw - 1, int(math.ceil(cx + rad + 1)))
        y0 = max(0, int(math.floor(cy - rad - 1)))
        y1 = min(self.sh - 1, int(math.ceil(cy + rad + 1)))
        r2 = rad * rad
        for y in range(y0, y1 + 1):
            dy = y + 0.5 - cy
            for x in range(x0, x1 + 1):
                dx = x + 0.5 - cx
                if dx * dx + dy * dy <= r2:
                    self.blend_pixel(x, y, r, g, b, a)

    def capsule(self, x1, y1, x2, y2, rad, color):
        r, g, b, a = color
        x1 *= self.ss
        y1 *= self.ss
        x2 *= self.ss
        y2 *= self.ss
        rad *= self.ss
        minx = max(0, int(math.floor(min(x1, x2) - rad - 1)))
        maxx = min(self.sw - 1, int(math.ceil(max(x1, x2) + rad + 1)))
        miny = max(0, int(math.floor(min(y1, y2) - rad - 1)))
        maxy = min(self.sh - 1, int(math.ceil(max(y1, y2) + rad + 1)))
        vx = x2 - x1
        vy = y2 - y1
        vlen2 = vx * vx + vy * vy
        r2 = rad * rad
        for y in range(miny, maxy + 1):
            py = y + 0.5
            for x in range(minx, maxx + 1):
                px = x + 0.5
                if vlen2 == 0:
                    dx, dy = px - x1, py - y1
                else:
                    t = max(0.0, min(1.0, ((px - x1) * vx + (py - y1) * vy) / vlen2))
                    dx = px - (x1 + t * vx)
                    dy = py - (y1 + t * vy)
                if dx * dx + dy * dy <= r2:
                    self.blend_pixel(x, y, r, g, b, a)

    def rect(self, x1, y1, x2, y2, color):
        r, g, b, a = color
        sx1 = max(0, int(round(x1 * self.ss)))
        sy1 = max(0, int(round(y1 * self.ss)))
        sx2 = min(self.sw, int(round(x2 * self.ss)))
        sy2 = min(self.sh, int(round(y2 * self.ss)))
        for y in range(sy1, sy2):
            for x in range(sx1, sx2):
                self.blend_pixel(x, y, r, g, b, a)

    def polygon(self, pts, color):
        r, g, b, a = color
        spts = [(x * self.ss, y * self.ss) for x, y in pts]
        xs = [p[0] for p in spts]
        ys = [p[1] for p in spts]
        minx = max(0, int(math.floor(min(xs))))
        maxx = min(self.sw - 1, int(math.ceil(max(xs))))
        miny = max(0, int(math.floor(min(ys))))
        maxy = min(self.sh - 1, int(math.ceil(max(ys))))
        n = len(spts)
        for y in range(miny, maxy + 1):
            py = y + 0.5
            for x in range(minx, maxx + 1):
                px = x + 0.5
                inside = False
                j = n - 1
                for i in range(n):
                    xi, yi = spts[i]
                    xj, yj = spts[j]
                    if ((yi > py) != (yj > py)) and (
                        px < (xj - xi) * (py - yi) / (yj - yi + 1e-12) + xi
                    ):
                        inside = not inside
                    j = i
                if inside:
                    self.blend_pixel(x, y, r, g, b, a)

    def subtract_circle(self, cx, cy, rad):
        cx *= self.ss
        cy *= self.ss
        rad *= self.ss
        x0 = max(0, int(math.floor(cx - rad - 1)))
        x1 = min(self.sw - 1, int(math.ceil(cx + rad + 1)))
        y0 = max(0, int(math.floor(cy - rad - 1)))
        y1 = min(self.sh - 1, int(math.ceil(cy + rad + 1)))
        r2 = rad * rad
        for y in range(y0, y1 + 1):
            dy = y + 0.5 - cy
            for x in range(x0, x1 + 1):
                dx = x + 0.5 - cx
                if dx * dx + dy * dy <= r2:
                    self.buf[y * self.sw + x] = [0, 0, 0, 0]

    def to_rgba_bytes(self):
        out = bytearray(self.w * self.h * 4)
        area = self.ss * self.ss
        for y in range(self.h):
            for x in range(self.w):
                sr = sg = sb = sa = 0
                for sy in range(self.ss):
                    row = (y * self.ss + sy) * self.sw
                    for sx in range(self.ss):
                        px = self.buf[row + x * self.ss + sx]
                        pa = px[3]
                        sr += px[0] * pa
                        sg += px[1] * pa
                        sb += px[2] * pa
                        sa += pa
                idx = (y * self.w + x) * 4
                if sa > 0:
                    out[idx] = min(255, sr // sa)
                    out[idx + 1] = min(255, sg // sa)
                    out[idx + 2] = min(255, sb // sa)
                    out[idx + 3] = min(255, sa // area)
        return bytes(out)

    def save(self, filename):
        os.makedirs(OUT_DIR, exist_ok=True)
        write_png(os.path.join(OUT_DIR, filename), self.w, self.h, self.to_rgba_bytes())


PALETTE_STANDARD = {
    "sun_gold": (255, 209, 92, 255),
    "sun_ray": (255, 196, 61, 255),
    "cloud_light": (224, 232, 242, 255),
    "cloud_mid": (182, 194, 210, 255),
    "cloud_dark": (146, 160, 178, 255),
    "rain_blue": (92, 184, 255, 255),
    "pour_blue": (62, 160, 255, 255),
    "snow_ice": (232, 246, 255, 255),
    "hail_ice": (196, 228, 252, 255),
    "fog_gray": (176, 190, 208, 235),
    "bolt_yellow": (255, 214, 64, 255),
    "moon_light": (220, 232, 248, 255),
    "wind_blue": (180, 212, 236, 240),
    "warn_bg": (235, 152, 46, 255),
    "warn_fg": (22, 26, 32, 255),
    "alarm": (142, 152, 168, 255),
}

# Dark-ink palette for light backgrounds (e.g. Bright Silver on white Squeezebox Radio)
PALETTE_DARK = {
    "sun_gold": (217, 134, 14, 255),
    "sun_ray": (204, 120, 10, 255),
    "cloud_light": (62, 74, 92, 255),
    "cloud_mid": (92, 106, 126, 255),
    "cloud_dark": (46, 56, 70, 255),
    "rain_blue": (20, 110, 200, 255),
    "pour_blue": (12, 88, 176, 255),
    "snow_ice": (42, 126, 186, 255),
    "hail_ice": (34, 96, 154, 255),
    "fog_gray": (82, 94, 112, 235),
    "bolt_yellow": (210, 138, 8, 255),
    "moon_light": (54, 68, 92, 255),
    "wind_blue": (48, 96, 136, 245),
    "warn_bg": (194, 72, 24, 255),
    "warn_fg": (255, 255, 255, 255),
    "alarm": (60, 69, 82, 255),
}

WHITE = (255, 255, 255, 255)


def S(v):
    return v * SCALE


def draw_cloud(c, ox, oy, scale, color):
    sc = scale * SCALE
    ox *= SCALE
    oy *= SCALE
    c.circle(ox + 12 * sc, oy + 14 * sc, 7.2 * sc, color)
    c.circle(ox + 20 * sc, oy + 10 * sc, 8.8 * sc, color)
    c.circle(ox + 29 * sc, oy + 14 * sc, 6.8 * sc, color)
    c.capsule(
        ox + 12 * sc,
        oy + 17.5 * sc,
        ox + 29 * sc,
        oy + 17.5 * sc,
        3.8 * sc,
        color,
    )


def gen_sunny(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    cx, cy = S(22.0), S(22.0)
    c.circle(cx, cy, S(9.0), pal["sun_gold"])
    for i in range(8):
        ang = i * (math.pi / 4.0)
        x1 = cx + math.cos(ang) * S(12.5)
        y1 = cy + math.sin(ang) * S(12.5)
        x2 = cx + math.cos(ang) * S(16.8)
        y2 = cy + math.sin(ang) * S(16.8)
        c.capsule(x1, y1, x2, y2, S(1.55), pal["sun_ray"])
    c.save(f"weather_sunny{suffix}.png")


def gen_clear_night(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    c.circle(S(21.0), S(22.0), S(12.0), pal["moon_light"])
    c.subtract_circle(S(26.5), S(18.0), S(10.5))
    c.circle(S(33.5), S(12.5), S(1.4), pal["sun_gold"])
    c.circle(S(36.0), S(20.5), S(1.0), pal["moon_light"])
    c.save(f"weather_clear_night{suffix}.png")


def gen_partlycloudy(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    cx, cy = S(15.5), S(16.5)
    c.circle(cx, cy, S(6.8), pal["sun_gold"])
    for i in range(8):
        ang = i * (math.pi / 4.0)
        c.capsule(
            cx + math.cos(ang) * S(9.5),
            cy + math.sin(ang) * S(9.5),
            cx + math.cos(ang) * S(12.2),
            cy + math.sin(ang) * S(12.2),
            S(1.25),
            pal["sun_ray"],
        )
    draw_cloud(c, 8.0, 14.5, 0.92, pal["cloud_light"])
    c.save(f"weather_partlycloudy{suffix}.png")


def gen_cloudy(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    draw_cloud(c, 10.0, 8.5, 0.78, pal["cloud_mid"])
    draw_cloud(c, 3.0, 13.5, 0.96, pal["cloud_light"])
    c.save(f"weather_cloudy{suffix}.png")


def gen_rainy(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    draw_cloud(c, 3.5, 5.5, 0.95, pal["cloud_light"])
    for x in (14.5, 22.5, 30.5):
        c.capsule(S(x), S(29.0), S(x - 2.4), S(36.0), S(1.45), pal["rain_blue"])
    c.save(f"weather_rainy{suffix}.png")


def gen_pouring(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    draw_cloud(c, 3.5, 4.5, 0.95, pal["cloud_dark"])
    for x in (11.5, 17.5, 23.5, 29.5, 35.0):
        c.capsule(S(x), S(27.5), S(x - 3.2), S(37.5), S(1.35), pal["pour_blue"])
    c.save(f"weather_pouring{suffix}.png")


def gen_hail(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    draw_cloud(c, 3.5, 4.5, 0.95, pal["cloud_dark"])
    for hx, hy in ((13.0, 30.0), (22.0, 29.5), (31.0, 30.0), (17.0, 36.5), (26.5, 36.5)):
        diamond = [
            (S(hx), S(hy - 2.5)),
            (S(hx + 2.3), S(hy)),
            (S(hx), S(hy + 2.5)),
            (S(hx - 2.3), S(hy)),
        ]
        c.polygon(diamond, pal["hail_ice"])
    c.save(f"weather_hail{suffix}.png")


def gen_snowy(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    draw_cloud(c, 3.5, 5.5, 0.95, pal["cloud_light"])
    for fx, fy in ((14.0, 32.5), (22.5, 35.0), (31.0, 32.5)):
        c.circle(S(fx), S(fy), S(2.3), pal["snow_ice"])
    c.save(f"weather_snowy{suffix}.png")


def gen_snowy_rainy(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    draw_cloud(c, 3.5, 5.0, 0.95, pal["cloud_light"])
    # Alternating rain streaks and snow dots
    c.capsule(S(14.5), S(28.5), S(12.2), S(36.0), S(1.4), pal["rain_blue"])
    c.circle(S(22.5), S(33.5), S(2.3), pal["snow_ice"])
    c.capsule(S(31.0), S(28.5), S(28.7), S(36.0), S(1.4), pal["rain_blue"])
    c.save(f"weather_snowy_rainy{suffix}.png")


def gen_fog(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    draw_cloud(c, 4.5, 4.0, 0.88, pal["cloud_mid"])
    c.capsule(S(8.0), S(27.5), S(36.0), S(27.5), S(1.7), pal["fog_gray"])
    c.capsule(S(11.0), S(33.0), S(33.0), S(33.0), S(1.7), pal["fog_gray"])
    c.capsule(S(14.0), S(38.5), S(30.0), S(38.5), S(1.6), pal["fog_gray"])
    c.save(f"weather_fog{suffix}.png")


def gen_lightning(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    draw_cloud(c, 3.5, 4.5, 0.95, pal["cloud_dark"])
    bolt = [
        (S(24.0), S(24.0)),
        (S(17.5), S(33.0)),
        (S(22.5), S(33.0)),
        (S(19.0), S(41.0)),
        (S(28.0), S(30.5)),
        (S(23.0), S(30.5)),
    ]
    c.polygon(bolt, pal["bolt_yellow"])
    c.save(f"weather_lightning{suffix}.png")


def gen_lightning_rainy(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    draw_cloud(c, 3.5, 4.5, 0.95, pal["cloud_dark"])
    c.capsule(S(13.0), S(28.5), S(10.8), S(36.5), S(1.35), pal["rain_blue"])
    c.capsule(S(33.0), S(28.5), S(30.8), S(36.5), S(1.35), pal["rain_blue"])
    bolt = [
        (S(24.0), S(24.0)),
        (S(18.0), S(32.5)),
        (S(22.5), S(32.5)),
        (S(19.5), S(40.5)),
        (S(27.5), S(30.5)),
        (S(23.0), S(30.5)),
    ]
    c.polygon(bolt, pal["bolt_yellow"])
    c.save(f"weather_lightning_rainy{suffix}.png")


def gen_windy(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    c.capsule(S(6.0), S(15.0), S(31.0), S(15.0), S(1.8), pal["wind_blue"])
    c.capsule(S(31.0), S(15.0), S(34.5), S(11.5), S(1.7), pal["wind_blue"])
    c.capsule(S(8.0), S(22.5), S(36.5), S(22.5), S(1.8), pal["cloud_light"])
    c.capsule(S(12.0), S(30.0), S(29.0), S(30.0), S(1.8), pal["wind_blue"])
    c.capsule(S(29.0), S(30.0), S(32.5), S(33.5), S(1.7), pal["wind_blue"])
    c.save(f"weather_windy{suffix}.png")


def gen_windy_variant(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    draw_cloud(c, 5.5, 4.0, 0.85, pal["cloud_light"])
    c.capsule(S(7.0), S(28.5), S(33.0), S(28.5), S(1.65), pal["wind_blue"])
    c.capsule(S(33.0), S(28.5), S(36.0), S(25.5), S(1.55), pal["wind_blue"])
    c.capsule(S(11.0), S(35.0), S(29.5), S(35.0), S(1.65), pal["wind_blue"])
    c.capsule(S(29.5), S(35.0), S(32.5), S(38.0), S(1.55), pal["wind_blue"])
    c.save(f"weather_windy_variant{suffix}.png")


def gen_exceptional(pal, suffix):
    c = Canvas(WEATHER_SIZE, WEATHER_SIZE)
    # Rounded warning triangle + crisp exclamation mark
    tri = [
        (S(22.0), S(6.5)),
        (S(38.0), S(36.5)),
        (S(6.0), S(36.5)),
    ]
    c.polygon(tri, pal["warn_bg"])
    c.capsule(S(22.0), S(6.5), S(38.0), S(36.5), S(2.0), pal["warn_bg"])
    c.capsule(S(38.0), S(36.5), S(6.0), S(36.5), S(2.0), pal["warn_bg"])
    c.capsule(S(6.0), S(36.5), S(22.0), S(6.5), S(2.0), pal["warn_bg"])
    c.capsule(S(22.0), S(16.0), S(22.0), S(26.0), S(2.0), pal["warn_fg"])
    c.circle(S(22.0), S(31.8), S(2.2), pal["warn_fg"])
    c.save(f"weather_exceptional{suffix}.png")


def gen_alarm_icon(pal, suffix):
    c = Canvas(16, 16)
    col = pal["alarm"]
    c.circle(8.0, 3.0, 1.2, col)
    c.circle(8.0, 7.2, 4.2, col)
    c.rect(3.8, 7.2, 12.2, 11.5, col)
    c.capsule(2.6, 11.8, 13.4, 11.8, 1.1, col)
    c.circle(8.0, 13.6, 1.5, col)
    c.save(f"icon_alarm{suffix}.png")


def gen_door_icon():
    c = Canvas(14, 14)
    c.capsule(2.5, 2.0, 11.5, 2.0, 0.9, WHITE)
    c.capsule(2.5, 2.0, 2.5, 12.0, 0.9, WHITE)
    c.capsule(11.5, 2.0, 11.5, 12.0, 0.9, WHITE)
    c.polygon([(3.2, 2.6), (8.6, 4.0), (8.6, 12.2), (3.2, 11.4)], WHITE)
    c.save("icon_door.png")


WEATHER_GENERATORS = (
    gen_sunny,
    gen_clear_night,
    gen_partlycloudy,
    gen_cloudy,
    gen_rainy,
    gen_pouring,
    gen_hail,
    gen_snowy,
    gen_snowy_rainy,
    gen_fog,
    gen_lightning,
    gen_lightning_rainy,
    gen_windy,
    gen_windy_variant,
    gen_exceptional,
)


def main():
    count = 0
    for pal, suffix in ((PALETTE_STANDARD, ""), (PALETTE_DARK, "_dark")):
        for fn in WEATHER_GENERATORS:
            fn(pal, suffix)
            count += 1
        gen_alarm_icon(pal, suffix)
        count += 1
    gen_door_icon()
    count += 1
    print(f"Generated {count} PNG icons in {OUT_DIR} (weather icons: {WEATHER_SIZE}x{WEATHER_SIZE})")


if __name__ == "__main__":
    main()
