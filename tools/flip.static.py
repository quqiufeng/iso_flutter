# flip.static.py — 水平镜像（左走 → 右走），保留 alpha / 多帧延迟
# usage: flip IN.png OUT.png

extern fn img_open(path: str) -> ptr from "imgproc"
extern fn img_save(im: ptr, path: str) -> int from "imgproc"
extern fn img_free(im: ptr) -> int from "imgproc"
extern fn img_convert(im: ptr, mode: str) -> ptr from "imgproc"
extern fn img_mirror(im: ptr) -> ptr from "imgproc"


def main():
    args = list_to_py_list(argv())
    if py_list_length(args) < 3:
        print("usage: flip IN.png OUT.png")
        exit_program(1)
    src: str = py_list_ref(args, 1)
    out: str = py_list_ref(args, 2)
    im = img_open(src)
    if im is None:
        print("cannot open " + src)
        exit_program(1)
    im = img_convert(im, "RGBA")
    m = img_mirror(im)
    rc: int = img_save(m, out)
    img_free(m)
    img_free(im)
    if rc != 0:
        print("save failed: " + out)
        exit_program(1)
    print("flip -> " + out)


main()
