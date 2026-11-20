#!/usr/bin/env python3
"""
Generate anti-aliased RGBA PNG weather & status icons for HAScreenSaver
using only Python standard library (4x supersampling for crisp 320x240 rendering).
"""

import math
import os
import struct
import zlib

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT_DIR, "radio-applet", "HAScreenSaver", "icons")


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


SUN_GOLD = (255, 209, 92, 255)
SUN_RAY = (255, 196, 61, 255)
CLOUD_LIGHT = (224, 232, 242, 255)
CLOUD_MID = (182, 194, 210, 255)
CLOUD_DARK = (146, 160, 178, 255)
RAIN_BLUE = (92, 184, 255, 255)
POUR_BLUE = (62, 160, 255, 255)
SNOW_ICE = (232, 246, 255, 255)
FOG_GRAY = (176, 190, 208, 235)
BOLT_YELLOW = (255, 214, 64, 255)
MOON_LIGHT = (220, 232, 248, 255)
WIND_BLUE = (180, 212, 236, 240)
ALARM_MUTED = (142, 152, 168, 255)
WHITE = (255, 255, 255, 255)


def draw_cloud(c, ox, oy, scale, color):
    # Clean fluffy cloud made of 3 overlapping circles + rounded base
    c.circle(ox + 12 * scale, oy + 14 * scale, 7.2 * scale, color)
    c.circle(ox + 20 * scale, oy + 10 * scale, 8.8 * scale, color)
    c.circle(ox + 29 * scale, oy + 14 * scale, 6.8 * scale, color)
    c.capsule(
        ox + 12 * scale,
        oy + 17.5 * scale,
        ox + 29 * scale,
        oy + 17.5 * scale,
        3.8 * scale,
        color,
    )


def gen_sunny():
    c = Canvas(44, 44)
    cx, cy = 22.0, 22.0
    c.circle(cx, cy, 9.0, SUN_GOLD)
    for i in range(8):
        ang = i * (math.pi / 4.0)
        x1 = cx + math.cos(ang) * 12.5
        y1 = cy + math.sin(ang) * 12.5
        x2 = cx + math.cos(ang) * 16.8
        y2 = cy + math.sin(ang) * 16.8
        c.capsule(x1, y1, x2, y2, 1.55, SUN_RAY)
    c.save("weather_sunny.png")


def gen_clear_night():
    c = Canvas(44, 44)
    c.circle(21.0, 22.0, 12.0, MOON_LIGHT)
    c.subtract_circle(26.5, 18.0, 10.5)
    # Two subtle stars
    c.circle(33.5, 12.5, 1.4, SUN_GOLD)
    c.circle(36.0, 20.5, 1.0, MOON_LIGHT)
    c.save("weather_clear_night.png")


def gen_partlycloudy():
    c = Canvas(44, 44)
    cx, cy = 15.5, 16.5
    c.circle(cx, cy, 6.8, SUN_GOLD)
    for i in range(8):
        ang = i * (math.pi / 4.0)
        c.capsule(
            cx + math.cos(ang) * 9.5,
            cy + math.sin(ang) * 9.5,
            cx + math.cos(ang) * 12.2,
            cy + math.sin(ang) * 12.2,
            1.25,
            SUN_RAY,
        )
    draw_cloud(c, 8.0, 14.5, 0.92, CLOUD_LIGHT)
    c.save("weather_partlycloudy.png")


def gen_cloudy():
    c = Canvas(44, 44)
    draw_cloud(c, 10.0, 8.5, 0.78, CLOUD_MID)
    draw_cloud(c, 3.0, 13.5, 0.96, CLOUD_LIGHT)
    c.save("weather_cloudy.png")


def gen_rainy():
    c = Canvas(44, 44)
    draw_cloud(c, 3.5, 5.5, 0.95, CLOUD_LIGHT)
    for x in (14.5, 22.5, 30.5):
        c.capsule(x, 29.0, x - 2.4, 36.0, 1.45, RAIN_BLUE)
    c.save("weather_rainy.png")


