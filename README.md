# iso_flutter

> **native 等距解释图/动画引擎**：Dart + Lua 双引擎（等价），Flutter 离屏渲染出 PNG/GIF/MP4 —— 无浏览器、无 node、无 JS。

把 anatomy（等距插画）的引擎**全量移植为 Dart 与 Lua 两份等价实现**，在 **Flutter 里离屏渲染**出
**PNG / GIF / MP4**（发微信），并可与用户交互（拖拽开盖、实时特效）。**无浏览器、无 node、无 JS。**

```
iso_flutter/                       # 独立仓（自包含）
  bin/iso.sh                       # 入口 CLI：render / anim → PNG / GIF / MP4
  iso_engine/        # 框架（Dart 包 name: iso_engine）
    lib/iso_kit.dart  iso_lathe.dart  iso_tube.dart   # 引擎（Dart，移植自 iso-kit/lathe/tube.mjs）
    lib/iso_render.dart                                # 渲染层：kit 线稿样式 → Canvas（Dart/Lua 图共用）
    lib/lua_bridge.dart                                # Dart ←FFI→ LuaJIT 桥
    lib/lua/{iso_kit,lathe,tube}.lua                   # 引擎（Lua，与 Dart 等价）—— 随包打成 assets
    tool/{kit_parity.dart,kit_parity.lua,lua_probe.dart}  # 对拍 / 桥探针
  app/               # 应用（Flutter name: iso_app，依赖 ../iso_engine）
    lib/main.dart                                      # 窗口 + 导出 CLI + 图注册表 _figures
    lib/lua/figures/tmall_genie.lua                    # 图（Lua 版天猫精灵）—— 打成 assets
    assets/fonts/  shaders/
  docs/references/*.md               # 设计规范（craft/kit/motion…，来自 anatomy）
  docs/LICENSE-anatomy              # 署名（MIT）
```

**自包含**：Lua 引擎与图都随包打成 **assets**（运行时解包到临时目录 `require`/`dofile`），不依赖开发机路径；
唯一外部依赖是系统 **`libluajit-5.1.so.2`**（`lua_bridge` 用 `dart:ffi` 加载）。

## 双引擎（Dart 与 Lua 并存，等价）
- **引擎**：`lib/iso_*.dart` 与 `lib/lua/*.lua`；**图**可用 Dart 写（`main.dart` 的 `_figures`）或 Lua 写（`lib/lua/figures/*.lua`）。
- **渲染层一份共用**：Lua 只算几何、输出路径串/指令 JSON，Dart 负责画。
- **等价性**：同图 Dart 与 Lua 输出**逐字符相同**（RMSE≈1e-5）。

## 构建 / 运行
```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd app && flutter build linux --release
./build/linux/x64/release/bundle/iso_app                 # 交互窗口（左上空 64×64 区域点一下切 dark/light）
```
**离屏导出（CLI）**：env `ISO_EXPORT=<图名> ISO_OUT=<路径> [ISO_SS=2] [ISO_LIFT=0..1] [ISO_THEME=dark] [ISO_MOTION=1 ISO_FRAME=i ISO_N=n]`。
对外工具：`/opt/my-agent/operator/tools/iso_native.sh render|anim <图名>`（出图/动画 → 微信）。

**图名**（`app/lib/main.dart` 的 `_figures`）：
- `tmall-genie` —— 天猫精灵（**Lua**，默认）
- `tmall-genie-dart` —— 天猫精灵（**Dart** 参考实现，与 Lua 逐像素一致）
- `lathe` / `tube` —— 引擎测试图

## 参考与致谢
引擎与美术来自开源项目 **anatomy**（MIT）· https://github.com/wheresryan22/anatomy
`iso_engine/lib/{iso_*.dart, lua/*.lua}` 为其 `kit/iso-kit.mjs`/`lathe.mjs`/`tube.mjs` 及 CSS 的移植；请勿删除署名。
（设计规范见 `/opt/my-agent/operator/tools/iso/anatomy/references/`。）
