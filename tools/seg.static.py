# seg.static.py — StaticPy CLI for MobileSAM segmentation (Segment Anything, lightweight).
# usage:
#   seg IN.png OUT.png                         # auto main subject, transparent RGBA
#   seg IN.png OUT.png "x,y;x,y"               # manual points (original pixels)
#   seg IN.png OUT.png "x,y" "1" mask.png 3    # mask mode
#   seg IN.png OUT.png "auto" "" mask.png 1    # auto, mask + white composite
#
# modes: 0=RGBA, 1=white, 2=black, 3=mask

extern fn mobilesam_segment(in_path: str, out_path: str, mask_path: str,
                            points_csv: str, labels_csv: str, mode: int) -> int from "mobilesam"
extern fn mobilesam_auto(in_path: str, out_path: str, mask_path: str,
                         grid: int, iou_thr: float, min_area: float, max_area: float,
                         mode: int) -> int from "mobilesam"


def dflt(args, i: int, d: str) -> str:
    if py_list_length(args) > i:
        return py_list_ref(args, i)
    return d


def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 3:
        print("usage: seg IN.png OUT.png [POINTS|auto] [LABELS] [MASK] [MODE]")
        print("  POINTS: \"x,y;x,y\" in original pixels; empty/auto = automatic main subject")
        print("  MODE: 0=RGBA, 1=white, 2=black, 3=mask")
        exit_program(1)

    src: str = py_list_ref(args, 1)
    dst: str = py_list_ref(args, 2)
    points: str = dflt(args, 3, "")
    labels: str = dflt(args, 4, "")
    mask: str = dflt(args, 5, "")
    mode: int = 0
    if n > 6:
        mode = string_to_int(py_list_ref(args, 6))

    rc: int = 0
    if points == "" or points == "auto" or points == "AUTO":
        rc = mobilesam_auto(src, dst, mask, 16, 0.70, 0.01, 0.65, mode)
    else:
        rc = mobilesam_segment(src, dst, mask, points, labels, mode)

    if rc != 0:
        print("seg failed: " + src)
        exit_program(1)
    print("seg -> " + dst)


main()
