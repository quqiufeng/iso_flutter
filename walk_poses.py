#!/usr/bin/env python3
"""生成 OpenPose(COCO-18) 走路姿势帧序列（改用 StaticPy imgproc 绘制，无 PIL）。
侧视：L/R 用微小水平偏移区分远近。★调步幅用 env LEGX（腿部横向压缩），不要改 KEY 髋角。
"""
import os, math
import imgproc_py as P

W, H = 512, 768
CX = W // 2

LEGX = float(os.environ.get("LEGX", "1.0"))
ARMX = float(os.environ.get("ARMX", "1.0"))
YUP = int(os.environ.get("YUP", "0"))
HAND = int(os.environ.get("HAND", "1"))   # 是否画 OpenPose 手部 21 关键点（约束手的漂移）

# OpenPose 手 21 关键点：局部坐标 (前向, 侧向)，单位=手长；沿前臂方向摆放
HAND_OFF = [
    (0.00, 0.00),                                                     # 0 腕
    (0.16, -0.34), (0.34, -0.52), (0.52, -0.60), (0.68, -0.64),       # 1-4 拇指
    (0.26, -0.20), (0.62, -0.26), (0.90, -0.26), (1.10, -0.24),       # 5-8 食指
    (0.22,  0.00), (0.64,  0.00), (0.94,  0.00), (1.16,  0.00),       # 9-12 中指
    (0.22,  0.20), (0.62,  0.26), (0.90,  0.28), (1.08,  0.28),       # 13-16 无名
    (0.20,  0.40), (0.52,  0.50), (0.74,  0.56), (0.90,  0.60),       # 17-20 小指
]
HAND_EDGES = [
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8),
    (0, 9), (9, 10), (10, 11), (11, 12),
    (0, 13), (13, 14), (14, 15), (15, 16),
    (0, 17), (17, 18), (18, 19), (19, 20),
    (5, 9), (9, 13), (13, 17),                                        # 掌
]
# 每根手指颜色（用洋红系——身体调色板里没有，避免 ControlNet 把手误认成手臂）
HAND_COLORS = [(255, 0, 255), (255, 0, 200), (230, 0, 255), (255, 60, 255), (200, 0, 230)]
def _finger(i):
    if i <= 4: return 0
    if i <= 8: return 1
    if i <= 12: return 2
    if i <= 16: return 3
    return 4

def draw_hand(im, elbow, wrist, length=22.0):
    ex, ey = elbow; wx, wy = wrist
    dx, dy = wx - ex, wy - ey
    L = math.hypot(dx, dy) or 1.0
    ux, uy = dx / L, dy / L          # 前向（沿前臂）
    px, py = -uy, ux                 # 侧向
    pts = [(wx + ux * f * length + px * s * length, wy + uy * f * length + py * s * length)
           for (f, s) in HAND_OFF]
    for a, b in HAND_EDGES:
        col = HAND_COLORS[_finger(b)]
        x1, y1 = pts[a]; x2, y2 = pts[b]
        P.img_draw_line(im, int(round(x1)), int(round(y1)), int(round(x2)), int(round(y2)), rgba(col), 2)
    for (x, y) in pts:
        P.img_draw_ellipse(im, int(x - 2), int(y - 2), int(x + 2), int(y + 2), 0, 0xFFFFFFFF)

def deg(d): return math.radians(d)
def rgba(c): return (c[0] << 24) | (c[1] << 16) | (c[2] << 8) | 0xFF

