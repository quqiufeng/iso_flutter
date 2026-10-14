# 架构 · 技术 · 原理

> `iso_flutter`：把"零件"拼成 **等距解释图**并生成 **动画** 的 **native 引擎**。
> 无浏览器、无 node、无 JS —— 渲染在 Flutter，几何有 **Dart 与 Lua 两份等价实现**。

---

## 1. 总览（数据流）

```
        图定义（content）
   ┌──────────────┴──────────────┐
   │ Dart                         │ Lua
   │ app/lib/main.dart            │ app/lib/lua/figures/*.lua
   │  的 _figures 注册的画图函数    │  (返回绘制指令 JSON)
   └──────────────┬──────────────┘
                  │                    ▲
        ┌─────────┴─────────┐          │ 内嵌 LuaJIT
        │ 引擎（geometry）    │◄─────────┘（dart:ffi 桥）
        │ Dart: iso_*.dart   │   Lua: iso_kit/lathe/tube.lua
        └─────────┬─────────┘
                  │ 路径串 / 绘制指令
        ┌─────────┴─────────┐
        │ 渲染层 iso_render  │  线稿样式 → Canvas（Dart/Lua 图共用）
        └─────────┬─────────┘
                  │
        ┌─────────┴─────────┐
        │ Flutter / Impeller │  ① 交互窗口（实时）  ② 离屏导出（CLI）
        └─────────┬─────────┘
                  │
            PNG / GIF / MP4   （bin/iso.sh → 可发微信）
```

---

## 2. 分层与目录

| 层 | 位置 | 职责 |
|---|---|---|
| **应用** | `app/`（Flutter, `iso_app`） | 渲染窗口、图注册表 `_figures`、导出 CLI、Lua 入口 |
| **框架** | `iso_engine/`（Dart 包, `iso_engine`） | 引擎 + 渲染层 + FFI 桥；**不含任何具体图** |
| **图** | `app/lib/main.dart`（Dart）/ `app/lib/lua/figures/*.lua`（Lua） | 用引擎摆零件、定时间线/特效 |
| **入口** | `bin/iso.sh` | `render`/`anim` → 生成 PNG/GIF/MP4 |
| **文档** | `docs/` | 设计规范 `references/` + anatomy 署名 `LICENSE-anatomy` |

**框架 ⊥ 内容**：引擎通用；加图 = 加一个画图函数（Dart）或一个 `.lua`，不动引擎。

---

## 3. 技术栈

| | 技术 | 用途 |
|---|---|---|
| 渲染 | **Flutter + Impeller**（GPU） | 矢量→光栅；交互实时 + 离屏出图 |
| 语言① | **Dart** | 引擎/渲染/桥/应用 |
| 语言② | **Lua（LuaJIT）** | 引擎/图的脚本层（内嵌，可热改） |
| 桥 | **`dart:ffi`**→ `libluajit-5.1.so.2` | Dart 跑 Lua、取回路径串/JSON |
| 合成 | **ffmpeg** | 逐帧 PNG → GIF/MP4 |
| 字体 | **仓耳今楷02**（子集 14KB，随包 assets） | 中文标注 |

---

## 4. 原理：等距图怎么来的

### 4.1 等距投影
世界点 `[x,y,z]`（x/y 在地面、z 向上）投到 2D：**方位角 45°、俯仰角 30°**，比例 `k = scale·√1.6`。
"立体感"来自几何，不是 3D 引擎。函数：`iso([x,y,z], P)`、`fitProjection(...)`（自动取景居中）。

### 4.2 实心体建模（挤出/回转/扫掠）
- **挤出** `extrude(ring, z, height)`：地面轮廓向上挤出棱柱 → 产出 `fill / outline / crease / top / shades[4] / bevel`。
  - `slabOf`（圆角矩形盒）、`cylinder`（柱）、`prismOf`（任意多边形棱柱）。
- **回转体** `lathe(meridian)`：母线绕轴回转（含**样条 `curveRuns/curved`** 与**平滑着色 `smoothRows`**、`surfaceOf` 轮廓）。
  封装：`disc / ringBand / solidOf / sphereOf / bandOfProfile`。
- **扫掠管** `tubePieces(path)`：圆沿 3D 路径扫掠（含端盖、条纹高光、环）。

