# game/love —— 等距「兵线对推」（LÖVE 运行时）

把开源的 **LÖVE**（`love`，LuaJIT + SDL/OpenGL 的 2D 引擎；
官网 <https://love2d.org> · 源码 <https://github.com/love2d/love>）**集成进本项目**当游戏运行时：
逻辑复用**纯 Lua Sim**，LÖVE 只负责**渲染 / 输入 / 音效 / HUD**；换皮/换引擎只需重写事件消费。

| 复用 | 来自 |
|---|---|
| 游戏逻辑（纯 Lua Sim） | `iso_engine/lib/lua/game/battle.lua`（门面）→ `arena.lua`（内核） |
| 角色动画（主力） | `game/love/assets/nb/<name>_<anim>_<i>.png`（AI 关键帧，Nano Banana） |
| 角色动画（备选） | `assets/chars/*`（CC0 帧）、`example/rig-knight/parts/*`（骨骼）、`app/assets/sprites/*`（SD） |
| 中文字体 | 仓耳今楷 |

**运行**（需 `love` **11.x**）：
```bash
sudo apt install love          # Ubuntu 发行版包：11.5（noble/universe），够用
love ~/iso_flutter/game/love
```
> 本机即发行版安装的 `love 11.5`；代码按 **11.x API** 写（`conf.lua`、`love.graphics/audio`），无需自编译。
> 只有要**更新版本（12.x）或改引擎**时才需从源码 <https://github.com/love2d/love> 构建。

**操作**：`1/2/3` 选兵（剑士/弓手/法师）· **点左半场布兵** · `空格`/`Q` 大招 · `W` 旋斩 · `R` 重开 · `F2` 手动截图连拍。

## 逻辑（纯 Lua Sim，同一份）
`battle.lua` 是对外门面（`battle.new(opts)`、`battle.TYPES`），内核见
`iso_engine/lib/lua/game/`：`config`（数值）/ `entity`（实体）/ `behaviors`（行为）/
`weapons`（命中）/ `abilities`（技能）/ `arena`（世界内核）。**同一份**被 `luajit`（headless 测试 / agent 驱动）
与 LÖVE（渲染）共用——加兵种只改 `config.lua`，不动主循环。

## 渲染解耦：消费 Sim 事件流
Sim 只 `emit{type="hit|death|wave|base"}`（见 `arena.lua`），**渲染层不自行探测血量差**。
`main.lua` 的 `stepJuice` 每帧消费 `game.events`：

| 事件 | 表现 |
|---|---|
| `hit` | 单位闪红 + 飘伤害数字 + 火花 + 命中音效 |
| `death` | 碎屑爆发 + 死亡音效；击杀敌方累计**连杀** + 顿帧（慢动作） |
| `wave` | 「第 N 波」横幅 + 波次音效 |
| `base` | 震屏 + 全屏闪光（基地受击） |

> 换皮 / 换引擎 = 只重写这段事件消费；逻辑一行不改。

## 画面
**俯视 3/4、横平竖直**（`FY=0.78` 竖向压扁）：地面棋盘铺满窗口（战场内亮、场外暗一档），
一条条**横排兵线**；蓝塔在左（我方）、红塔在右（敌方），单位沿行向对方推进。

## 角色渲染（按优先级回退）
`main.lua` 的 `drawUnit` 依次尝试：**NB 关键帧 → 单图网格蒙皮(`skin.lua`) → 刚性分件(`rig.lua`) → CC0 帧 → SD 精灵**。

- **NB 关键帧（主力）**：`assets/nb/knight_{walk,idle,attack,whirl,ult}_*`，白底抠图、脚底对齐；
  走/站循环，`attack`/`whirl`/`ult` 不循环、按施法进度播放；受击闪红 + 弧光。
- 关键帧生成**必须 `--ref` 同一张参考图**（否则跨帧形象漂移）；动态效果一律「关键帧 + 动画模型」，不手绑骨。详见 `../README.md`、`../../docs/ai-game-system.md` §8。

## 技能 / 特效
- 数值 = Sim：`game:ultimate()`（全体敌方 AoE）/ `game:whirlwind()`（全体我方旋风斩）。
- 特效 = **程序化 VFX**（LÖVE 画，不用图），按进度 `p` 分段：
  大招「蓄力金晕 → 砸地(闪光+震屏+冲击环+放射光+火花) → 余波扩散环」；旋斩「多道白色刀光绕身飞转 + 扩散环」。
- 播放同步：`ULT_DUR=1.1s` / `WHIRL_DUR=0.75s`，与关键帧、VFX 对齐。

## 截图钩子（agent 自驱抓图）
`CAPTURE_DIR` 启用后，动画/技能触发时自动连拍 PNG：
```bash
CAPTURE_DIR=$HOME/iso_gen/ult AUTO=ult love game/love    # 自动布兵并触发大招
CAPTURE_DIR=$HOME/iso_gen/whirl AUTO=whirl love game/love
# 帧数 CAPTURE_FRAMES（默认 40）；游戏内 F2 手动开始连拍
```
> 无人值守抓图 + `bin/motion.sh <帧目录>` 做动效自检，见 `../../AGENTS.md` §7。

## 说明
- LÖVE 的沙箱：`love.graphics.newImage/newFont` 只读游戏目录 → 本项目用 `io.open` 读字节 +
  `love.filesystem.newFileData` 载入外部素材/字体；`package.path` 由 `love.filesystem.getSource()` 推导。
- 音效为**程序化合成**（`love.sound.newSoundData`），无需音频文件。
- 窗口 1280×800（`conf.lua`），可缩放。
