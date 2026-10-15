import sys
from PIL import Image, ImageSequence
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src)
frames, durs = [], []
for f in ImageSequence.Iterator(im):
    durs.append(f.info.get("duration", 100))
    frames.append(f.convert("RGB").transpose(Image.FLIP_LEFT_RIGHT))
frames[0].save(out, save_all=True, append_images=frames[1:], duration=durs, loop=0)
print("saved", out, "frames", len(frames), "dur", set(durs))
