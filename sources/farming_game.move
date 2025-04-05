module pixcelgame::farming_game {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use sui::vec_map::{Self, VecMap};
    use std::vector;
    use std::string::{Self, String};

    // ===== 常量定义 =====
    // 地块类型
    const LAND_TYPE_UNCULTIVABLE: u8 = 0; // 不可开垦地块
    const LAND_TYPE_CULTIVABLE: u8 = 1;   // 可开垦地块
    const LAND_TYPE_FARMLAND: u8 = 2;     // 可耕种地块

    // 种子状态
    const SEED_STATE_PLANTED: u8 = 0;    // 已种植
    const SEED_STATE_GROWING: u8 = 1;    // 生长中
    const SEED_STATE_MATURE: u8 = 2;     // 成熟
    
    // 错误码
    const EInvalidLandType: u64 = 1;
    const ELandNotCultivable: u64 = 2;
    const ELandNotFarmland: u64 = 3;
    const ELandOccupied: u64 = 4;
    const ELandNoSeed: u64 = 5;
    const ESeedNotMature: u64 = 6;
    const ENotEnoughSeeds: u64 = 7;
    const EInvalidMerchant: u64 = 8;

    // ===== 游戏对象 =====
    // 玩家信息
    public struct Player has key, store {
        id: UID,
        seeds: VecMap<String, u64>,     // 种子名称 -> 数量
        tools: VecMap<String, u64>,     // 工具名称 -> 数量
        fertilizers: VecMap<String, u64> // 肥料名称 -> 数量
    }

    // 地图
    public struct GameMap has key {
        id: UID,
        width: u64,
        height: u64,
        lands: Table<Coordinates, Land>,
        merchants: vector<Merchant>,
        last_merchant_refresh: u64
    }

    // 坐标
    public struct Coordinates has copy, drop, store {
        x: u64,
        y: u64
    }

    // 地块
    public struct Land has store {
        land_type: u8,
        planted_seed: Option<PlantedSeed>
    }

    // 种植的种子
    public struct PlantedSeed has store {
        seed_type: String,
        state: u8,
        plant_time: u64,
        water_level: u64,
        fertilizer_level: u64,
        growth_time_needed: u64,
        harvested_amount: u64
    }

    // 种子定义
    public struct SeedDefinition has store, copy, drop {
        name: String,
        growth_time: u64,
        base_yield: u64,
        water_need: u64,
        fertilizer_need: u64
    }

    // 商人
    public struct Merchant has store, copy, drop {
        id: u64,
        name: String,
        items_for_sale: vector<MerchantItem>,
        expires_at: u64
    }

    // 商人出售物品
    public struct MerchantItem has store, copy, drop {
        item_type: String, // "seed", "tool", "fertilizer"
        name: String,
        price_seed_type: String,
        price_amount: u64
    }

    // 可选类型
    public struct Option<T: store> has store {
        value: vector<T>
    }

    // ===== 事件 =====
    public struct PlayerCreated has copy, drop {
        player_id: address
    }

    public struct SeedPlanted has copy, drop {
        player: address,
        coordinates: Coordinates,
        seed_type: String
    }

    public struct PlantHarvested has copy, drop {
        player: address,
        coordinates: Coordinates,
        seed_type: String,
        amount: u64
    }

    public struct MerchantSpawned has copy, drop {
        merchant_id: u64,
        merchant_name: String,
        expires_at: u64
    }

    // ===== 辅助函数 =====
    public fun new_option<T: store>(): Option<T> {
        Option { value: vector::empty() }
    }

    public fun some<T: store>(value: T): Option<T> {
        let v = vector::empty();
        vector::push_back(&mut v, value);
        Option { value: v }
    }

    public fun none<T: store>(): Option<T> {
        Option { value: vector::empty() }
    }

    public fun is_some<T: store>(opt: &Option<T>): bool {
        !vector::is_empty(&opt.value)
    }

    public fun is_none<T: store>(opt: &Option<T>): bool {
        vector::is_empty(&opt.value)
    }

    public fun extract<T: store>(opt: Option<T>): T {
        assert!(!vector::is_empty(&opt.value), 0);
        let v = opt.value;
        let result = vector::pop_back(&mut v);
        vector::destroy_empty(v);
        result
    }

    public fun borrow<T: store>(opt: &Option<T>): &T {
        assert!(!vector::is_empty(&opt.value), 0);
        vector::borrow(&opt.value, 0)
    }

    public fun borrow_mut<T: store>(opt: &mut Option<T>): &mut T {
        assert!(!vector::is_empty(&opt.value), 0);
        vector::borrow_mut(&mut opt.value, 0)
    }

    // ===== 初始化函数 =====
    #[init]
    public fun init(ctx: &mut TxContext) {
        // 创建游戏地图
        let game_map = GameMap {
            id: object::new(ctx),
            width: 10,
            height: 10,
            lands: table::new(ctx),
            merchants: vector::empty(),
            last_merchant_refresh: 0
        };

        // 初始化地图
        let x = 0;
        while (x < 10) {
            let y = 0;
            while (y < 10) {
                let coords = Coordinates { x, y };
                
                // 简单的地图生成逻辑
                let land_type = if (x < 3 && y < 3) {
                    // 左上角区域为可耕种地块
                    LAND_TYPE_FARMLAND
                } else if (x < 7 && y < 7) {
                    // 中间区域为可开垦地块
                    LAND_TYPE_CULTIVABLE
                } else {
                    // 其余为不可开垦地块
                    LAND_TYPE_UNCULTIVABLE
                };
                
                let land = Land {
                    land_type,
                    planted_seed: none()
                };
                
                table::add(&mut game_map.lands, coords, land);
                y = y + 1;
            };
            x = x + 1;
        };

        // 将游戏地图共享给所有人
        transfer::share_object(game_map);
    }

    // 创建玩家
    public entry fun create_player(ctx: &mut TxContext) {
        let player = Player {
            id: object::new(ctx),
            seeds: vec_map::empty(),
            tools: vec_map::empty(),
            fertilizers: vec_map::empty()
        };

        // 初始赠送一些种子
        vec_map::insert(&mut player.seeds, string::utf8(b"carrot"), 5);
        vec_map::insert(&mut player.seeds, string::utf8(b"tomato"), 3);
        
        // 初始赠送一些工具
        vec_map::insert(&mut player.tools, string::utf8(b"shovel"), 1);
        vec_map::insert(&mut player.tools, string::utf8(b"watering_can"), 1);
        
        // 发送玩家创建事件
        event::emit(PlayerCreated { player_id: tx_context::sender(ctx) });
        
        // 转移玩家对象给发送者
        transfer::transfer(player, tx_context::sender(ctx));
    }

    // ===== 游戏功能函数 =====
    
    // 开垦土地（将可开垦地块转变为可耕种地块）
    public entry fun cultivate_land(
        player: &mut Player,
        game_map: &mut GameMap,
        x: u64,
        y: u64,
        ctx: &mut TxContext
    ) {
        // 检查玩家是否有铲子
        let shovel_count = if (vec_map::contains(&player.tools, &string::utf8(b"shovel"))) {
            *vec_map::get(&player.tools, &string::utf8(b"shovel"))
        } else {
            0
        };
        assert!(shovel_count > 0, ENotEnoughSeeds);

        let coords = Coordinates { x, y };
        assert!(table::contains(&game_map.lands, coords), EInvalidLandType);
        
        let land = table::borrow_mut(&mut game_map.lands, coords);
        assert!(land.land_type == LAND_TYPE_CULTIVABLE, ELandNotCultivable);
        
        // 将地块类型改为可耕种地块
        land.land_type = LAND_TYPE_FARMLAND;
    }
    
    // 种植种子
    public entry fun plant_seed(
        player: &mut Player,
        game_map: &mut GameMap,
        x: u64,
        y: u64,
        seed_type: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let seed_name = string::utf8(seed_type);
        
        // 检查玩家是否有足够的种子
        assert!(vec_map::contains(&player.seeds, &seed_name), ENotEnoughSeeds);
        let seed_count = *vec_map::get(&player.seeds, &seed_name);
        assert!(seed_count > 0, ENotEnoughSeeds);
        
        // 减少玩家的种子数量
        *vec_map::get_mut(&mut player.seeds, &seed_name) = seed_count - 1;
        
        let coords = Coordinates { x, y };
        assert!(table::contains(&game_map.lands, coords), EInvalidLandType);
        
        let land = table::borrow_mut(&mut game_map.lands, coords);
        assert!(land.land_type == LAND_TYPE_FARMLAND, ELandNotFarmland);
        assert!(is_none(&land.planted_seed), ELandOccupied);
        
        // 获取种子生长时间和产量
        let (growth_time, base_yield) = get_seed_properties(&seed_name);
        
        // 创建新种植的种子
        let planted_seed = PlantedSeed {
            seed_type: seed_name,
            state: SEED_STATE_PLANTED,
            plant_time: clock::timestamp_ms(clock),
            water_level: 0,
            fertilizer_level: 0,
            growth_time_needed: growth_time,
            harvested_amount: 0
        };
        
        // 设置地块上的种子
        land.planted_seed = some(planted_seed);
        
        // 发出种植事件
        event::emit(SeedPlanted {
            player: tx_context::sender(ctx),
            coordinates: coords,
            seed_type: seed_name
        });
    }
    
    // 获取种子属性（根据种子类型返回生长时间和基础产量）
    fun get_seed_properties(seed_type: &String): (u64, u64) {
        if (string::bytes(seed_type) == &b"carrot") {
            return (300000, 2) // 5分钟, 产量2
        } else if (string::bytes(seed_type) == &b"tomato") {
            return (600000, 3) // 10分钟, 产量3
        } else if (string::bytes(seed_type) == &b"potato") {
            return (900000, 4) // 15分钟, 产量4
        } else if (string::bytes(seed_type) == &b"wheat") {
            return (1200000, 5) // 20分钟, 产量5
        } else {
            return (300000, 1) // 默认5分钟, 产量1
        }
    }
    
    // 浇水
    public entry fun water_plant(
        player: &mut Player,
        game_map: &mut GameMap,
        x: u64,
        y: u64,
        ctx: &mut TxContext
    ) {
        // 检查玩家是否有浇水壶
        let watering_can_count = if (vec_map::contains(&player.tools, &string::utf8(b"watering_can"))) {
            *vec_map::get(&player.tools, &string::utf8(b"watering_can"))
        } else {
            0
        };
        assert!(watering_can_count > 0, ENotEnoughSeeds);

        let coords = Coordinates { x, y };
        assert!(table::contains(&game_map.lands, coords), EInvalidLandType);
        
        let land = table::borrow_mut(&mut game_map.lands, coords);
        assert!(land.land_type == LAND_TYPE_FARMLAND, ELandNotFarmland);
        assert!(is_some(&land.planted_seed), ELandNoSeed);
        
        // 增加水分
        let planted_seed = borrow_mut(&mut land.planted_seed);
        if (planted_seed.state != SEED_STATE_MATURE) {
            planted_seed.water_level = planted_seed.water_level + 1;
            
            // 检查是否状态应该更新
            update_seed_state(planted_seed);
        }
    }
    
    // 施肥
    public entry fun fertilize_plant(
        player: &mut Player,
        game_map: &mut GameMap,
        x: u64,
        y: u64,
        fertilizer_type: vector<u8>,
        ctx: &mut TxContext
    ) {
        let fertilizer_name = string::utf8(fertilizer_type);
        
        // 检查玩家是否有足够的肥料
        assert!(vec_map::contains(&player.fertilizers, &fertilizer_name), ENotEnoughSeeds);
        let fertilizer_count = *vec_map::get(&player.fertilizers, &fertilizer_name);
        assert!(fertilizer_count > 0, ENotEnoughSeeds);
        
        // 减少玩家的肥料数量
        *vec_map::get_mut(&mut player.fertilizers, &fertilizer_name) = fertilizer_count - 1;
        
        let coords = Coordinates { x, y };
        assert!(table::contains(&game_map.lands, coords), EInvalidLandType);
        
        let land = table::borrow_mut(&mut game_map.lands, coords);
        assert!(land.land_type == LAND_TYPE_FARMLAND, ELandNotFarmland);
        assert!(is_some(&land.planted_seed), ELandNoSeed);
        
        // 增加肥料
        let planted_seed = borrow_mut(&mut land.planted_seed);
        if (planted_seed.state != SEED_STATE_MATURE) {
            planted_seed.fertilizer_level = planted_seed.fertilizer_level + 1;
            
            // 检查是否状态应该更新
            update_seed_state(planted_seed);
        }
    }
    
    // 更新种子状态
    fun update_seed_state(planted_seed: &mut PlantedSeed) {
        if (planted_seed.water_level >= 1 && planted_seed.fertilizer_level >= 1 && 
            planted_seed.state == SEED_STATE_PLANTED) {
            planted_seed.state = SEED_STATE_GROWING;
        }
    }
    
    // 检查种子生长状态
    public entry fun check_growth(
        game_map: &mut GameMap,
        x: u64,
        y: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let coords = Coordinates { x, y };
        assert!(table::contains(&game_map.lands, coords), EInvalidLandType);
        
        let land = table::borrow_mut(&mut game_map.lands, coords);
        assert!(is_some(&land.planted_seed), ELandNoSeed);
        
        let planted_seed = borrow_mut(&mut land.planted_seed);
        if (planted_seed.state == SEED_STATE_GROWING) {
            let current_time = clock::timestamp_ms(clock);
            let time_elapsed = current_time - planted_seed.plant_time;
            
            if (time_elapsed >= planted_seed.growth_time_needed) {
                planted_seed.state = SEED_STATE_MATURE;
            }
        }
    }
    
    // 收获
    public entry fun harvest(
        player: &mut Player,
        game_map: &mut GameMap,
        x: u64,
        y: u64,
        ctx: &mut TxContext
    ) {
        let coords = Coordinates { x, y };
        assert!(table::contains(&game_map.lands, coords), EInvalidLandType);
        
        let land = table::borrow_mut(&mut game_map.lands, coords);
        assert!(land.land_type == LAND_TYPE_FARMLAND, ELandNotFarmland);
        assert!(is_some(&land.planted_seed), ELandNoSeed);
        
        let planted_seed = borrow(&land.planted_seed);
        assert!(planted_seed.state == SEED_STATE_MATURE, ESeedNotMature);
        
        // 计算收获量
        let harvest_amount = calculate_harvest_amount(planted_seed);
        
        // 增加玩家的种子数量
        let seed_type = planted_seed.seed_type;
        if (vec_map::contains(&player.seeds, &seed_type)) {
            let current_amount = *vec_map::get(&player.seeds, &seed_type);
            *vec_map::get_mut(&mut player.seeds, &seed_type) = current_amount + harvest_amount;
        } else {
            vec_map::insert(&mut player.seeds, seed_type, harvest_amount);
        }
        
        // 发送收获事件
        event::emit(PlantHarvested {
            player: tx_context::sender(ctx),
            coordinates: coords,
            seed_type: seed_type,
            amount: harvest_amount
        });
        
        // 重置土地
        land.planted_seed = none();
    }
    
    // 计算收获量
    fun calculate_harvest_amount(planted_seed: &PlantedSeed): u64 {
        let (_, base_yield) = get_seed_properties(&planted_seed.seed_type);
        let water_bonus = planted_seed.water_level;
        let fertilizer_bonus = planted_seed.fertilizer_level;
        
        // 基础产量 + 水分加成 + 肥料加成
        base_yield + water_bonus + fertilizer_bonus
    }
    
    // 随机刷新商人
    public entry fun refresh_merchant(
        game_map: &mut GameMap,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // 每5分钟才能刷新一次商人
        if (current_time - game_map.last_merchant_refresh < 300000) {
            return
        }
        
        // 清理过期商人
        let i = 0;
        let len = vector::length(&game_map.merchants);
        let merchants = vector::empty();
        
        while (i < len) {
            let merchant = vector::borrow(&game_map.merchants, i);
            if (merchant.expires_at > current_time) {
                vector::push_back(&mut merchants, *merchant);
            };
            i = i + 1;
        };
        
        game_map.merchants = merchants;
        
        // 生成新商人
        let merchant_id = (((current_time as u128) % 1000) as u64);
        let merchant_name = string::utf8(b"Traveling Merchant");
        let expires_at = current_time + 600000; // 10分钟后过期
        
        let items = vector::empty();
        
        // 添加随机商品
        let seed_type_array = vector[b"carrot", b"tomato", b"potato", b"wheat"];
        let tool_type_array = vector[b"shovel", b"watering_can", b"pruner"];
        let fertilizer_type_array = vector[b"basic_fertilizer", b"premium_fertilizer"];
        
        // 添加一种种子商品
        let seed_index = (((current_time as u128) % (vector::length(&seed_type_array) as u128)) as u64);
        let seed_type = vector::borrow(&seed_type_array, seed_index);
        vector::push_back(&mut items, MerchantItem {
            item_type: string::utf8(b"seed"),
            name: string::utf8(*seed_type),
            price_seed_type: string::utf8(b"carrot"),
            price_amount: 2
        });
        
        // 添加一种工具商品
        let tool_index = (((current_time as u128) % (vector::length(&tool_type_array) as u128)) as u64);
        let tool_type = vector::borrow(&tool_type_array, tool_index);
        vector::push_back(&mut items, MerchantItem {
            item_type: string::utf8(b"tool"),
            name: string::utf8(*tool_type),
            price_seed_type: string::utf8(b"tomato"),
            price_amount: 3
        });
        
        // 添加一种肥料商品
        let fertilizer_index = (((current_time as u128) % (vector::length(&fertilizer_type_array) as u128)) as u64);
        let fertilizer_type = vector::borrow(&fertilizer_type_array, fertilizer_index);
        vector::push_back(&mut items, MerchantItem {
            item_type: string::utf8(b"fertilizer"),
            name: string::utf8(*fertilizer_type),
            price_seed_type: string::utf8(b"potato"),
            price_amount: 2
        });
        
        let merchant = Merchant {
            id: merchant_id,
            name: merchant_name,
            items_for_sale: items,
            expires_at
        };
        
        vector::push_back(&mut game_map.merchants, merchant);
        game_map.last_merchant_refresh = current_time;
        
        // 发送商人刷新事件
        event::emit(MerchantSpawned {
            merchant_id,
            merchant_name,
            expires_at
        });
    }
    
    // 与商人交易
    public entry fun trade_with_merchant(
        player: &mut Player,
        game_map: &mut GameMap,
        merchant_id: u64,
        item_index: u64,
        ctx: &mut TxContext
    ) {
        // 查找商人
        let merchants = &game_map.merchants;
        let i = 0;
        let len = vector::length(merchants);
        let merchant_index: u64 = 0;
        let found = false;
        
        while (i < len) {
            let merchant = vector::borrow(merchants, i);
            if (merchant.id == merchant_id) {
                merchant_index = i;
                found = true;
                break
            };
            i = i + 1;
        };
        
        assert!(found, EInvalidMerchant);
        
        let merchant = vector::borrow(&game_map.merchants, merchant_index);
        assert!(item_index < vector::length(&merchant.items_for_sale), EInvalidMerchant);
        
        let item = vector::borrow(&merchant.items_for_sale, item_index);
        
        // 检查玩家是否有足够的支付种子
        assert!(vec_map::contains(&player.seeds, &item.price_seed_type), ENotEnoughSeeds);
        let seed_count = *vec_map::get(&player.seeds, &item.price_seed_type);
        assert!(seed_count >= item.price_amount, ENotEnoughSeeds);
        
        // 扣除玩家的种子
        *vec_map::get_mut(&mut player.seeds, &item.price_seed_type) = seed_count - item.price_amount;
        
        // 根据物品类型给玩家添加物品
        if (string::bytes(&item.item_type) == &b"seed") {
            if (vec_map::contains(&player.seeds, &item.name)) {
                let count = *vec_map::get(&player.seeds, &item.name);
                *vec_map::get_mut(&mut player.seeds, &item.name) = count + 1;
            } else {
                vec_map::insert(&mut player.seeds, item.name, 1);
            }
        } else if (string::bytes(&item.item_type) == &b"tool") {
            if (vec_map::contains(&player.tools, &item.name)) {
                let count = *vec_map::get(&player.tools, &item.name);
                *vec_map::get_mut(&mut player.tools, &item.name) = count + 1;
            } else {
                vec_map::insert(&mut player.tools, item.name, 1);
            }
        } else if (string::bytes(&item.item_type) == &b"fertilizer") {
            if (vec_map::contains(&player.fertilizers, &item.name)) {
                let count = *vec_map::get(&player.fertilizers, &item.name);
                *vec_map::get_mut(&mut player.fertilizers, &item.name) = count + 1;
            } else {
                vec_map::insert(&mut player.fertilizers, item.name, 1);
            }
        }
    }
    
    // 随机探索获取种子
    public entry fun explore_for_seeds(
        player: &mut Player,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // 使用当前时间作为随机数来源
        let seed_type_array = vector[b"carrot", b"tomato", b"potato", b"wheat"];
        let seed_index = (((current_time as u128) % (vector::length(&seed_type_array) as u128)) as u64);
        let seed_type = vector::borrow(&seed_type_array, seed_index);
        let seed_name = string::utf8(*seed_type);
        
        // 随机数量 1-3
        let amount = (((current_time as u128) % 3) as u64) + 1;
        
        // 给玩家添加种子
        if (vec_map::contains(&player.seeds, &seed_name)) {
            let count = *vec_map::get(&player.seeds, &seed_name);
            *vec_map::get_mut(&mut player.seeds, &seed_name) = count + amount;
        } else {
            vec_map::insert(&mut player.seeds, seed_name, amount);
        }
    }

    // 查询玩家背包
    public fun get_player_inventory(player: &Player): (vector<String>, vector<u64>, vector<String>, vector<u64>, vector<String>, vector<u64>) {
        let seed_names = vector::empty();
        let seed_amounts = vector::empty();
        let tool_names = vector::empty();
        let tool_amounts = vector::empty();
        let fertilizer_names = vector::empty();
        let fertilizer_amounts = vector::empty();
        
        // 获取所有种子
        let seed_keys = vec_map::keys(&player.seeds);
        let i = 0;
        let len = vector::length(&seed_keys);
        while (i < len) {
            let key = vector::borrow(&seed_keys, i);
            vector::push_back(&mut seed_names, *key);
            vector::push_back(&mut seed_amounts, *vec_map::get(&player.seeds, key));
            i = i + 1;
        };
        
        // 获取所有工具
        let tool_keys = vec_map::keys(&player.tools);
        let i = 0;
        let len = vector::length(&tool_keys);
        while (i < len) {
            let key = vector::borrow(&tool_keys, i);
            vector::push_back(&mut tool_names, *key);
            vector::push_back(&mut tool_amounts, *vec_map::get(&player.tools, key));
            i = i + 1;
        };
        
        // 获取所有肥料
        let fertilizer_keys = vec_map::keys(&player.fertilizers);
        let i = 0;
        let len = vector::length(&fertilizer_keys);
        while (i < len) {
            let key = vector::borrow(&fertilizer_keys, i);
            vector::push_back(&mut fertilizer_names, *key);
            vector::push_back(&mut fertilizer_amounts, *vec_map::get(&player.fertilizers, key));
            i = i + 1;
        };
        
        (seed_names, seed_amounts, tool_names, tool_amounts, fertilizer_names, fertilizer_amounts)
    }
    
    // 查询地图信息
    public fun get_map_info(game_map: &GameMap): (u64, u64) {
        (game_map.width, game_map.height)
    }
    
    // 查询地块信息
    public fun get_land_info(game_map: &GameMap, x: u64, y: u64): (u8, bool, String, u8, u64, u64) {
        let coords = Coordinates { x, y };
        assert!(table::contains(&game_map.lands, coords), EInvalidLandType);
        
        let land = table::borrow(&game_map.lands, coords);
        let has_seed = is_some(&land.planted_seed);
        
        let seed_type = if (has_seed) {
            let planted_seed = borrow(&land.planted_seed);
            planted_seed.seed_type
        } else {
            string::utf8(b"")
        };
        
        let seed_state = if (has_seed) {
            let planted_seed = borrow(&land.planted_seed);
            planted_seed.state
        } else {
            0
        };
        
        let water_level = if (has_seed) {
            let planted_seed = borrow(&land.planted_seed);
            planted_seed.water_level
        } else {
            0
        };
        
        let fertilizer_level = if (has_seed) {
            let planted_seed = borrow(&land.planted_seed);
            planted_seed.fertilizer_level
        } else {
            0
        };
        
        (land.land_type, has_seed, seed_type, seed_state, water_level, fertilizer_level)
    }
    
    // 查询商人信息
    public fun get_merchants_info(game_map: &GameMap): (vector<u64>, vector<String>, vector<u64>, vector<u64>) {
        let merchant_ids = vector::empty();
        let merchant_names = vector::empty();
        let merchant_item_counts = vector::empty();
        let merchant_expire_times = vector::empty();
        
        let i = 0;
        let len = vector::length(&game_map.merchants);
        while (i < len) {
            let merchant = vector::borrow(&game_map.merchants, i);
            vector::push_back(&mut merchant_ids, merchant.id);
            vector::push_back(&mut merchant_names, merchant.name);
            vector::push_back(&mut merchant_item_counts, vector::length(&merchant.items_for_sale));
            vector::push_back(&mut merchant_expire_times, merchant.expires_at);
            i = i + 1;
        };
        
        (merchant_ids, merchant_names, merchant_item_counts, merchant_expire_times)
    }
    
    // 查询商人物品信息
    public fun get_merchant_items(game_map: &GameMap, merchant_id: u64): (
        vector<String>, vector<String>, vector<String>, vector<u64>
    ) {
        let item_types = vector::empty();
        let item_names = vector::empty();
        let price_seed_types = vector::empty();
        let price_amounts = vector::empty();
        
        // 查找商人
        let merchants = &game_map.merchants;
        let i = 0;
        let len = vector::length(merchants);
        let merchant_index: u64 = 0;
        let found = false;
        
        while (i < len) {
            let merchant = vector::borrow(merchants, i);
            if (merchant.id == merchant_id) {
                merchant_index = i;
                found = true;
                break
            };
            i = i + 1;
        };
        
        assert!(found, EInvalidMerchant);
        
        let merchant = vector::borrow(&game_map.merchants, merchant_index);
        let items = &merchant.items_for_sale;
        
        let j = 0;
        let items_len = vector::length(items);
        while (j < items_len) {
            let item = vector::borrow(items, j);
            vector::push_back(&mut item_types, item.item_type);
            vector::push_back(&mut item_names, item.name);
            vector::push_back(&mut price_seed_types, item.price_seed_type);
            vector::push_back(&mut price_amounts, item.price_amount);
            j = j + 1;
        };
        
        (item_types, item_names, price_seed_types, price_amounts)
    }

    // ===== 测试专用函数 =====
    #[test_only]
    public fun test_add_fertilizer(player: &mut Player, fertilizer_type: vector<u8>, amount: u64, _ctx: &mut TxContext) {
        let fertilizer_name = string::utf8(fertilizer_type);
        if (vec_map::contains(&player.fertilizers, &fertilizer_name)) {
            let current_amount = *vec_map::get(&player.fertilizers, &fertilizer_name);
            *vec_map::get_mut(&mut player.fertilizers, &fertilizer_name) = current_amount + amount;
        } else {
            vec_map::insert(&mut player.fertilizers, fertilizer_name, amount);
        }
    }
} 