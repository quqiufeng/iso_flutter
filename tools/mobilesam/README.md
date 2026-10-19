# MobileSAM seg (StaticPy + ONNX Runtime)

Segment Anything（MobileSAM 轻量版）的 StaticPy 封装，用于给现成游戏素材直接扣图。

## 模型

放在 `/models/mobilesam/`：

```text
mobilesam.encoder.onnx   27MB
mobilesam.decoder.onnx   16MB
config.json
preprocessor_config.json
```

可用 `MOBILESAM_ENCODER` / `MOBILESAM_DECODER` 覆盖；`MOBILESAM_CUDA=0` 强制 CPU。

## 构建

```bash
cd ~/iso_flutter
export LD_LIBRARY_PATH=/opt/StaticPy/cpp/imgproc/build:${LD_LIBRARY_PATH:-}

# C++ C ABI（ORT）
bash tools/mobilesam/build.sh

# StaticPy CLI
bash /opt/StaticPy/imgproc/build_app.sh tools/seg.static.py seg
cp /opt/StaticPy/seg bin/seg
cp /opt/StaticPy/seg.so bin/seg.so
chmod +x bin/seg
```

运行：

```bash
export LD_LIBRARY_PATH=$HOME/iso_flutter/bin:/opt/StaticPy/cpp/imgproc/build:${LD_LIBRARY_PATH:-}
export MOBILESAM_CUDA=0

# 自动找主体，透明 RGBA
bin/seg in.png out.png

# 手动点（原图像素坐标，可多个）
bin/seg in.png out.png "512,700;500,400"

# 输出 mask / 白底
bin/seg in.png out.png "auto" "" mask.png 3
bin/seg in.png out.png "auto" "" mask.png 1
```

模式：`0=RGBA`、`1=white`、`2=black`、`3=mask`。

自动模式默认 16×16 网格，CPU 约 40–50s；手动点约 4s。输出会做“最大连通块 + 填洞”，得到可直接进 `split_grid → align_head → pack_sprites` 的透明素材。