### 4.3 明暗与遮挡
- 每个可见面按**法向·光向**分到 **4 档明暗**（`SHADES=4`）；另有 top（顶面）、crease（折线）、outline（轮廓）。
- **Painter's order**：`depthOf = 点·视线`，同层从远到近画（后画盖先画）；运动件每帧重排。

### 4.4 线稿风格（"好看"的来源）
这不是写实渲染，而是**单色线稿**：
- 实体填充 = **卡片底色**（≈镂空）；
- 可见面 = **4 档贴近底色**的微妙阴影；
- 边缘 = **细线**，按 `hi/mid/lo/faint` 色阶；
- `halo` = 一层 **blur 软投影**。
> light 主题（白机身/浅底/深灰细边）才是"产品图"那版；dark 是深色线稿。
（详见 `docs/references/craft.md`。）

---

## 5. 双引擎：Dart 与 Lua（等价）

同一套几何有**两份实现**，接口同名：

| | Dart | Lua |
|---|---|---|
| 核心 | `iso_engine/lib/iso_kit.dart` `iso_lathe.dart` `iso_tube.dart` | `iso_engine/lib/lua/{iso_kit,lathe,tube}.lua` |

- **等价性**：同图两版输出**逐字符相同**（`iso_engine/tool/kit_parity.{dart,lua}`），渲染结果 RMSE≈1e-5。
- **Lua 路径**：`lua_bridge`（FFI）跑 Lua → 图的 `function(lift,time)` 返回**绘制指令 JSON** → Dart 解析 → 同一个渲染层画。
- **渲染层只有一份**（Dart）：Lua 只"算几何"，不重复画。

---

## 6. 动画与交互

- **时间线**：图的"抬升/开合"等按归一化时间 `t∈[0,1]` 驱动（`--motion` 用 easeOutBack 缓动，带过冲）。
- **相位特效**：唤醒扩散波纹（带透明度衰减）、LED 环变亮、麦克风点呼吸、顶盖抬升**轻微倾斜**、软阴影随开合变化。
- **实时效**：可叠 **fragment shader**（如火焰那类 GPU 实时效果）。
- **交互**：Flutter 手势（拖拽开盖 + 弹簧/点击）。窗口渲染用 **整数倍缩放（1/2/3×）+ 离屏 2× 超采样**，让细线锐利、抗锯齿细腻。

---

## 7. 出图 / 出动画流水线

1. **离屏渲染**（`PictureRecorder` → `toImage` → PNG），2× 超采样；
2. **批量**：`ISO_BATCH` 一次进程内渲染全部帧（120 帧 ≈ 19s），不再逐帧起进程；
3. **合成**：ffmpeg → GIF + MP4（60fps）；
4. **对外**：`bin/iso.sh render|anim <图名>` → 打印生成的文件路径（`my-agent` 的 `iso_native.sh` 再发给微信）。

导出由环境变量驱动（应用同一份代码）：`ISO_EXPORT / ISO_FRAME / ISO_N / ISO_BATCH / ISO_MOTION / ISO_LIFT / ISO_THEME / ISO_SS / ISO_OUT`。

---

## 8. 自包含与桥

- **Lua 随包打成 assets**：引擎的 `iso_engine/lib/lua/` + 图的 `app/lib/lua/figures/`；运行时**解包到临时目录**再 `require/dofile` —— 不依赖开发机路径。
- **唯一外部依赖**：系统 `libluajit-5.1.so.2`（`lua_bridge` 用 `dart:ffi` 加载）。
- **字体/着色器**：`app/assets/`、`app/shaders/` 随包。

---

## 9. 扩展：加一张图

- **Lua**：在 `app/lib/lua/figures/` 加 `xxx.lua`（`return function(lift,time) → 绘制指令 JSON`），在 `main.dart` 的 `_figures` 注册 `'xxx'`。
- **Dart**：在 `main.dart` 写 `xxxFigure(canvas, palette, lift, time)`，注册 `'xxx'`。
- 然后 `cd app && flutter build linux --release`；`bin/iso.sh render xxx` 出图。
- 设计规范见 `docs/references/`（`craft`/`kit`/`motion`/`verify`/…）。

---

## 10. 署名

绘图引擎与美术源自开源项目 **anatomy**（MIT）· https://github.com/wheresryan22/anatomy
`iso_engine/lib/{iso_*.dart, lua/*.lua}` 为其 `kit/iso-kit.mjs`/`lathe.mjs`/`tube.mjs` 及 CSS 的移植。许可见 `docs/LICENSE-anatomy`，**请勿删除署名**。
