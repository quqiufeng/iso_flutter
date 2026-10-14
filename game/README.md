# game —— 等距「兵线对推」小游戏（LÖVE 运行时）

> 详细技术方案见 [`../docs/ai-game-system.md`](../docs/ai-game-system.md) §8。

## 技术栈（当前）
| 层 | 选型 | 位置 |
|---|---|---|
| **游戏逻辑（Sim）** | **纯 Lua**（确定性/headless） | `iso_engine/lib/lua/game/battle.lua` |
| **运行时 / 渲染** | **LÖVE**（开源 Lua 2D 引擎，OpenGL） | `game/love/` |
| **GUI 容器** | **Flutter**（只做窗口/工具，不做游戏渲染） | `app/` |
| **素材** | **CC0 开源素材包**（角色/地图/武器） | `game/love/assets/` |

## 运行
```bash
# 渲染版（LÖVE）
love ~/iso_flutter/game/love

# 纯逻辑版（headless，agent 驱动/测试）
luajit iso_engine/lib/lua/game/run.lua --script "goto:14,14;pick" --json --replay
```

## 玩法
左=我方防守（`1/2/3` 选兵 · 点左半场布兵）· 右=敌方进攻（成波刷兵）· 双方单位射程内自动互攻 · 推掉对方城堡即胜 · `R` 重开。

## 素材来源
- **CC0**：*Free 2D Animated Vector Game Character Sprites*（角色 walk/idle/hit/death + 分件 + 武器 + 地面），见 `game/love/assets/LICENSE-charpack.txt`。
- 自研矢量图/图表：`iso_engine`（`bin/iso.sh`）。
- **不**用 SD 自动生成角色动画（一致性不可靠）。
