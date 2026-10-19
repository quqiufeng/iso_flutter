# hstack.static.py — 把多张透明 PNG 水平拼接成一条 strip（StaticPy + imgproc）
# usage: hstack OUT.png GAP f1.png f2.png ...

extern fn img_open(path: str) -> ptr from "imgproc"
extern fn img_save(im: ptr, path: str) -> int from "imgproc"
extern fn img_free(im: ptr) -> int from "imgproc"
extern fn img_width(im: ptr) -> int from "imgproc"
extern fn img_height(im: ptr) -> int from "imgproc"
extern fn img_new(w: int, h: int) -> ptr from "imgproc"
extern fn img_fill(im: ptr, rgba: int) -> int from "imgproc"
extern fn img_alpha_composite_at(base: ptr, over: ptr, x: int, y: int) -> ptr from "imgproc"


def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 4:
        print("usage: hstack OUT.png GAP f1.png f2.png ...")
        exit_program(1)
    out: str = py_list_ref(args, 1)
    gap: int = string_to_int(py_list_ref(args, 2))
    nf: int = n - 3

    total: int = 0
    maxh: int = 0
    i: int = 0
    while i < nf:
        im = img_open(py_list_ref(args, 3 + i))
        if im is not None:
            total = total + img_width(im)
            if i > 0:
                total = total + gap
            h: int = img_height(im)
            if h > maxh:
                maxh = h
            img_free(im)
        i = i + 1

    canvas = img_new(total, maxh)
    if canvas is None:
        print("imgproc: img_new failed")
        exit_program(1)
    img_fill(canvas, 0)

    x: int = 0
    i = 0
    while i < nf:
        im = img_open(py_list_ref(args, 3 + i))
        if im is not None:
            img_alpha_composite_at(canvas, im, x, 0)
            x = x + img_width(im) + gap
            img_free(im)
        i = i + 1

    rc: int = img_save(canvas, out)
    img_free(canvas)
    if rc != 0:
        print("imgproc: save failed")
        exit_program(1)
    print("hstack " + string_of_int(nf) + " -> " + out + " (" + string_of_int(total) + "x" + string_of_int(maxh) + ")")


main()
