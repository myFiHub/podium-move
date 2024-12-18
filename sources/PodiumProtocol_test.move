#[test_only]
module podium::PodiumProtocol_test {
    use std::string::{Self, String};
    use std::signer;
    use std::option;
    use std::debug;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use podium::PodiumProtocol::{Self, OutpostData, Config};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_framework::fungible_asset;
    use aptos_framework::primary_fungible_store;

    // Test addresses
    const TREASURY: address = @podium;
    const USER1: address = @user1;    // First subscriber/buyer
    const USER2: address = @user2;    // Second subscriber/buyer
    const TARGET: address = @target;   // Target/creator address

    // Error constants
    const EPASS_NOT_FOUND: u64 = 12;
    const EINVALID_SUBSCRIPTION_TIER: u64 = 20;
    const ETIER_EXISTS: u64 = 8;
    const ESUBSCRIPTION_ALREADY_EXISTS: u64 = 18;
    const ESUBSCRIPTION_NOT_FOUND: u64 = 6;
    const ENOT_OWNER: u64 = 15;

    // Test constants
    const PASS_AMOUNT: u64 = 100000000; // 1 pass (1 * 10^8)
    const SUBSCRIPTION_WEEK_PRICE: u64 = 10000000000; // 100 MOVE
    const SUBSCRIPTION_MONTH_PRICE: u64 = 30000000000; // 300 MOVE
    const SUBSCRIPTION_YEAR_PRICE: u64 = 300000000000; // 3000 MOVE

    // Helper function to setup test environment
    fun setup_test(
        aptos_framework: &signer,
        podium_signer: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        debug::print(&string::utf8(b"[setup_test] Starting setup"));
        
        // Create test accounts with proper initialization
        account::create_account_for_test(@0x1);
        assert!(signer::address_of(podium_signer) == @podium, 0);
        account::create_account_for_test(signer::address_of(podium_signer));
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(target));

