# split_grid.static.py — 按行优先把精灵表切成等大格子（StaticPy + imgproc）
# usage: split_grid IN.png OUTDIR COLS ROWS

extern fn img_open(path: str) -> ptr from "imgproc"
extern fn img_save(im: ptr, path: str) -> int from "imgproc"
extern fn img_free(im: ptr) -> int from "imgproc"
extern fn img_width(im: ptr) -> int from "imgproc"
extern fn img_height(im: ptr) -> int from "imgproc"
extern fn img_crop(im: ptr, x: int, y: int, w: int, h: int) -> ptr from "imgproc"


def main():
    args = list_to_py_list(argv())
    if py_list_length(args) < 5:
        print("usage: split_grid IN.png OUTDIR COLS ROWS")
        exit_program(1)
    src: str = py_list_ref(args, 1)
    outdir: str = py_list_ref(args, 2)
    cols: int = string_to_int(py_list_ref(args, 3))
    rows: int = string_to_int(py_list_ref(args, 4))
    os_mkdir(outdir)
    im = img_open(src)
    if im is None:
        print("cannot open " + src)
        exit_program(1)
    w: int = img_width(im)
    h: int = img_height(im)
    cw: int = int(w / cols)
    ch: int = int(h / rows)
    i: int = 0
    r: int = 0
    while r < rows:
        c: int = 0
        while c < cols:
            cell = img_crop(im, c * cw, r * ch, cw, ch)
            if i < 10:
                nm: str = "f0" + string_of_int(i) + ".png"
            else:
                nm: str = "f" + string_of_int(i) + ".png"
            img_save(cell, outdir + "/" + nm)
            img_free(cell)
            c = c + 1
            i = i + 1
        r = r + 1
    img_free(im)
    print("split " + string_of_int(cols) + "x" + string_of_int(rows) + " -> " + outdir)


main()
