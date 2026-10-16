# mirror_gif.py — 镜像 GIF（改用 StaticPy imgproc，无 PIL；GIF 保留索引+调色板 → 无损）
import sys
import imgproc_py as P

src, out = sys.argv[1], sys.argv[2]
im = P.img_open(src.encode())
if not im:
    sys.exit("imgproc: cannot open " + src)
o = P.img_transpose(im, 0)          # 0 = FLIP_LEFT_RIGHT（索引帧无损）
rc = P.img_save(o, out.encode())
n = P.img_count(o)
durs = sorted({P.img_delay(o, i) for i in range(n)})
P.img_free(im); P.img_free(o)
if rc != 0:
    sys.exit("imgproc: save failed rc=%d" % rc)
print("saved", out, "frames", n, "dur", durs)
