# align_head.static.py — 透明角色帧按“头盔中心 + 脚底基线”对齐到固定画布
# usage: align_head OUTDIR CW CH PIVOT_X PIVOT_Y f1.png f2.png ...

extern fn img_open(path: str) -> ptr from "imgproc"
extern fn img_save(im: ptr, path: str) -> int from "imgproc"
extern fn img_free(im: ptr) -> int from "imgproc"
extern fn img_width(im: ptr) -> int from "imgproc"
extern fn img_height(im: ptr) -> int from "imgproc"
extern fn img_convert(im: ptr, mode: str) -> ptr from "imgproc"
extern fn img_crop(im: ptr, x: int, y: int, w: int, h: int) -> ptr from "imgproc"
extern fn img_new(w: int, h: int) -> ptr from "imgproc"
extern fn img_fill(im: ptr, rgba: int) -> int from "imgproc"
extern fn img_getpixel(im: ptr, x: int, y: int) -> int from "imgproc"
extern fn img_alpha_composite_at(base: ptr, over: ptr, x: int, y: int) -> ptr from "imgproc"


def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 7:
        print("usage: align_head OUTDIR CW CH PIVOT_X PIVOT_Y f1.png f2.png ...")
        exit_program(1)
    outdir: str = py_list_ref(args, 1)
    cw: int = string_to_int(py_list_ref(args, 2))
    ch: int = string_to_int(py_list_ref(args, 3))
    px: int = string_to_int(py_list_ref(args, 4))
    py: int = string_to_int(py_list_ref(args, 5))
    nf: int = n - 6
    os_mkdir(outdir)

    i: int = 0
    while i < nf:
        src: str = py_list_ref(args, 6 + i)
        im = img_open(src)
        if im is None:
            print("cannot open " + src)
            exit_program(1)
        im = img_convert(im, "RGBA")
        w: int = img_width(im)
        h: int = img_height(im)

        mnx: int = w
        mxx: int = -1
        mny: int = h
        mxy: int = -1
        y: int = 0
        while y < h:
            x: int = 0
            while x < w:
                if img_getpixel(im, x, y) % 256 > 10:
                    if x < mnx:
                        mnx = x
                    if x > mxx:
                        mxx = x
                    if y < mny:
                        mny = y
                    if y > mxy:
                        mxy = y
                x = x + 1
            y = y + 1
        if mxx < 0:
            print("empty frame " + src)
            exit_program(1)

        bw: int = mxx - mnx + 1
        bh: int = mxy - mny + 1

        # 头盔中心 = bbox 顶部 300px 内 alpha 内容的水平中点
        hh: int = 300
        if bh < hh:
            hh = bh
        hx0: int = bw
        hx1: int = -1
        y = 0
        while y < hh:
            x = 0
            while x < bw:
                if img_getpixel(im, mnx + x, mny + y) % 256 > 10:
                    if x < hx0:
                        hx0 = x
                    if x > hx1:
                        hx1 = x
                x = x + 1
            y = y + 1
        if hx1 < 0:
            hx0 = 0
            hx1 = 0
        head_cx: int = int((hx0 + hx1) / 2)

        ox: int = px - head_cx
        oy: int = py - bh
        body = img_crop(im, mnx, mny, bw, bh)
        canvas = img_new(cw, ch)
        img_fill(canvas, 0)
        img_alpha_composite_at(canvas, body, ox, oy)

        if i < 10:
            nm: str = "f0" + string_of_int(i) + ".png"
        else:
            nm: str = "f" + string_of_int(i) + ".png"
        img_save(canvas, outdir + "/" + nm)
        print(nm + " bbox=" + string_of_int(bw) + "x" + string_of_int(bh) + " head_cx=" + string_of_int(head_cx) + " ox=" + string_of_int(ox) + " oy=" + string_of_int(oy))
        img_free(body)
        img_free(canvas)
        img_free(im)
        i = i + 1
    print("aligned " + string_of_int(nf) + " -> " + outdir)


main()
