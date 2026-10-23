"""App icon: the ninja drop companion, drawn with the same proportions as
`NinjaDrop` in Views/CompanionView.swift, on the dojo background with a red 水 seal.
Full-bleed square; iOS applies the rounded mask itself.

usage: python3 make_app_icon.py <out.svg> <folder containing make_icons.py>
"""
import math
import sys

sys.path.insert(0, sys.argv[2])
from make_icons import seigaiha  # the wave pattern used in the app

# The companion's frame inside the 1024 icon (same 64:84 aspect as in the app).
W, H = 520.0, 682.5
MIN_X, MIN_Y = 512 - W / 2, 150.0
MID_X, MID_Y = MIN_X + W / 2, MIN_Y + H / 2
MAX_X, MAX_Y = MIN_X + W, MIN_Y + H
R = W / 2
CY = MAX_Y - R  # centre of the round bottom

# DropShape from CompanionView.swift
DROP = (f"M{MID_X} {MIN_Y} "
        f"C {MID_X + W * 0.08} {MIN_Y + H * 0.2}, {MAX_X} {MIN_Y + H * 0.4}, {MAX_X} {CY} "
        f"A {R} {R} 0 0 1 {MIN_X} {CY} "
        f"C {MIN_X} {MIN_Y + H * 0.4}, {MID_X - W * 0.08} {MIN_Y + H * 0.2}, {MID_X} {MIN_Y} Z")

# Water level like the app at ~80 % progress, with its wave (FillBand).
LEVEL = 0.8
surface = MAX_Y - H * LEVEL
amp = H * 0.025
wave = " ".join(
    f"L {MIN_X + W * i / 24:.1f} {surface + math.sin(1.2 + i / 24 * 2 * math.pi) * amp:.1f}" for i in range(25)
)
WATER = f"M {MIN_X} {MAX_Y} L {MIN_X} {surface} {wave} L {MAX_X} {MAX_Y} Z"

# Mask band and eyes (NinjaDrop: capsule 0.92w x 0.17h, eye frame 0.52w, gap 0.16w, offset 0.12h).
band_y = MID_Y + H * 0.12
band_w, band_h = W * 0.92, H * 0.17
eyes_w, eyes_h, gap = W * 0.52, H * 0.075, W * 0.16
eye_w = (eyes_w - gap) / 2
left_cx = MID_X - gap / 2 - eye_w / 2
right_cx = MID_X + gap / 2 + eye_w / 2

# Headband tails: capsules 0.36w x 0.075h, rotated 18° and 40° around their left end,
# which sits at (midX + 0.62w - 0.18w, band_y).
tail_w, tail_h = W * 0.36, H * 0.075
tail_x = MID_X + W * 0.62 - tail_w / 2


def tail(angle, color):
    return (f'<rect x="{tail_x:.1f}" y="{band_y - tail_h / 2:.1f}" width="{tail_w:.1f}" height="{tail_h:.1f}" '
            f'rx="{tail_h / 2:.1f}" fill="{color}" transform="rotate({angle} {tail_x:.1f} {band_y:.1f})"/>')


def eye(cx, angle):
    return (f'<rect x="{cx - eye_w / 2:.1f}" y="{band_y - eyes_h / 2:.1f}" width="{eye_w:.1f}" height="{eyes_h:.1f}" '
            f'rx="{eyes_h / 2:.1f}" fill="#FFFFFF" transform="rotate({angle} {cx:.1f} {band_y:.1f})"/>')


svg = f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="bg" cx="0.5" cy="0.32" r="0.85">
      <stop offset="0" stop-color="#2E63BE"/>
      <stop offset="0.6" stop-color="#1D4590"/>
      <stop offset="1" stop-color="#0F2A5C"/>
    </radialGradient>
    <linearGradient id="water" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#6FB3F5"/>
      <stop offset="1" stop-color="#3D88E2"/>
    </linearGradient>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#06152F" flood-opacity="0.45"/>
    </filter>
    <clipPath id="dropClip"><path d="{DROP}"/></clipPath>
  </defs>

  <rect width="1024" height="1024" fill="url(#bg)"/>
  {seigaiha(1024, 1024, 120, "#FFFFFF", "none", 0.035)}

  <!-- headband tails (red, like the highest Dan belt) behind the drop -->
  {tail(18, "#C9302A")}
  {tail(40, "#A8241F")}

  <!-- drop: white body, water fill with wave, ink outline -->
  <g filter="url(#shadow)"><path d="{DROP}" fill="#FFFFFF"/></g>
  <g clip-path="url(#dropClip)">
    <path d="{WATER}" fill="url(#water)"/>
  </g>
  <path d="{DROP}" fill="none" stroke="#0A1C40" stroke-width="{W * 0.045:.1f}" stroke-linejoin="round"/>

  <!-- mask band and focused eyes -->
  <rect x="{MID_X - band_w / 2:.1f}" y="{band_y - band_h / 2:.1f}" width="{band_w:.1f}" height="{band_h:.1f}" rx="{band_h / 2:.1f}" fill="#1F1F1F"/>
  {eye(left_cx, 10)}
  {eye(right_cx, -10)}

  <!-- red seal with 水 (water) -->
  <g transform="translate(812 838)">
    <rect x="-74" y="-74" width="148" height="148" rx="22" fill="#C2332B"/>
    <rect x="-62" y="-62" width="124" height="124" rx="14" fill="none" stroke="#F5EFE3" stroke-width="6" opacity="0.9"/>
    <text x="0" y="34" font-family="Hiragino Mincho ProN, Songti SC, serif" font-size="100" font-weight="600" fill="#F5EFE3" text-anchor="middle">水</text>
  </g>
</svg>'''

open(sys.argv[1], "w", encoding="utf-8").write(svg)
print("ok")
