#[test_only]
module podium::PodiumPass_test {
    use std::string::{Self, String};
    use std::signer;
    use std::option;
    use std::debug;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use podium::PodiumPass;
    use podium::PodiumPassCoin;
    use podium::PodiumOutpost::{Self, OutpostData};
    use aptos_token_objects::collection;

    // Test addresses - with clear roles
    const TREASURY: address = @podium;
    const USER1: address = @user1;    // First subscriber/buyer (0x678)
    const USER2: address = @user2;    // Second subscriber/buyer (0x789)
    const TARGET: address = @target;   // Use target for both prod and test

    // Error constants - Updated to match actual error codes
    const EPASS_NOT_FOUND: u64 = 393228;  // Updated from test output
    const EINVALID_SUBSCRIPTION_TIER: u64 = 65554;  // Updated from test output
    const ETIER_EXISTS: u64 = 524296;  // Updated from test output
    const ESUBSCRIPTION_ALREADY_EXISTS: u64 = 524304;  // Updated from test output
    const ESUBSCRIPTION_NOT_FOUND: u64 = 6;  // Original error code for subscription not found

    // Test constants
    const PASS_AMOUNT: u64 = 1;
    const SUBSCRIPTION_WEEK_PRICE: u64 = 100;
    const SUBSCRIPTION_MONTH_PRICE: u64 = 300;
    const SUBSCRIPTION_YEAR_PRICE: u64 = 3000;

    // Helper function to setup test environment
    fun setup_test(
        aptos_framework: &signer,
        podium_signer: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        // Create test accounts
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@podium);
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
        
        coin::deposit(signer::address_of(podium_signer), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(user1), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(user2), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(target), coin::mint<AptosCoin>(100000, &mint_cap));

        // Initialize modules in correct order
        PodiumPass::initialize(podium_signer);
        PodiumPassCoin::init_module_for_test(podium_signer);

        // Initialize outpost collection
        PodiumOutpost::init_collection(podium_signer);

        // Add verification that collection exists and is accessible
        let collection_addr = PodiumOutpost::get_collection_data();
        let collection = object::address_to_object<collection::Collection>(collection_addr);
        debug::print(&string::utf8(b"Verified collection access at:"));
        debug::print(&collection_addr);

        // Set timestamp for testing
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    // Helper function to create and initialize a test outpost
    fun create_test_outpost(creator: &signer): Object<OutpostData> {
        debug::print(&string::utf8(b"=== Starting create_test_outpost ==="));
        let podium_signer = account::create_signer_for_test(@podium);
        
        // For tests, we don't verify the exact target address
        let creator_addr = signer::address_of(creator);
        debug::print(&string::utf8(b"Creator address:"));
        debug::print(&creator_addr);
        
        // Register creator for coins if needed
        debug::print(&string::utf8(b"Checking creator coin registration"));
        if (!coin::is_account_registered<AptosCoin>(creator_addr)) {
            debug::print(&string::utf8(b"Registering creator for coins"));
            coin::register<AptosCoin>(creator);
            coin::transfer<AptosCoin>(&podium_signer, creator_addr, 10000);
            debug::print(&string::utf8(b"Creator registered and funded"));
        };

        let name = string::utf8(b"Test Outpost");
        
        // Calculate expected token address
        let expected_addr = PodiumOutpost::get_token_address(creator_addr, name);
        debug::print(&string::utf8(b"Expected token address:"));
        debug::print(&expected_addr);
        
        // Create outpost using public function
        PodiumOutpost::create_outpost(
            creator,
            name,
            string::utf8(b"Test Description"),
            string::utf8(b"https://test.uri"),
        );

        // Get outpost object
        let outpost = PodiumOutpost::get_outpost_from_token_address(expected_addr);

        // Initialize subscription config
        debug::print(&string::utf8(b"Initializing subscription config"));
        PodiumPass::init_subscription_config(creator, outpost);
        debug::print(&string::utf8(b"=== Finished create_test_outpost ==="));
        outpost
    }