        // Setup coin for testing
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        
        // Register and fund accounts
        coin::register<AptosCoin>(podium_signer);
        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);
        coin::register<AptosCoin>(target);
        
        // Fund accounts with test MOVE
        let initial_balance = 10000000 * 100000000; // 10M MOVE
        coin::deposit(signer::address_of(podium_signer), coin::mint<AptosCoin>(initial_balance, &mint_cap));
        coin::deposit(signer::address_of(user1), coin::mint<AptosCoin>(initial_balance, &mint_cap));
        coin::deposit(signer::address_of(user2), coin::mint<AptosCoin>(initial_balance, &mint_cap));
        coin::deposit(signer::address_of(target), coin::mint<AptosCoin>(initial_balance, &mint_cap));

        // Initialize protocol if not already initialized
        if (!PodiumProtocol::is_initialized()) {
            PodiumProtocol::initialize(podium_signer);
        };

        // Set timestamp for testing
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    // Helper function to create test outpost
    fun create_test_outpost(creator: &signer): Object<OutpostData> {
        debug::print(&string::utf8(b"=== Starting create_test_outpost ==="));
        
        let creator_addr = signer::address_of(creator);
        debug::print(&string::utf8(b"Creator address:"));
        debug::print(&creator_addr);
        
        let name = string::utf8(b"Test Outpost");
        
        // Create outpost
        let outpost = PodiumProtocol::create_outpost_internal(
            creator,
            name,
            string::utf8(b"Test Description"),
            string::utf8(b"https://test.uri"),
        );

        // Initialize subscription config
        PodiumProtocol::init_subscription_config(creator, outpost);
        
        debug::print(&string::utf8(b"=== Finished create_test_outpost ==="));
        outpost
    }

    // Helper function to get expected outpost address
    fun get_expected_outpost_address(creator: address, name: String): address {
        let collection_name = PodiumProtocol::get_collection_name();
        let seed = token::create_token_seed(&collection_name, &name);
        object::create_object_address(&creator, seed)
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target, buyer = @user1)]
    public fun test_outpost_creation_and_pass_buying(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
        buyer: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, podium_signer, buyer, buyer, creator);
        
        // Create outpost
        let outpost = create_test_outpost(creator);
        let target_addr = object::object_address(&outpost);
        
        // Create subscription tier
        PodiumProtocol::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            1, // DURATION_WEEK
        );
        
        // Create pass token
        PodiumProtocol::create_pass_token(
            creator,
            target_addr,
            string::utf8(b"Test Pass"),
            string::utf8(b"Test Pass Description"),
            string::utf8(b"https://test.uri"),
        );
        
        // Buy pass
        PodiumProtocol::buy_pass(buyer, target_addr, PASS_AMOUNT, option::none());
        
        // Verify pass balance
        let asset_symbol = PodiumProtocol::get_asset_symbol(target_addr);
        let balance = PodiumProtocol::get_balance(signer::address_of(buyer), asset_symbol);
        assert!(balance == PASS_AMOUNT, 0);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target, user1 = @user1, user2 = @user2)]
    public fun test_subscription_flow(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
        user1: &signer,
        user2: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, user1, user2, creator);
        let outpost = create_test_outpost(creator);
        
        // Create subscription tiers
        PodiumProtocol::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            1, // DURATION_WEEK
        );

        PodiumProtocol::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"premium"),
            SUBSCRIPTION_MONTH_PRICE,
            2, // DURATION_MONTH
        );

        // Subscribe to premium tier
        PodiumProtocol::subscribe(
            user2,
            outpost,
            1, // premium tier ID
            option::none(),
        );

        // Verify subscription
        assert!(PodiumProtocol::verify_subscription(
            signer::address_of(user2),
            outpost,
            1 // premium tier ID
        ), 0);

        // Get subscription details
        let (tier_id, start_time, end_time) = PodiumProtocol::get_subscription(
            signer::address_of(user2),
            outpost
        );
        assert!(tier_id == 1, 1);
        assert!(end_time > start_time, 2);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target, user1 = @user1)]
    public fun test_pass_trading(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
        user1: &signer,
    ) {
        debug::print(&string::utf8(b"[test_pass_trading] Starting test"));
        setup_test(aptos_framework, podium_signer, user1, user1, creator);
        
        debug::print(&string::utf8(b"[test_pass_trading] Creating outpost"));
        let outpost = create_test_outpost(creator);
        let target_addr = object::object_address(&outpost);
        debug::print(&string::utf8(b"[test_pass_trading] Target address:"));
        debug::print(&target_addr);
        
        debug::print(&string::utf8(b"[test_pass_trading] Creating pass token"));
        PodiumProtocol::create_pass_token(
            creator,
            target_addr,
            string::utf8(b"Test Pass"),
            string::utf8(b"Test Pass Description"),
            string::utf8(b"https://test.uri"),
        );
        
        debug::print(&string::utf8(b"[test_pass_trading] Recording initial balance"));
        let initial_apt_balance = coin::balance<AptosCoin>(signer::address_of(user1));
        debug::print(&string::utf8(b"Initial APT balance:"));
        debug::print(&initial_apt_balance);
        
        debug::print(&string::utf8(b"[test_pass_trading] Calculating buy price"));
        let (buy_price, protocol_fee, subject_fee, referral_fee) = PodiumProtocol::calculate_buy_price_with_fees(target_addr, PASS_AMOUNT, option::none());
        debug::print(&string::utf8(b"Buy price:"));
        debug::print(&buy_price);
        debug::print(&string::utf8(b"Protocol fee:"));
        debug::print(&protocol_fee);
        debug::print(&string::utf8(b"Subject fee:"));
        debug::print(&subject_fee);
        debug::print(&string::utf8(b"Referral fee:"));
        debug::print(&referral_fee);
        debug::print(&string::utf8(b"Total cost:"));
        debug::print(&(buy_price + protocol_fee + subject_fee + referral_fee));
        
        debug::print(&string::utf8(b"[test_pass_trading] Buying pass"));
        PodiumProtocol::buy_pass(user1, target_addr, PASS_AMOUNT, option::none());
        
        debug::print(&string::utf8(b"[test_pass_trading] Verifying pass received"));
        let asset_symbol = PodiumProtocol::get_asset_symbol(target_addr);
        assert!(PodiumProtocol::get_balance(signer::address_of(user1), asset_symbol) == PASS_AMOUNT, 0);
        
        debug::print(&string::utf8(b"[test_pass_trading] Checking balance after buy"));
        let balance_after_buy = coin::balance<AptosCoin>(signer::address_of(user1));
        debug::print(&string::utf8(b"Balance after buy:"));
        debug::print(&balance_after_buy);
        debug::print(&string::utf8(b"Expected balance after buy:"));
        let expected_balance = initial_apt_balance - (buy_price + protocol_fee + subject_fee + referral_fee);
        debug::print(&expected_balance);
        
        assert!(balance_after_buy == expected_balance, 1);
        
        // Calculate expected sell price
        let (amount_received, _, _) = PodiumProtocol::calculate_sell_price_with_fees(target_addr, PASS_AMOUNT);
        
        // Sell pass
        PodiumProtocol::sell_pass(user1, target_addr, PASS_AMOUNT);
        
        // Verify pass was sold
        assert!(PodiumProtocol::get_balance(signer::address_of(user1), asset_symbol) == 0, 2);
        
        // Verify final balance
        let final_balance = coin::balance<AptosCoin>(signer::address_of(user1));
        assert!(final_balance == balance_after_buy + amount_received, 3);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target, unauthorized_user = @user1)]
    #[expected_failure(abort_code = 327695)]
    public fun test_unauthorized_tier_creation(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
        unauthorized_user: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, creator, unauthorized_user, creator);
        let outpost = create_test_outpost(creator);
        
        // Try to create tier with unauthorized user
        PodiumProtocol::create_subscription_tier(
            unauthorized_user,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            1, // DURATION_WEEK
        );
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target, user1 = @user1)]
    #[expected_failure(abort_code = 524296)]
    public fun test_duplicate_tier_creation(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, creator, creator, creator);
        let outpost = create_test_outpost(creator);
        
        // Create first tier
        PodiumProtocol::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            1, // DURATION_WEEK
        );
        
        // Try to create duplicate tier
        PodiumProtocol::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            1, // DURATION_WEEK
        );
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target, user1 = @user1)]
    public fun test_subscription_expiration(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
        user1: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, user1, user1, creator);
        let outpost = create_test_outpost(creator);

        // Create tier
        PodiumProtocol::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            1, // DURATION_WEEK
        );

        // Subscribe
        PodiumProtocol::subscribe(
            user1,
            outpost,
            0,
            option::none(),
        );

        // Verify active subscription
        assert!(PodiumProtocol::verify_subscription(
            signer::address_of(user1),
            outpost,
            0
        ), 0);

        // Move time forward past expiration (8 days)
        timestamp::fast_forward_seconds(8 * 24 * 60 * 60);

        // Verify subscription expired
        assert!(!PodiumProtocol::verify_subscription(
            signer::address_of(user1),
            outpost,
            0
        ), 1);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target, user1 = @user1)]
    public fun test_outpost_emergency_pause(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
        user1: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, user1, user1, creator);
        let outpost = create_test_outpost(creator);

        // Toggle emergency pause
        PodiumProtocol::toggle_emergency_pause(creator, outpost);
        
        // Verify paused state
        assert!(PodiumProtocol::is_paused(outpost), 0);

        // Toggle back
        PodiumProtocol::toggle_emergency_pause(creator, outpost);
        
        // Verify unpaused
        assert!(!PodiumProtocol::is_paused(outpost), 1);
    }

    #[test(creator = @podium)]
    fun test_create_target_asset(creator: &signer) {
        // Create account first
        account::create_account_for_test(@podium);
        
        // Initialize the protocol
        PodiumProtocol::initialize(creator);

        // Create test asset
        let target_id = string::utf8(b"test_target");
        let name = string::utf8(b"Test Asset");
        let description = string::utf8(b"Test Description");
        let icon_uri = string::utf8(b"https://test.com/icon.png");
        let project_uri = string::utf8(b"https://test.com");

        let metadata = PodiumProtocol::create_target_asset(
            creator,
            target_id,
            name,
            description,
            icon_uri,
            project_uri,
        );

        // Get metadata address and verify it exists
        let metadata_addr = object::object_address<fungible_asset::Metadata>(&metadata);
        assert!(object::is_object(metadata_addr), 0);

        // Create fungible store for the creator
        let asset_symbol = PodiumProtocol::get_asset_symbol_from_string(target_id);
        primary_fungible_store::ensure_primary_store_exists(@podium, metadata);

        // Verify initial balance is 0
        assert!(PodiumProtocol::get_balance(@podium, asset_symbol) == 0, 1);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, user1 = @user1)]
    public fun test_pass_auto_creation(
        aptos_framework: &signer,
        podium_signer: &signer,
        user1: &signer,
    ) {
        debug::print(&string::utf8(b"[test_pass_auto_creation] Starting test"));
        
        // Setup test environment
        setup_test(aptos_framework, podium_signer, user1, user1, user1);
        
        // Record initial balances
        let user_addr = signer::address_of(user1);
        let initial_apt_balance = coin::balance<AptosCoin>(user_addr);
        let initial_target_balance = coin::balance<AptosCoin>(TARGET);
        
        debug::print(&string::utf8(b"[test_pass_auto_creation] Initial balances recorded"));
        debug::print(&string::utf8(b"User APT balance:"));
        debug::print(&initial_apt_balance);
        
        // Buy passes without pre-creating the target asset
        let amount = PASS_AMOUNT;
        debug::print(&string::utf8(b"[test_pass_auto_creation] Buying pass"));
        PodiumProtocol::buy_pass(
            user1,
            TARGET,
            amount,
            option::none() // no referrer
        );
        
        // Get asset symbol and verify balance
        let asset_symbol = PodiumProtocol::get_asset_symbol(TARGET);
        let pass_balance = PodiumProtocol::get_balance(user_addr, asset_symbol);
        debug::print(&string::utf8(b"[test_pass_auto_creation] Pass balance after buy:"));
        debug::print(&pass_balance);
        assert!(pass_balance == amount, 0);
        
        // Verify APT balances changed appropriately
        let final_user_balance = coin::balance<AptosCoin>(user_addr);
        let final_target_balance = coin::balance<AptosCoin>(TARGET);
        debug::print(&string::utf8(b"[test_pass_auto_creation] Final balances:"));
        debug::print(&string::utf8(b"User APT balance:"));
        debug::print(&final_user_balance);
        debug::print(&string::utf8(b"Target APT balance:"));
        debug::print(&final_target_balance);
        
        assert!(final_user_balance < initial_apt_balance, 1); // User spent APT
        assert!(final_target_balance > initial_target_balance, 2); // Target received fee share
        
        // Try selling half the passes
        let sell_amount = amount / 2;
        debug::print(&string::utf8(b"[test_pass_auto_creation] Selling passes"));
        PodiumProtocol::sell_pass(
            user1,
            TARGET,
            sell_amount
        );
        
        // Verify updated pass balance after sell
        let final_pass_balance = PodiumProtocol::get_balance(user_addr, asset_symbol);
        debug::print(&string::utf8(b"[test_pass_auto_creation] Final pass balance:"));
        debug::print(&final_pass_balance);
        assert!(final_pass_balance == amount - sell_amount, 3);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target)]
    public fun test_view_functions(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, podium_signer, creator, creator, creator);
        
        // Test is_initialized
        assert!(PodiumProtocol::is_initialized(), 0);
        
        // Create test outpost
        let outpost = create_test_outpost(creator);
        let outpost_addr = object::object_address(&outpost);
        
        // Test get_collection_name
        let collection_name = PodiumProtocol::get_collection_name();
        assert!(collection_name == string::utf8(b"PodiumOutposts"), 1);
        
        // Test get_outpost_purchase_price
        let purchase_price = PodiumProtocol::get_outpost_purchase_price();
        assert!(purchase_price > 0, 2);
        
        // Test verify_ownership
        assert!(PodiumProtocol::verify_ownership(outpost, signer::address_of(creator)), 3);
        assert!(!PodiumProtocol::verify_ownership(outpost, @user1), 4);
        
        // Test has_outpost_data
        assert!(PodiumProtocol::has_outpost_data(outpost), 5);
        
        // Create subscription tier for testing subscription views
        PodiumProtocol::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"test_tier"),
            SUBSCRIPTION_WEEK_PRICE,
            1, // DURATION_WEEK
        );
        
        // Test get_tier_count
        assert!(PodiumProtocol::get_tier_count(outpost) == 1, 6);
        
        // Test get_tier_details
        let (tier_name, tier_price, tier_duration) = PodiumProtocol::get_tier_details(outpost, 0);
        assert!(tier_name == string::utf8(b"test_tier"), 7);
        assert!(tier_price == SUBSCRIPTION_WEEK_PRICE, 8);
        assert!(tier_duration == 1, 9);
        
        // Test verify_subscription (when no subscription exists)
        assert!(!PodiumProtocol::verify_subscription(signer::address_of(creator), outpost, 0), 10);
        
        // Subscribe to test subscription views
        PodiumProtocol::subscribe(creator, outpost, 0, option::none());
        
        // Test verify_subscription (with active subscription)
        assert!(PodiumProtocol::verify_subscription(signer::address_of(creator), outpost, 0), 11);
        
        // Test get_subscription
        let (sub_tier_id, start_time, end_time) = PodiumProtocol::get_subscription(signer::address_of(creator), outpost);
        assert!(sub_tier_id == 0, 12);
        assert!(end_time > start_time, 13);
        
        // Test is_paused
        assert!(!PodiumProtocol::is_paused(outpost), 14);
        PodiumProtocol::toggle_emergency_pause(creator, outpost);
        assert!(PodiumProtocol::is_paused(outpost), 15);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target)]
    public fun test_self_trading(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, podium_signer, creator, creator, creator);
        
        // Create outpost
        let outpost = create_test_outpost(creator);
        let target_addr = object::object_address(&outpost);
        
        // Create pass token
        PodiumProtocol::create_pass_token(
            creator,
            target_addr,
            string::utf8(b"Self Trade Pass"),
            string::utf8(b"Test Pass for Self Trading"),
            string::utf8(b"https://test.uri"),
        );
        
        // Record initial balances
        let initial_apt_balance = coin::balance<AptosCoin>(signer::address_of(creator));
        
        // Buy passes as creator
        let buy_amount = PASS_AMOUNT;
        PodiumProtocol::buy_pass(creator, target_addr, buy_amount, option::none());
        
        // Verify pass balance
        let asset_symbol = PodiumProtocol::get_asset_symbol(target_addr);
        let pass_balance = PodiumProtocol::get_balance(signer::address_of(creator), asset_symbol);
        assert!(pass_balance == buy_amount, 0);
        
        // Calculate fees from buy
        let (base_price, protocol_fee, subject_fee, referral_fee) = 
            PodiumProtocol::calculate_buy_price_with_fees(target_addr, buy_amount, option::none());
        let total_buy_cost = base_price + protocol_fee + subject_fee + referral_fee;
        
        // Verify APT balance after buy (should include received subject fee)
        let post_buy_balance = coin::balance<AptosCoin>(signer::address_of(creator));
        assert!(post_buy_balance == initial_apt_balance - total_buy_cost + subject_fee, 1);
        
        // Sell half the passes
        let sell_amount = buy_amount / 2;
        PodiumProtocol::sell_pass(creator, target_addr, sell_amount);
        
        // Verify updated pass balance
        let final_pass_balance = PodiumProtocol::get_balance(signer::address_of(creator), asset_symbol);
        assert!(final_pass_balance == buy_amount - sell_amount, 2);
        
        // Calculate sell fees
        let (sell_amount_received, sell_protocol_fee, sell_subject_fee) = 
            PodiumProtocol::calculate_sell_price_with_fees(target_addr, sell_amount);
        
        // Verify final APT balance (should include received subject fee from sell)
        let final_balance = coin::balance<AptosCoin>(signer::address_of(creator));
        assert!(final_balance == post_buy_balance + sell_amount_received + sell_subject_fee, 3);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target)]
    public fun test_self_subscription(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, podium_signer, creator, creator, creator);
        
        // Create outpost
        let outpost = create_test_outpost(creator);
        
        // Create subscription tier
        PodiumProtocol::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"self_tier"),
            SUBSCRIPTION_WEEK_PRICE,
            1, // DURATION_WEEK
        );
        
        // Record initial balance
        let initial_balance = coin::balance<AptosCoin>(signer::address_of(creator));
        
        // Subscribe to own outpost
        PodiumProtocol::subscribe(creator, outpost, 0, option::none());
        
        // Verify subscription is active
        assert!(PodiumProtocol::verify_subscription(signer::address_of(creator), outpost, 0), 0);
        
        // Calculate total cost and fees
        let total_cost = SUBSCRIPTION_WEEK_PRICE;
        let protocol_fee = (total_cost * 4) / 100; // 4% protocol fee
        let subject_fee = (total_cost * 8) / 100; // 8% subject fee
        
        // Verify final balance (should only be reduced by protocol fee since subject fee returns to creator)
        let final_balance = coin::balance<AptosCoin>(signer::address_of(creator));
        assert!(final_balance == initial_balance - total_cost + subject_fee, 1);
        
        // Cancel own subscription
        PodiumProtocol::cancel_subscription(creator, outpost);
        
        // Verify subscription is cancelled
        assert!(!PodiumProtocol::verify_subscription(signer::address_of(creator), outpost, 0), 2);
    }
} 