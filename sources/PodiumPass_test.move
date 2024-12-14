#[test_only]
module podium::PodiumPass_test {
    use std::string;
    use std::signer;
    use std::option;
    use std::debug;
    use aptos_framework::object::Object;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use podium::PodiumPass;
    use podium::PodiumPassCoin;
    use podium::PodiumOutpost::{Self, OutpostData};

    // Test addresses
    const ADMIN: address = @admin;
    const TREASURY: address = @admin;
    const USER1: address = @0x456;
    const USER2: address = @0x789;
    const TARGET: address = @0x123;

    // Error constants
    const ESUBSCRIPTION_NOT_FOUND: u64 = 6;
    const ESUBSCRIPTION_EXPIRED: u64 = 7;
    const ETIER_EXISTS: u64 = 8;
    const ETIER_NOT_FOUND: u64 = 9;
    const ESUBSCRIPTION_ALREADY_EXISTS: u64 = 16;

    // Test constants
    const OUTPOST_PRICE: u64 = 1000;
    const OUTPOST_FEE_SHARE: u64 = 500; // 5%
    const PASS_AMOUNT: u64 = 1;
    const SUBSCRIPTION_WEEK_PRICE: u64 = 100;
    const SUBSCRIPTION_MONTH_PRICE: u64 = 300;
    const SUBSCRIPTION_YEAR_PRICE: u64 = 3000;

    // Helper function to setup test environment
    fun setup_test(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        // Create test accounts
        account::create_account_for_test(@admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(target));

        // Setup coin for testing
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        
        // Register and fund accounts
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);
        coin::register<AptosCoin>(target);
        
        coin::deposit(signer::address_of(admin), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(user1), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(user2), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(target), coin::mint<AptosCoin>(100000, &mint_cap));

        // Initialize modules
        PodiumPass::init_module_for_test(admin);
        PodiumPassCoin::init_module_for_test(admin);
        PodiumOutpost::init_collection(admin);

        // Set timestamp for testing
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    // Helper function to create and initialize a test outpost
    fun create_test_outpost(creator: &signer): Object<OutpostData> {
        debug::print(&string::utf8(b"Creating test outpost"));
        let outpost = PodiumOutpost::create_outpost_internal(
            creator,
            string::utf8(b"Test Outpost"),
            string::utf8(b"Test Description"),
            string::utf8(b"https://test.uri"),
            OUTPOST_PRICE,
            OUTPOST_FEE_SHARE,
        );
        debug::print(&string::utf8(b"Initializing outpost configs"));
        PodiumPass::init_pass_config(creator, outpost);
        PodiumPass::init_subscription_config(creator, outpost);
        debug::print(&string::utf8(b"Test outpost created"));
        outpost
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    public fun test_buy_pass(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Buy pass
        let referrer = option::none();
        PodiumPass::buy_pass(user1, outpost, PASS_AMOUNT, referrer);

        // Verify pass ownership
        PodiumPass::assert_pass_balance(signer::address_of(user1), outpost, PASS_AMOUNT);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    public fun test_subscription(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
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
            0
        ), 1);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    public fun test_pass_trading(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Initial balances
        let user1_initial_balance = coin::balance<AptosCoin>(signer::address_of(user1));
        let user2_initial_balance = coin::balance<AptosCoin>(signer::address_of(user2));

        // User1 buys a pass
        PodiumPass::buy_pass(user1, outpost, PASS_AMOUNT, option::none());

        // Verify pass ownership
        PodiumPass::assert_pass_balance(signer::address_of(user1), outpost, PASS_AMOUNT);

        // User1 sells the pass
        PodiumPass::sell_pass(user1, outpost, PASS_AMOUNT);

        // Verify pass was sold
        PodiumPass::assert_pass_balance(signer::address_of(user1), outpost, 0);

        // User2 buys a pass at a higher price (due to bonding curve)
        PodiumPass::buy_pass(user2, outpost, PASS_AMOUNT, option::none());

        // Verify second purchase was more expensive
        let user1_spent = user1_initial_balance - coin::balance<AptosCoin>(signer::address_of(user1));
        let user2_spent = user2_initial_balance - coin::balance<AptosCoin>(signer::address_of(user2));
        assert!(user2_spent > user1_spent, 0);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    public fun test_subscription_with_referral(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
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
            0
        ), 1);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    public fun test_subscription_flow(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
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

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = 8)] // ETIER_EXISTS
    public fun test_duplicate_tier_creation(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Create subscription tier
        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            PodiumPass::get_duration_week(),
        );

        // Try to create duplicate tier
        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_MONTH_PRICE,
            PodiumPass::get_duration_month(),
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = 9)] // ETIER_NOT_FOUND
    public fun test_subscribe_nonexistent_tier(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Try to subscribe to nonexistent tier
        PodiumPass::subscribe(
            user2,
            outpost,
            0, // nonexistent tier ID
            option::none(),
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = 16)] // ESUBSCRIPTION_ALREADY_EXISTS
    public fun test_duplicate_subscription(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
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

        // Try to subscribe again (should fail)
        PodiumPass::subscribe(
            user2,
            outpost,
            0, // basic tier ID
            option::none(),
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    public fun test_subscription_expiration(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

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
}
