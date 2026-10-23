"""Generates three app-icon concepts as SVG and an HTML page to compare them."""
import sys

INDIGO = "#1F4FA3"
INDIGO_DARK = "#122F66"
WATER_LIGHT = "#8CC3F7"
WATER = "#4E9BEF"
INK = "#1C1C1E"
SEAL = "#C2332B"
PAPER = "#F5EFE3"

DROP = "M512 150 C 548 300, 762 452, 762 640 A 250 250 0 0 1 262 640 C 262 452, 476 300, 512 150 Z"


def seigaiha(width, height, radius, stroke, fill, opacity=1.0, rings=4):
    """Overlapping fans of concentric half-circles, drawn row by row so each row covers the one above."""
    out = [f'<g opacity="{opacity}">']
    row, y = 0, 0.0
    while y < height + radius:
        x = -radius + (0 if row % 2 == 0 else radius)
        while x < width + radius:
            for i in range(rings):
                r = radius * (rings - i) / rings
                out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{fill}" stroke="{stroke}" stroke-width="{radius * 0.06:.1f}"/>')
            x += radius * 2
        y += radius * 0.5
        row += 1
    out.append("</g>")
    return "\n".join(out)


def ninja_drop():
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{INDIGO}"/><stop offset="1" stop-color="{INDIGO_DARK}"/></linearGradient>
    <linearGradient id="w1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{WATER_LIGHT}"/><stop offset="1" stop-color="{WATER}"/></linearGradient>
    <clipPath id="c1"><rect width="1024" height="1024"/></clipPath>
  </defs>
  <g clip-path="url(#c1)">
    <rect width="1024" height="1024" fill="url(#bg1)"/>
    {seigaiha(1024, 1024, 96, "#FFFFFF", "none", 0.07)}
    <g transform="translate(770 655)">
      <rect x="0" y="-24" width="200" height="48" rx="24" fill="{SEAL}" transform="rotate(22)"/>
      <rect x="0" y="-24" width="170" height="48" rx="24" fill="{SEAL}" transform="rotate(48)"/>
    </g>
    <path d="{DROP}" fill="url(#w1)" stroke="#0B1F45" stroke-width="26" stroke-linejoin="round"/>
    <path d="M430 330 C 395 400, 360 470, 352 540" fill="none" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="30" stroke-linecap="round"/>
    <rect x="232" y="598" width="560" height="118" rx="59" fill="{INK}"/>
    <rect x="352" y="638" width="104" height="38" rx="19" fill="#FFFFFF" transform="rotate(9 404 657)"/>
    <rect x="568" y="638" width="104" height="38" rx="19" fill="#FFFFFF" transform="rotate(-9 620 657)"/>
  </g>
</svg>'''


def enso():
    # Brush circle: a thick arc with a gap, plus a thinner offset stroke for a dry-brush edge.
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <rect width="1024" height="1024" fill="{PAPER}"/>
  <path d="M 700 230 A 320 320 0 1 0 800 430" fill="none" stroke="{INDIGO_DARK}" stroke-width="74" stroke-linecap="round"/>
  <path d="M 682 250 A 300 300 0 1 0 778 440" fill="none" stroke="{PAPER}" stroke-width="10" stroke-linecap="round" stroke-dasharray="40 26 90 30 140 22" opacity="0.8"/>
  <path d="M 812 412 L 836 380" stroke="{INDIGO_DARK}" stroke-width="40" stroke-linecap="round"/>
  <g transform="translate(512 548) scale(0.42) translate(-512 -560)">
    <path d="{DROP}" fill="{INDIGO}"/>
  </g>
  <circle cx="808" cy="824" r="46" fill="{SEAL}"/>
  <text x="808" y="840" font-family="Hiragino Mincho ProN, serif" font-size="46" fill="{PAPER}" text-anchor="middle">水</text>
</svg>'''


def wave_drop():
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg3" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E4EFFC"/></linearGradient>
    <clipPath id="dropclip"><path d="{DROP}"/></clipPath>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg3)"/>
  <g clip-path="url(#dropclip)">
    <rect x="200" y="540" width="624" height="400" fill="{WATER}"/>
    <g transform="translate(0 540)">{seigaiha(1024, 400, 70, WATER, "#7DB6F2", 1.0)}</g>
    <path d="M200 548 C 300 500, 400 600, 512 548 S 724 500, 824 548 L 824 590 L 200 590 Z" fill="#7DB6F2"/>
  </g>
  <path d="{DROP}" fill="none" stroke="{INDIGO}" stroke-width="44" stroke-linejoin="round"/>