def draw_frame(a):
    im = P.img_new(W, H)
    P.img_fill(im, 0x000000FF)   # 黑底不透明

    hip_y, neck_y, head_y = 460, 250, 180
    thigh, shin = 140, 140
    uarm, farm = 95, 95
    sho_y = neck_y + 8

    def leg(hip_deg, knee_deg, ankle_deg, dx):
        hx = CX + dx
        hx1 = hx + LEGX * thigh * math.sin(deg(hip_deg))
        hy1 = hip_y + thigh * math.cos(deg(hip_deg))
        sd = hip_deg - knee_deg
        hx2 = hx1 + LEGX * shin * math.sin(deg(sd))
        hy2 = hy1 + shin * math.cos(deg(sd))
        fx = hx2 + LEGX * 26 * math.sin(deg(sd + ankle_deg))
        fy = min(H - 30, hy2 + 15)
        return {"hip": (hx, hip_y), "knee": (hx1, hy1), "ankle": (hx2, hy2), "foot": (fx, fy)}

    def arm(sho_deg, elb_deg, dx):
        sx = CX + dx
        sx1 = sx + ARMX * uarm * math.sin(deg(sho_deg))
        sy1 = sho_y + uarm * math.cos(deg(sho_deg))
        fd = sho_deg - elb_deg
        sx2 = sx1 + ARMX * farm * math.sin(deg(fd))
        sy2 = sy1 + farm * math.cos(deg(fd))
        return {"shoulder": (sx, sho_y), "elbow": (sx1, sy1), "wrist": (sx2, sy2)}

    Lleg = leg(a["hipL"], a["kneeL"], a["ankleL"], -10)
    Rleg = leg(a["hipR"], a["kneeR"], a["ankleR"], +12)
    Larm = arm(a["shoL"], a["elbL"], -12)
    Rarm = arm(a["shoR"], a["elbR"], +14)

    neck = (CX, neck_y); nose = (CX, head_y)
    eyeR = (CX + 8, head_y - 6); earR = (CX - 8, head_y - 2)

    limbs = [
        (nose, neck, (255, 0, 0)),
        (neck, Rarm["shoulder"], (255, 85, 0)), (Rarm["shoulder"], Rarm["elbow"], (255, 170, 0)), (Rarm["elbow"], Rarm["wrist"], (255, 255, 0)),
        (neck, Larm["shoulder"], (170, 255, 0)), (Larm["shoulder"], Larm["elbow"], (85, 255, 0)), (Larm["elbow"], Larm["wrist"], (0, 255, 0)),
        (neck, Rleg["hip"], (0, 255, 85)), (Rleg["hip"], Rleg["knee"], (0, 255, 170)), (Rleg["knee"], Rleg["ankle"], (0, 255, 255)), (Rleg["ankle"], Rleg["foot"], (0, 255, 255)),
        (neck, Lleg["hip"], (0, 170, 255)), (Lleg["hip"], Lleg["knee"], (0, 85, 255)), (Lleg["knee"], Lleg["ankle"], (0, 0, 255)), (Lleg["ankle"], Lleg["foot"], (0, 0, 255)),
    ]
    for (x1, y1), (x2, y2), col in limbs:
        P.img_draw_line(im, int(round(x1)), int(round(y1)), int(round(x2)), int(round(y2)), rgba(col), 6)
    pts = [nose, neck, eyeR, earR, Rarm["shoulder"], Rarm["elbow"], Rarm["wrist"], Larm["shoulder"], Larm["elbow"], Larm["wrist"]]
    for legd in (Rleg, Lleg):
        pts += [legd["hip"], legd["knee"], legd["ankle"]]
    for p in pts:
        P.img_draw_ellipse(im, int(p[0] - 4), int(p[1] - 4), int(p[0] + 4), int(p[1] + 4), 0, 0xFFFFFFFF)
    if HAND:
        draw_hand(im, Rarm["elbow"], Rarm["wrist"])
        draw_hand(im, Larm["elbow"], Larm["wrist"])
    return im

def shift_up(im, dy):
    """画面整体上移 dy 像素（底部留黑）。"""
    if dy <= 0:
        return im
    return P.img_pad(im, 0, 0, 0, dy, 0x000000FF)

def save(im, path):
    rc = P.img_save(im, path.encode())
    P.img_free(im)
    if rc != 0:
        raise RuntimeError("save failed: %s" % path)

def lerp(a, b, t): return a + (b - a) * t

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
        save(shift_up(draw_frame(a), YUP), os.path.join(outdir, "f%02d.png" % i))
    save(shift_up(draw_frame(KEY[0]), YUP), os.path.join(os.path.dirname(__file__), "preview_contact.png"))
    save(shift_up(draw_frame(KEY[1]), YUP), os.path.join(os.path.dirname(__file__), "preview_passing.png"))
    print("生成", N, "帧 →", outdir)

main()