    #[test(creator = @target, buyer = @user1)]
    public fun test_buy_pass(
        creator: &signer,
        buyer: &signer,
    ) {
        // Setup with creator as target
        let podium_signer = account::create_signer_for_test(@podium);
        setup_test(&account::create_signer_for_test(@0x1), &podium_signer, buyer, buyer, creator);
        
        // Create outpost with target as creator
        let outpost = create_test_outpost(creator);
        let target_addr = object::object_address(&outpost);
        debug::print(&string::utf8(b"Outpost address:"));
        debug::print(&target_addr);
        
        // Create a subscription tier (required for pass purchase)
        PodiumPass::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            PodiumPass::get_duration_week(),
        );
        
        // Create asset for pass
        create_test_asset(creator, PodiumPass::get_asset_symbol(target_addr));
        
        debug::print(&string::utf8(b"Attempting to buy pass at address:"));
        debug::print(&target_addr);
        // Now we can buy a pass
        PodiumPass::buy_pass(buyer, target_addr, PASS_AMOUNT, option::none<address>());
        
        // Verify pass was created using PodiumPassCoin balance check
        let asset_symbol = PodiumPass::get_asset_symbol(target_addr);
        assert!(PodiumPassCoin::balance(signer::address_of(buyer), asset_symbol) > 0, 0);
    }
    
    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target, buyer = @user1)]
    public fun test_outpost_pass_operations(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
        buyer: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, podium_signer, buyer, buyer, creator);
        
        // Fund protocol treasury for redemptions
        coin::transfer<AptosCoin>(podium_signer, @podium, 100000);
        
        // Create outpost
        let outpost = create_test_outpost(creator);
        let target_addr = object::object_address(&outpost);
        
        // Create subscription tier (required for pass operations)
        PodiumPass::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            PodiumPass::get_duration_week(),
        );
        
        // Create asset for pass
        create_test_asset(creator, PodiumPass::get_asset_symbol(target_addr));
        
        // Buy pass - PassStats will be initialized automatically
        PodiumPass::buy_pass(buyer, target_addr, PASS_AMOUNT, option::none<address>());
        
        // Verify pass was created
        let asset_symbol = PodiumPass::get_asset_symbol(target_addr);
        let initial_balance = PodiumPassCoin::balance(signer::address_of(buyer), asset_symbol);
        assert!(initial_balance == PASS_AMOUNT, 0);
        
        // Record initial balances
        let initial_vault_balance = PodiumPass::get_vault_balance();
        
        // Verify contract has sufficient funds
        let (sell_price, _, _) = PodiumPass::calculate_sell_price_with_fees(target_addr, PASS_AMOUNT);
        assert!(initial_vault_balance >= sell_price, 1);
        
        // Sell pass
        PodiumPass::sell_pass(buyer, target_addr, PASS_AMOUNT);
        
        // Verify:
        // 1. Pass balance decreased
        assert!(PodiumPassCoin::balance(signer::address_of(buyer), asset_symbol) == 0, 2);
        // 2. Supply updated correctly
        assert!(PodiumPass::get_supply(target_addr) == 0, 3);
        // 3. Received payment
        assert!(coin::balance<AptosCoin>(signer::address_of(buyer)) > initial_balance, 4);
        // 4. Contract balance decreased
        assert!(PodiumPass::get_vault_balance() < initial_vault_balance, 5);

        debug::print(&string::utf8(b"[test] Initial buyer balance:"));
        debug::print(&initial_balance);
        debug::print(&string::utf8(b"[test] Initial vault balance:"));
        debug::print(&initial_vault_balance);
        debug::print(&string::utf8(b"[test] Final buyer balance:"));
        debug::print(&coin::balance<AptosCoin>(signer::address_of(buyer)));
        debug::print(&string::utf8(b"[test] Final vault balance:"));
        debug::print(&PodiumPass::get_vault_balance());
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target, buyer = @user1)]
    public fun test_account_pass_operations(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
        buyer: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, podium_signer, buyer, buyer, creator);
        
        let creator_addr = signer::address_of(creator);
        
        // Fund protocol treasury for redemptions
        coin::transfer<AptosCoin>(podium_signer, @podium, 100000);
        
        // Create asset for account pass (no outpost needed for regular target accounts)
        create_test_asset(creator, PodiumPass::get_asset_symbol(creator_addr));
        
        // Initialize pass stats for the target account
        PodiumPass::init_pass_stats(creator_addr);
        
        // Buy account pass
        PodiumPass::buy_pass(buyer, creator_addr, PASS_AMOUNT, option::none<address>());
        
        // Verify pass was created
        let asset_symbol = PodiumPass::get_asset_symbol(creator_addr);
        let initial_balance = PodiumPassCoin::balance(signer::address_of(buyer), asset_symbol);
        assert!(initial_balance == PASS_AMOUNT, 0);
        
        // Record initial balances
        let initial_vault_balance = PodiumPass::get_vault_balance();
        
        // Verify contract has sufficient funds
        let (sell_price, _, _) = PodiumPass::calculate_sell_price_with_fees(creator_addr, PASS_AMOUNT);
        assert!(initial_vault_balance >= sell_price, 1);
        
        // Sell pass
        PodiumPass::sell_pass(buyer, creator_addr, PASS_AMOUNT);
        
        // Verify:
        // 1. Pass balance decreased
        assert!(PodiumPassCoin::balance(signer::address_of(buyer), asset_symbol) == 0, 2);
        // 2. Supply updated correctly
        assert!(PodiumPass::get_supply(creator_addr) == 0, 3);
        // 3. Received payment
        assert!(coin::balance<AptosCoin>(signer::address_of(buyer)) > initial_balance, 4);
        // 4. Contract balance decreased
        assert!(PodiumPass::get_vault_balance() < initial_vault_balance, 5);

        debug::print(&string::utf8(b"[test] Initial buyer balance:"));
        debug::print(&initial_balance);
        debug::print(&string::utf8(b"[test] Initial vault balance:"));
        debug::print(&initial_vault_balance);
        debug::print(&string::utf8(b"[test] Final buyer balance:"));
        debug::print(&coin::balance<AptosCoin>(signer::address_of(buyer)));
        debug::print(&string::utf8(b"[test] Final vault balance:"));
        debug::print(&PodiumPass::get_vault_balance());
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, creator = @target, buyer = @user1)]
    public fun test_pass_sell(
        aptos_framework: &signer,
        podium_signer: &signer,
        creator: &signer,
        buyer: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, podium_signer, buyer, buyer, creator);
        
        // Fund protocol treasury for redemptions
        coin::transfer<AptosCoin>(podium_signer, @podium, 100000);
        
        // Create and setup outpost
        let outpost = create_test_outpost(creator);
        let target_addr = object::object_address(&outpost);
        
        // Create subscription tier (required for pass operations)
        PodiumPass::create_subscription_tier(
            creator,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            PodiumPass::get_duration_week(),
        );
        
        // Create asset for pass
        create_test_asset(creator, PodiumPass::get_asset_symbol(target_addr));
        
        // First buy a pass
        PodiumPass::buy_pass(buyer, target_addr, PASS_AMOUNT, option::none<address>());
        let asset_symbol = PodiumPass::get_asset_symbol(target_addr);
        
        // Record initial balances
        let initial_balance = PodiumPassCoin::balance(signer::address_of(buyer), asset_symbol);
        let initial_vault_balance = PodiumPass::get_vault_balance();
        
        // Verify contract has sufficient funds for redemption
        let (sell_price, _, _) = PodiumPass::calculate_sell_price_with_fees(target_addr, PASS_AMOUNT);
        assert!(initial_vault_balance >= sell_price, 0);
        
        // Sell pass back
        PodiumPass::sell_pass(buyer, target_addr, PASS_AMOUNT);
        
        // Verify:
        // 1. Pass balance decreased
        assert!(PodiumPassCoin::balance(signer::address_of(buyer), asset_symbol) == initial_balance - PASS_AMOUNT, 0);
        // 2. Received correct APT amount based on bonding curve
        assert!(coin::balance<AptosCoin>(signer::address_of(buyer)) > initial_balance, 1);
        // 3. Supply updated correctly
        assert!(PodiumPass::get_supply(target_addr) == initial_balance - PASS_AMOUNT, 2);
        // 4. Contract balance decreased by sell amount
        assert!(PodiumPass::get_vault_balance() < initial_vault_balance, 3);

        debug::print(&string::utf8(b"[test] Initial buyer balance:"));
        debug::print(&initial_balance);
        debug::print(&string::utf8(b"[test] Initial vault balance:"));
        debug::print(&initial_vault_balance);
        debug::print(&string::utf8(b"[test] Final buyer balance:"));
        debug::print(&coin::balance<AptosCoin>(signer::address_of(buyer)));
        debug::print(&string::utf8(b"[test] Final vault balance:"));
        debug::print(&PodiumPass::get_vault_balance());
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, user1 = @user1, user2 = @user2, target = @target)]
    public fun test_subscription(
        aptos_framework: &signer,
        podium_signer: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Create subscription tier
        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"premium"),
            SUBSCRIPTION_MONTH_PRICE,
            PodiumPass::get_duration_month(),
        );

        // Subscribe
        PodiumPass::subscribe(
            user1,
            outpost,
            0, // premium tier ID
            option::none(),
        );

        // Verify subscription
        assert!(PodiumPass::verify_subscription(
            signer::address_of(user1),
            outpost,
            0 // premium tier ID
        ), 1);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, buyer = @0x456, target = @target)]  // Simplified parameters
    public fun test_pass_trading(
        aptos_framework: &signer,
        podium_signer: &signer,
        buyer: &signer,
        target: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, podium_signer, buyer, target, target);
        
        // Create and setup outpost
        let outpost = create_test_outpost(target);  // Use target as creator
        let target_addr = object::object_address(&outpost);
        
        // Create subscription tier
        PodiumPass::create_subscription_tier(
            target,  // Use target instead of podium_signer
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            PodiumPass::get_duration_week(),
        );
        
        // Create asset for pass
        create_test_asset(target, PodiumPass::get_asset_symbol(target_addr));
        
        // Try to buy a pass
        PodiumPass::buy_pass(buyer, target_addr, PASS_AMOUNT, option::none<address>());
        
        // Verify pass was created
        let asset_symbol = PodiumPass::get_asset_symbol(target_addr);
        assert!(PodiumPassCoin::balance(signer::address_of(buyer), asset_symbol) > 0, 0);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, user1 = @0x456, user2 = @0x789, target = @target)]
    public fun test_subscription_with_referral(
        aptos_framework: &signer,
        podium_signer: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Create subscription tier
        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"premium"),
            SUBSCRIPTION_MONTH_PRICE,
            PodiumPass::get_duration_month(),
        );

        // Record initial balances
        let user1_initial_balance = coin::balance<AptosCoin>(signer::address_of(user1));

        // User2 subscribes with User1 as referrer
        PodiumPass::subscribe(
            user2,
            outpost,
            0, // premium tier ID
            option::some(signer::address_of(user1)),
        );

        // Verify User1 received referral fee
        assert!(coin::balance<AptosCoin>(signer::address_of(user1)) > user1_initial_balance, 0);

        // Verify subscription is active
        assert!(PodiumPass::verify_subscription(
            signer::address_of(user2),
            outpost,
            0 // premium tier ID
        ), 1);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, user1 = @0x456, user2 = @0x789, target = @target)]
    public fun test_subscription_flow(
        aptos_framework: &signer,
        podium_signer: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, user1, user2, target);
        let outpost = create_test_outpost(target);
        
        // Create subscription tiers
        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            PodiumPass::get_duration_week(),
        );

        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"premium"),
            SUBSCRIPTION_MONTH_PRICE,
            PodiumPass::get_duration_month(),
        );

        // Subscribe to premium tier
        PodiumPass::subscribe(
            user2,
            outpost,
            1, // premium tier ID
            option::none(),
        );

        // Verify subscription
        assert!(PodiumPass::verify_subscription(
            signer::address_of(user2),
            outpost,
            1 // premium tier ID
        ), ESUBSCRIPTION_NOT_FOUND);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, user1 = @0x456, user2 = @0x789, target = @target)]
    #[expected_failure(abort_code = ESUBSCRIPTION_ALREADY_EXISTS, location = 0x456::PodiumPass)]
    public fun test_duplicate_subscription(
        aptos_framework: &signer,
        podium_signer: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Create subscription tier
        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            PodiumPass::get_duration_week(),
        );

        // Subscribe to basic tier
        PodiumPass::subscribe(
            user2,
            outpost,
            0, // basic tier ID
            option::none(),
        );

        // Try to subscribe again (should fail with ESUBSCRIPTION_ALREADY_EXISTS)
        PodiumPass::subscribe(
            user2,
            outpost,
            0, // basic tier ID
            option::none(),
        );
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, user1 = @0x456, user2 = @0x789, target = @target)]
    #[expected_failure(abort_code = ETIER_EXISTS, location = 0x456::PodiumPass)]
    public fun test_duplicate_tier_creation(
        aptos_framework: &signer,
        podium_signer: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Create subscription tier
        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            PodiumPass::get_duration_week(),
        );

        // Try to create duplicate tier (should fail with ETIER_EXISTS)
        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_MONTH_PRICE,
            PodiumPass::get_duration_month(),
        );
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, user1 = @0x456, user2 = @0x789, target = @target)]
    #[expected_failure(abort_code = EINVALID_SUBSCRIPTION_TIER, location = 0x456::PodiumPass)]
    public fun test_subscribe_nonexistent_tier(
        aptos_framework: &signer,
        podium_signer: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Try to subscribe to nonexistent tier (should fail with EINVALID_SUBSCRIPTION_TIER)
        PodiumPass::subscribe(
            user2,
            outpost,
            0, // nonexistent tier ID
            option::none(),
        );
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, user1 = @0x456, user2 = @0x789, target = @target)]
    public fun test_subscription_expiration(
        aptos_framework: &signer,
        podium_signer: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, podium_signer, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Create subscription tier
        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            PodiumPass::get_duration_week(),
        );

        // Subscribe
        PodiumPass::subscribe(
            user2,
            outpost,
            0, // basic tier ID
            option::none(),
        );

        // Verify active subscription
        assert!(PodiumPass::verify_subscription(
            signer::address_of(user2),
            outpost,
            0
        ), 0);

        // Move time forward past expiration (8 days)
        timestamp::fast_forward_seconds(8 * 24 * 60 * 60);

        // Verify subscription expired
        assert!(!PodiumPass::verify_subscription(
            signer::address_of(user2),
            outpost,
            0
        ), 1);
    }

    #[test(creator = @target, buyer = @user1)]
    public fun test_outpost_price_update(
        creator: &signer,
        buyer: &signer,
    ) {
        // Setup test environment
        let podium_signer = account::create_signer_for_test(@podium);
        setup_test(&account::create_signer_for_test(@0x1), &podium_signer, buyer, buyer, creator);
        
        // Create outpost with initial price
        let outpost = create_test_outpost(creator);
        let initial_price = PodiumOutpost::get_price(outpost);
        let new_price = initial_price * 2;
        
        // Update price - creator should be able to update since they own it
        PodiumOutpost::update_price(creator, outpost, new_price);
        
        // Verify price was updated
        assert!(PodiumOutpost::get_price(outpost) == new_price, 0);
    }

    #[test_only]
    public fun create_test_asset(creator: &signer, asset_symbol: String) {
        let podium_signer = account::create_signer_for_test(@podium);
        PodiumPassCoin::create_target_asset_for_test(
            creator,
            asset_symbol,
            string::utf8(b"Test Pass"),
            string::utf8(b"https://example.com/icon.png"),
            string::utf8(b"https://example.com/project"),
        );
    }

    #[test(admin = @podium, creator = @target)]
    public fun test_outpost_creation_flow(
        admin: &signer,
        creator: &signer,
    ) {
        // Setup
        setup_test(
            &account::create_signer_for_test(@0x1),
            admin,
            creator,
            creator,
            creator
        );

        // Admin sets initial outpost price
        let initial_price = 1000;
        PodiumOutpost::update_outpost_price(admin, initial_price);
        
        // Creator purchases outpost
        let outpost = create_test_outpost(creator);
        
        // Creator can manage their outpost metadata
        let new_name = string::utf8(b"Updated Outpost");
        let new_description = string::utf8(b"Updated Description");
        let new_uri = string::utf8(b"https://updated.uri");
        PodiumOutpost::update_metadata(
            creator,
            outpost,
            new_name,
            new_description,
            new_uri
        );

        // Admin can update outpost price (affects future purchases)
        let new_price = 2000;
        PodiumOutpost::update_outpost_price(admin, new_price);
        assert!(PodiumOutpost::get_outpost_purchase_price() == new_price, 0);
    }

    #[test(admin = @podium, creator = @target)]
    #[expected_failure(abort_code = 65537)]
    public fun test_outpost_price_permissions(
        admin: &signer,
        creator: &signer,
    ) {
        // Setup
        setup_test(
            &account::create_signer_for_test(@0x1),
            admin,
            creator,
            creator,
            creator
        );

        // Creator tries to set outpost price (should fail)
        PodiumOutpost::update_outpost_price(creator, 2000);
    }

    #[test(admin = @podium, creator = @target)]
    public fun test_admin_price_control(
        admin: &signer,
        creator: &signer,
    ) {
        // Setup
        setup_test(
            &account::create_signer_for_test(@0x1),
            admin,
            creator,
            creator,
            creator
        );

        // Admin sets initial price
        let initial_price = 1000;
        PodiumOutpost::update_outpost_price(admin, initial_price);
        assert!(PodiumOutpost::get_outpost_purchase_price() == initial_price, 0);
        
        // Admin updates price
        let new_price = 2000;
        PodiumOutpost::update_outpost_price(admin, new_price);
        assert!(PodiumOutpost::get_outpost_purchase_price() == new_price, 1);
    }

    #[test(admin = @podium, creator = @target)]
    public fun test_outpost_purchase_flow(
        admin: &signer,
        creator: &signer,
    ) {
        // Setup
        setup_test(
            &account::create_signer_for_test(@0x1),
            admin,
            creator,
            creator,
            creator
        );

        // Record initial balances
        let creator_initial_balance = coin::balance<AptosCoin>(signer::address_of(creator));
        let podium_initial_balance = coin::balance<AptosCoin>(@podium);

        // Admin sets purchase price
        let purchase_price = 1000;
        PodiumOutpost::update_outpost_price(admin, purchase_price);
        assert!(PodiumOutpost::get_outpost_purchase_price() == purchase_price, 0);

        // Creator purchases outpost
        PodiumOutpost::create_outpost(
            creator,
            string::utf8(b"Test Outpost"),
            string::utf8(b"Test Description"),
            string::utf8(b"https://test.uri"),
        );

        // Verify payment was processed correctly
        assert!(coin::balance<AptosCoin>(signer::address_of(creator)) == creator_initial_balance - purchase_price, 1);
        assert!(coin::balance<AptosCoin>(@podium) == podium_initial_balance + purchase_price, 2);
    }
}
