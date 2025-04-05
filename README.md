# PixcelGame - 区块链种菜游戏

这是一个基于Sui区块链的种菜游戏，玩家可以探索地图、获取种子、开垦土地、种植作物、浇水施肥，以及与游商交易。

## 游戏特点

- **多样化地块**: 地图包含可耕种地块、可开垦地块和不可开垦地块
- **农作物种植系统**: 玩家可以种植不同种类的农作物，每种作物有不同的生长时间和产量
- **农作物管理**: 播种后需要浇水和施肥才能让农作物生长
- **随机商人系统**: 游戏中会随机刷新游商，提供不同的交易物品
- **探索机制**: 玩家可以探索地图获取随机种子

## 游戏流程

1. 创建玩家角色
2. 探索地图获取种子
3. 开垦可开垦地块变成可耕种地块
4. 在可耕种地块上种植种子
5. 给植物浇水和施肥
6. 等待植物生长成熟
7. 收获成熟的植物
8. 与游商交易获取新的种子、工具或肥料

## 开发说明

### 编译项目

```bash
sui move build
```

### 运行测试

```bash
sui move test
```

### 发布到区块链

```bash
sui client publish --gas-budget 100000000
```

## 合约说明

本游戏包含以下主要模块和功能：

### 主要数据结构

- `Player`: 玩家信息，包括拥有的种子、工具和肥料
- `GameMap`: 游戏地图，包含所有地块信息和商人
- `Land`: 地块信息，包括地块类型和种植的种子
- `PlantedSeed`: 种植的种子信息，包括种子类型、生长状态、浇水和施肥等级
- `Merchant`: 商人信息，包括出售的物品列表

### 主要功能函数

- `create_player`: 创建新玩家
- `cultivate_land`: 开垦土地
- `plant_seed`: 种植种子
- `water_plant`: 浇水
- `fertilize_plant`: 施肥
- `check_growth`: 检查植物生长状态
- `harvest`: 收获成熟的植物
- `refresh_merchant`: 刷新商人
- `trade_with_merchant`: 与商人交易
- `explore_for_seeds`: 探索获取种子

## 例子

```move
// 创建玩家
farming_game::create_player(ctx);

// 开垦土地坐标(4, 4)
farming_game::cultivate_land(&mut player, &mut game_map, 4, 4, ctx);

// 在坐标(4, 4)种植胡萝卜
farming_game::plant_seed(&mut player, &mut game_map, 4, 4, b"carrot", &clock, ctx);

// 给坐标(4, 4)的植物浇水
farming_game::water_plant(&mut player, &mut game_map, 4, 4, ctx);

// 给坐标(4, 4)的植物施肥
farming_game::fertilize_plant(&mut player, &mut game_map, 4, 4, b"basic_fertilizer", ctx);

// 检查坐标(4, 4)植物的生长状态
farming_game::check_growth(&mut game_map, 4, 4, &clock, ctx);

// 收获坐标(4, 4)的成熟植物
farming_game::harvest(&mut player, &mut game_map, 4, 4, ctx);

// 刷新商人
farming_game::refresh_merchant(&mut game_map, &clock, ctx);

// 与商人交易
farming_game::trade_with_merchant(&mut player, &mut game_map, merchant_id, item_index, ctx);

// 探索获取种子
farming_game::explore_for_seeds(&mut player, &clock, ctx);
```

## 未来计划

- 添加更多种类的种子和植物
- 实现农作物生长的可视化
- 添加更复杂的天气系统
- 添加更多玩家互动功能
- 实现土地升级系统 