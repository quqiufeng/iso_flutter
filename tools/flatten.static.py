# flatten.static.py — 把透明 PNG 合成到纯色底（StaticPy + imgproc）
# usage: flatten IN.png OUT.png BG_RGBA

extern fn img_open(path: str) -> ptr from "imgproc"
extern fn img_save(im: ptr, path: str) -> int from "imgproc"
extern fn img_free(im: ptr) -> int from "imgproc"
extern fn img_width(im: ptr) -> int from "imgproc"
extern fn img_height(im: ptr) -> int from "imgproc"
extern fn img_convert(im: ptr, mode: str) -> ptr from "imgproc"
extern fn img_new(w: int, h: int) -> ptr from "imgproc"
extern fn img_fill(im: ptr, rgba: int) -> int from "imgproc"
extern fn img_alpha_composite_at(base: ptr, over: ptr, x: int, y: int) -> ptr from "imgproc"


def main():
    args = list_to_py_list(argv())
    if py_list_length(args) < 4:
        print("usage: flatten IN.png OUT.png BG_RGBA")
        exit_program(1)
    src: str = py_list_ref(args, 1)
    out: str = py_list_ref(args, 2)
    bg: int = string_to_int(py_list_ref(args, 3))
    im = img_open(src)
    if im is None:
        print("cannot open " + src)
        exit_program(1)
    im = img_convert(im, "RGBA")
    w: int = img_width(im)
    h: int = img_height(im)
    canvas = img_new(w, h)
    img_fill(canvas, bg)
    img_alpha_composite_at(canvas, im, 0, 0)
    img_save(canvas, out)
    img_free(canvas)
    img_free(im)
    print("flatten -> " + out)


main()