</svg>'''


CONCEPTS = [
    ("1 · Ninja drop", "The companion from the app as the icon: drop, mask, red headband tails on indigo with a faint wave pattern. Most recognisable, ties icon and app together.", ninja_drop()),
    ("2 · Ensō + drop", "A Zen brush circle around a small drop, with a red 水 (water) seal. Calm, dojo-like, works in black and white.", enso()),
    ("3 · Wave in a drop", "A drop outline half filled with the seigaiha wave pattern, like the app's progress fill. Clean and on-theme, but less unique.", wave_drop()),
]


def icon(svg, size, radius_ratio=0.225):
    return f'<div class="icon" style="width:{size}px;height:{size}px;border-radius:{size * radius_ratio:.0f}px">{svg}</div>'


cards = []
for title, text, svg in CONCEPTS:
    cards.append(f'''
    <section class="card">
      <h2>{title}</h2>
      <div class="big">{icon(svg, 220)}</div>
      <p>{text}</p>
      <div class="sizes">
        <figure>{icon(svg, 60)}<figcaption>Home screen</figcaption></figure>
        <figure>{icon(svg, 40)}<figcaption>Spotlight</figcaption></figure>
        <figure>{icon(svg, 29)}<figcaption>Settings</figcaption></figure>
      </div>
    </section>''')

homescreen = "".join(
    f'<figure>{icon(svg, 62)}<figcaption>BeWater</figcaption></figure>' for _, _, svg in CONCEPTS
)

html = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Icon Concepts</title>
<style>
  :root {{ --bg: #F5EFE3; --card: #FFFFFF; --text: #1C1C1E; --muted: #6B6B70; --accent: {INDIGO}; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg: #11161F; --card: #1C2230; --text: #F2F2F5; --muted: #9DA3AE; --accent: #5B8DEF; }}
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; padding: 24px 16px 48px; background: var(--bg); color: var(--text);
         font-family: -apple-system, BlinkMacSystemFont, "SF Pro Rounded", system-ui, sans-serif; }}
  h1 {{ margin: 0 0 4px; font-size: 28px; }}
  .lead {{ margin: 0 0 24px; color: var(--muted); }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 16px; max-width: 1000px; }}
  .card {{ background: var(--card); border-radius: 20px; padding: 20px; }}
  .card h2 {{ margin: 0 0 16px; font-size: 18px; color: var(--accent); }}
  .card p {{ color: var(--muted); font-size: 14px; line-height: 1.45; min-height: 60px; }}
  .big {{ display: flex; justify-content: center; }}
  .icon {{ overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,.18); flex: none; }}
  .icon svg {{ width: 100%; height: 100%; display: block; }}
  .sizes {{ display: flex; gap: 20px; align-items: flex-end; }}
  figure {{ margin: 0; display: flex; flex-direction: column; align-items: center; gap: 6px; }}
  figcaption {{ font-size: 11px; color: var(--muted); }}
  .home {{ margin-top: 24px; max-width: 1000px; border-radius: 28px; padding: 24px;
           background: linear-gradient(160deg, #3B5BA5, #9A6FB0 60%, #E8A27C); }}
  .home h2 {{ margin: 0 0 16px; font-size: 16px; color: #fff; }}
  .home .row {{ display: flex; gap: 28px; flex-wrap: wrap; }}
  .home figcaption {{ color: #fff; font-size: 12px; }}
</style>
</head>
<body>
  <h1>App icon concepts</h1>
  <p class="lead">Rough drafts in the app's dojo style. Shown large, at real iOS sizes, and on a wallpaper.</p>
  <div class="grid">{"".join(cards)}</div>
  <div class="home"><h2>On a home screen</h2><div class="row">{homescreen}</div></div>
</body>
</html>'''

out = sys.argv[1]
open(out, "w", encoding="utf-8").write(html)
for i, (_, _, svg) in enumerate(CONCEPTS, 1):
    open(out.replace(".html", f"-{i}.svg"), "w", encoding="utf-8").write(svg)
print("ok")