def gen_pouring():
    c = Canvas(44, 44)
    draw_cloud(c, 3.5, 4.5, 0.95, CLOUD_DARK)
    for x in (11.5, 17.5, 23.5, 29.5, 35.0):
        c.capsule(x, 27.5, x - 3.2, 37.5, 1.35, POUR_BLUE)
    c.save("weather_pouring.png")


def gen_snowy():
    c = Canvas(44, 44)
    draw_cloud(c, 3.5, 5.5, 0.95, CLOUD_LIGHT)
    for fx, fy in ((14.0, 32.5), (22.5, 35.0), (31.0, 32.5)):
        c.circle(fx, fy, 2.3, SNOW_ICE)
    c.save("weather_snowy.png")


def gen_fog():
    c = Canvas(44, 44)
    draw_cloud(c, 4.5, 4.0, 0.88, CLOUD_MID)
    c.capsule(8.0, 27.5, 36.0, 27.5, 1.7, FOG_GRAY)
    c.capsule(11.0, 33.0, 33.0, 33.0, 1.7, FOG_GRAY)
    c.capsule(14.0, 38.5, 30.0, 38.5, 1.6, FOG_GRAY)
    c.save("weather_fog.png")


def gen_lightning():
    c = Canvas(44, 44)
    draw_cloud(c, 3.5, 4.5, 0.95, CLOUD_DARK)
    bolt = [
        (24.0, 24.0),
        (17.5, 33.0),
        (22.5, 33.0),
        (19.0, 41.0),
        (28.0, 30.5),
        (23.0, 30.5),
    ]
    c.polygon(bolt, BOLT_YELLOW)
    c.save("weather_lightning.png")


def gen_windy():
    c = Canvas(44, 44)
    c.capsule(6.0, 15.0, 31.0, 15.0, 1.8, WIND_BLUE)
    c.capsule(31.0, 15.0, 34.5, 11.5, 1.7, WIND_BLUE)
    c.capsule(8.0, 22.5, 36.5, 22.5, 1.8, CLOUD_LIGHT)
    c.capsule(12.0, 30.0, 29.0, 30.0, 1.8, WIND_BLUE)
    c.capsule(29.0, 30.0, 32.5, 33.5, 1.7, WIND_BLUE)
    c.save("weather_windy.png")


def gen_alarm_icon():
    c = Canvas(16, 16)
    # Classic bell silhouette in subtle muted slate matching temperature unit
    c.circle(8.0, 3.0, 1.2, ALARM_MUTED)
    c.circle(8.0, 7.2, 4.2, ALARM_MUTED)
    c.rect(3.8, 7.2, 12.2, 11.5, ALARM_MUTED)
    c.capsule(2.6, 11.8, 13.4, 11.8, 1.1, ALARM_MUTED)
    c.circle(8.0, 13.6, 1.5, ALARM_MUTED)
    c.save("icon_alarm.png")


def gen_door_icon():
    c = Canvas(14, 14)
    # Simple open-door frame + angled door leaf
    c.capsule(2.5, 2.0, 11.5, 2.0, 0.9, WHITE)
    c.capsule(2.5, 2.0, 2.5, 12.0, 0.9, WHITE)
    c.capsule(11.5, 2.0, 11.5, 12.0, 0.9, WHITE)
    c.polygon([(3.2, 2.6), (8.6, 4.0), (8.6, 12.2), (3.2, 11.4)], WHITE)
    c.save("icon_door.png")


def main():
    gen_sunny()
    gen_clear_night()
    gen_partlycloudy()
    gen_cloudy()
    gen_rainy()
    gen_pouring()
    gen_snowy()
    gen_fog()
    gen_lightning()
    gen_windy()
    gen_alarm_icon()
    gen_door_icon()
    print(f"Generated 12 PNG icons in {OUT_DIR}")


if __name__ == "__main__":
    main()
