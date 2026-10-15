#!/usr/bin/env python3
"""生成 OpenPose(COCO-18) 走路姿势帧序列，供 sd-cli --control-video 用。
侧视：L/R 用微小水平偏移区分远近。角度(度)：髋前后摆、膝弯曲、肩臂前后摆。
本版 = arm2 原版，仅髋角 ±36 → ±28（步幅调小一点），其余完全不变。
"""
import os, math
from PIL import Image, ImageDraw

W, H = 512, 768
CX = W // 2

def deg(d): return math.radians(d)

def draw_frame(a):
    """a: dict 关节角度(度)。返回 PIL.Image。"""
    im = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(im)

    hip_y, neck_y, head_y = 460, 250, 180
    thigh, shin = 140, 140
    uarm, farm = 95, 95
    sho_y = neck_y + 8

    def leg(side, hip_deg, knee_deg, ankle_deg, dx):
        hx = CX + dx
        # 大腿：从髋向下，+向前(+x)
        hx1 = hx + thigh * math.sin(deg(hip_deg))
        hy1 = hip_y + thigh * math.cos(deg(hip_deg))
        shin_dir = hip_deg - knee_deg            # 膝向后弯
        hx2 = hx1 + shin * math.sin(deg(shin_dir))
        hy2 = hy1 + shin * math.cos(deg(shin_dir))
        foot = ankle_deg
        fx = hx2 + 26 * math.sin(deg(shin_dir + foot))
        fy = min(H - 30, hy2 + 15)
        return {"hip": (hx, hip_y), "knee": (hx1, hy1), "ankle": (hx2, hy2), "foot": (fx, fy)}

    def arm(side, sho_deg, elb_deg, dx):
        sx = CX + dx
        sx1 = sx + uarm * math.sin(deg(sho_deg))
        sy1 = sho_y + uarm * math.cos(deg(sho_deg))
        fore_dir = sho_deg - elb_deg
        sx2 = sx1 + farm * math.sin(deg(fore_dir))
        sy2 = sy1 + farm * math.cos(deg(fore_dir))
        return {"shoulder": (sx, sho_y), "elbow": (sx1, sy1), "wrist": (sx2, sy2)}

    # 近侧(带 +dx) / 远侧(-dx)
    Lleg = leg("L", a["hipL"], a["kneeL"], a["ankleL"], -10)
    Rleg = leg("R", a["hipR"], a["kneeR"], a["ankleR"], +12)
    Larm = arm("L", a["shoL"], a["elbL"], -12)
    Rarm = arm("R", a["shoR"], a["elbR"], +14)

    neck = (CX, neck_y); nose = (CX, head_y); head = (CX, head_y - 8)
    eyeR = (CX + 8, head_y - 6); earR = (CX - 8, head_y - 2)

    limbs = [
        # (p1, p2, RGB)  顺序：鼻-颈 / 颈-肩 / 臂 / 颈-髋 / 腿
        (nose, neck, (255, 0, 0)),
        (neck, Rarm["shoulder"], (255, 85, 0)), (Rarm["shoulder"], Rarm["elbow"], (255, 170, 0)), (Rarm["elbow"], Rarm["wrist"], (255, 255, 0)),
        (neck, Larm["shoulder"], (170, 255, 0)), (Larm["shoulder"], Larm["elbow"], (85, 255, 0)), (Larm["elbow"], Larm["wrist"], (0, 255, 0)),
        (neck, Rleg["hip"], (0, 255, 85)), (Rleg["hip"], Rleg["knee"], (0, 255, 170)), (Rleg["knee"], Rleg["ankle"], (0, 255, 255)), (Rleg["ankle"], Rleg["foot"], (0, 255, 255)),
        (neck, Lleg["hip"], (0, 170, 255)), (Lleg["hip"], Lleg["knee"], (0, 85, 255)), (Lleg["knee"], Lleg["ankle"], (0, 0, 255)), (Lleg["ankle"], Lleg["foot"], (0, 0, 255)),
    ]
    for (x1, y1), (x2, y2), col in limbs:
        d.line([x1, y1, x2, y2], fill=col, width=6)
    # 关节圆点
    pts = [nose, neck, eyeR, earR, Rarm["shoulder"], Rarm["elbow"], Rarm["wrist"], Larm["shoulder"], Larm["elbow"], Larm["wrist"]]
    for legd in (Rleg, Lleg):
        pts += [legd["hip"], legd["knee"], legd["ankle"]]
    for p in pts:
        d.ellipse([p[0]-4, p[1]-4, p[0]+4, p[1]+4], fill=(255, 255, 255))
    return im

def lerp(a, b, t): return a + (b - a) * t

# arm2 原版，仅髋 ±36 → ±22（步幅再小一档），手臂/膝完全不变
KEY = [
    dict(hipL=22, kneeL=8, ankleL=5,  hipR=-22, kneeR=20, ankleR=12, shoL=-26, elbL=38, shoR=26,  elbR=42),
    dict(hipL=5,  kneeL=5, ankleL=0,  hipR=-5,  kneeR=38, ankleR=16, shoL=-8,  elbL=34, shoR=8,   elbR=44),
    dict(hipL=-22,kneeL=20,ankleL=12, hipR=22,  kneeR=8,  ankleR=5,  shoL=26,  elbL=42, shoR=-26, elbR=38),
    dict(hipL=-5, kneeL=38,ankleL=16, hipR=5,   kneeR=5,  ankleR=0,  shoL=8,   elbL=44, shoR=-8,  elbR=34),
]

def blend(k0, k1, t):
    return {key: lerp(k0[key], k1[key], t) for key in k0}

def main():
    outdir = os.environ.get("OUTDIR") or os.path.join(os.path.dirname(__file__), "walk6")
    os.makedirs(outdir, exist_ok=True)
    N = 16
    for i in range(N):
        f = i / N * len(KEY)
        j = int(f) % len(KEY); t = f - int(f)
        a = blend(KEY[j], KEY[(j + 1) % len(KEY)], t)
        draw_frame(a).save(os.path.join(outdir, f"f{i:02d}.png"))
    # 预览一张
    draw_frame(KEY[0]).save(os.path.join(os.path.dirname(__file__), "preview_contact.png"))
    draw_frame(KEY[1]).save(os.path.join(os.path.dirname(__file__), "preview_passing.png"))
    print("生成", N, "帧 →", outdir)

main()
