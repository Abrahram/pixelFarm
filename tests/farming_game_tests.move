#[test_only]
module pixcelgame::farming_game_tests {
    use pixcelgame::farming_game::{Self, Player, GameMap};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::test_utils::{assert_eq};
    use sui::clock::{Self, Clock};
    use std::string;
    
    // 测试账户地址
    const PLAYER: address = @0xA;

    // 初始化测试场景
    fun setup_test(): Scenario {
        let scenario = ts::begin(PLAYER);
        
        // 创建时钟
        let ctx = ts::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        
        // 共享时钟
        ts::next_tx(&mut scenario, PLAYER);
        {
            ts::share_object(&mut scenario, clock);
        };
        
        // 初始化游戏
        ts::next_tx(&mut scenario, PLAYER);
        {
            farming_game::init(ts::ctx(&mut scenario));
        };
        
        // 创建玩家
        ts::next_tx(&mut scenario, PLAYER);
        {
            farming_game::create_player(ts::ctx(&mut scenario));
        };
        
        scenario
    }

    #[test]
    fun test_create_player() {
        let scenario = setup_test();
        
        // 检查玩家是否被正确创建
        ts::next_tx(&mut scenario, PLAYER);
        {
            let player = ts::take_from_sender<Player>(&scenario);
            let (seed_names, seed_amounts, tool_names, tool_amounts, _, _) = farming_game::get_player_inventory(&player);
            
            // 检查玩家是否有初始种子和工具
            assert_eq(seed_names[0], string::utf8(b"carrot"));
            assert_eq(seed_amounts[0], 5);
            assert_eq(seed_names[1], string::utf8(b"tomato"));
            assert_eq(seed_amounts[1], 3);
            assert_eq(tool_names[0], string::utf8(b"shovel"));
            assert_eq(tool_amounts[0], 1);
            assert_eq(tool_names[1], string::utf8(b"watering_can"));
            assert_eq(tool_amounts[1], 1);
            
            ts::return_to_sender(&scenario, player);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_cultivate_land() {
        let scenario = setup_test();
        
        // 开垦土地
        ts::next_tx(&mut scenario, PLAYER);
        {
            let player = ts::take_from_sender<Player>(&scenario);
            let game_map = ts::take_shared<GameMap>(&scenario);
            
            // 开垦坐标 (4, 4) 的土地 (这是可开垦地块区域)
            farming_game::cultivate_land(&mut player, &mut game_map, 4, 4, ts::ctx(&mut scenario));
            
            // 检查地块是否变为可耕种地块
            let (land_type, _, _, _, _, _) = farming_game::get_land_info(&game_map, 4, 4);
            assert_eq(land_type, 2); // LAND_TYPE_FARMLAND
            
            ts::return_to_sender(&scenario, player);
            ts::return_shared(game_map);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_plant_grow_harvest() {
        let scenario = setup_test();
        
        // 开垦土地
        ts::next_tx(&mut scenario, PLAYER);
        {
            let player = ts::take_from_sender<Player>(&scenario);
            let game_map = ts::take_shared<GameMap>(&scenario);
            
            // 开垦坐标 (4, 4) 的土地
            farming_game::cultivate_land(&mut player, &mut game_map, 4, 4, ts::ctx(&mut scenario));
            
            ts::return_to_sender(&scenario, player);
            ts::return_shared(game_map);
        };
        
        // 种植种子
        ts::next_tx(&mut scenario, PLAYER);
        {
            let player = ts::take_from_sender<Player>(&scenario);
            let game_map = ts::take_shared<GameMap>(&scenario);
            let clock = ts::take_shared<Clock>(&scenario);
            
            // 种植胡萝卜
            farming_game::plant_seed(&mut player, &mut game_map, 4, 4, b"carrot", &clock, ts::ctx(&mut scenario));
            
            // 检查地块是否有种子
            let (_, has_seed, seed_type, seed_state, _, _) = farming_game::get_land_info(&game_map, 4, 4);
            assert_eq(has_seed, true);
            assert_eq(seed_type, string::utf8(b"carrot"));
            assert_eq(seed_state, 0); // SEED_STATE_PLANTED
            
            ts::return_to_sender(&scenario, player);
            ts::return_shared(game_map);
            ts::return_shared(clock);
        };
        
        // 浇水
        ts::next_tx(&mut scenario, PLAYER);
        {
            let player = ts::take_from_sender<Player>(&scenario);
            let game_map = ts::take_shared<GameMap>(&scenario);
            
            farming_game::water_plant(&mut player, &mut game_map, 4, 4, ts::ctx(&mut scenario));
            
            // 检查水分是否增加
            let (_, _, _, _, water_level, _) = farming_game::get_land_info(&game_map, 4, 4);
            assert_eq(water_level, 1);
            
            ts::return_to_sender(&scenario, player);
            ts::return_shared(game_map);
        };
        
        // 施肥 (首先需要探索获取一些肥料)
        ts::next_tx(&mut scenario, PLAYER);
        {
            let player = ts::take_from_sender<Player>(&scenario);
            
            // 添加一些肥料到玩家背包
            let ctx = ts::ctx(&mut scenario);
            farming_game::test_add_fertilizer(&mut player, b"basic_fertilizer", 5, ctx);
            
            ts::return_to_sender(&scenario, player);
        };
        
        // 施肥
        ts::next_tx(&mut scenario, PLAYER);
        {
            let player = ts::take_from_sender<Player>(&scenario);
            let game_map = ts::take_shared<GameMap>(&scenario);
            
            farming_game::fertilize_plant(&mut player, &mut game_map, 4, 4, b"basic_fertilizer", ts::ctx(&mut scenario));
            
            // 检查肥料是否增加，状态是否变为生长中
            let (_, _, _, seed_state, _, fertilizer_level) = farming_game::get_land_info(&game_map, 4, 4);
            assert_eq(fertilizer_level, 1);
            assert_eq(seed_state, 1); // SEED_STATE_GROWING
            
            ts::return_to_sender(&scenario, player);
            ts::return_shared(game_map);
        };
        
        // 将时钟快进，使种子成熟
        ts::next_tx(&mut scenario, PLAYER);
        {
            let clock = ts::take_shared<Clock>(&scenario);
            
            // 快进6分钟
            clock::increment_for_testing(&mut clock, 360000);
            
            ts::return_shared(clock);
        };
        
        // 检查生长状态
        ts::next_tx(&mut scenario, PLAYER);
        {
            let game_map = ts::take_shared<GameMap>(&scenario);
            let clock = ts::take_shared<Clock>(&scenario);
            
            farming_game::check_growth(&mut game_map, 4, 4, &clock, ts::ctx(&mut scenario));
            
            // 检查种子是否成熟
            let (_, _, _, seed_state, _, _) = farming_game::get_land_info(&game_map, 4, 4);
            assert_eq(seed_state, 2); // SEED_STATE_MATURE
            
            ts::return_shared(game_map);
            ts::return_shared(clock);
        };
        
        // 收获
        ts::next_tx(&mut scenario, PLAYER);
        {
            let player = ts::take_from_sender<Player>(&scenario);
            let game_map = ts::take_shared<GameMap>(&scenario);
            
            // 记录收获前的种子数量
            let (seed_names, seed_amounts, _, _, _, _) = farming_game::get_player_inventory(&player);
            let carrot_index = 0; // 假设胡萝卜在第一个位置
            let carrot_before = seed_amounts[carrot_index];
            
            farming_game::harvest(&mut player, &mut game_map, 4, 4, ts::ctx(&mut scenario));
            
            // 检查收获后种子数量是否增加
            let (seed_names, seed_amounts, _, _, _, _) = farming_game::get_player_inventory(&player);
            let carrot_after = seed_amounts[carrot_index];
            
            // 基础产量 2 + 水分 1 + 肥料 1 = 4
            assert_eq(carrot_after, carrot_before + 4);
            
            // 检查地块是否被重置
            let (_, has_seed, _, _, _, _) = farming_game::get_land_info(&game_map, 4, 4);
            assert_eq(has_seed, false);
            
            ts::return_to_sender(&scenario, player);
            ts::return_shared(game_map);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_merchant() {
        let scenario = setup_test();
        
        // 刷新商人
        ts::next_tx(&mut scenario, PLAYER);
        {
            let game_map = ts::take_shared<GameMap>(&scenario);
            let clock = ts::take_shared<Clock>(&scenario);
            
            farming_game::refresh_merchant(&mut game_map, &clock, ts::ctx(&mut scenario));
            
            // 检查是否有商人
            let (merchant_ids, _, _, _) = farming_game::get_merchants_info(&game_map);
            assert_eq(vector::length(&merchant_ids) > 0, true);
            
            ts::return_shared(game_map);
            ts::return_shared(clock);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_explore() {
        let scenario = setup_test();
        
        // 探索获取种子
        ts::next_tx(&mut scenario, PLAYER);
        {
            let player = ts::take_from_sender<Player>(&scenario);
            let clock = ts::take_shared<Clock>(&scenario);
            
            // 记录探索前的种子数量
            let (seed_names, seed_amounts, _, _, _, _) = farming_game::get_player_inventory(&player);
            let total_seeds_before = 0;
            let i = 0;
            let len = vector::length(&seed_amounts);
            while (i < len) {
                total_seeds_before = total_seeds_before + seed_amounts[i];
                i = i + 1;
            };
            
            farming_game::explore_for_seeds(&mut player, &clock, ts::ctx(&mut scenario));
            
            // 检查探索后种子总数是否增加
            let (_, seed_amounts, _, _, _, _) = farming_game::get_player_inventory(&player);
            let total_seeds_after = 0;
            let i = 0;
            let len = vector::length(&seed_amounts);
            while (i < len) {
                total_seeds_after = total_seeds_after + seed_amounts[i];
                i = i + 1;
            };
            
            assert_eq(total_seeds_after > total_seeds_before, true);
            
            ts::return_to_sender(&scenario, player);
            ts::return_shared(clock);
        };
        
        ts::end(scenario);
    }
} 