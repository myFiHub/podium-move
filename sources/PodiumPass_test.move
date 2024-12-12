#[test_only]
module podium::PodiumPass_test {
    use std::string;
    use std::signer;
    use std::option;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use podium::PodiumPass;
    use podium::PodiumPassCoin;
    use podium::PodiumOutpost;

    // Test addresses
    const ADMIN: address = @podium;
    const TREASURY: address = @podium;
    const USER1: address = @0x456;
    const USER2: address = @0x789;
    const TARGET: address = @0x123;

    // Test error codes
    const ENOT_AUTHORIZED: u64 = 1;
    const EINVALID_AMOUNT: u64 = 2;

    // Duration constants
    const DURATION_WEEK: u64 = 1;
    const DURATION_MONTH: u64 = 2;
    const DURATION_YEAR: u64 = 3;

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_buy_pass(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, admin, user1, user2, target);

        // Fund user account
        coin::register<AptosCoin>(user1);
        coin::transfer<AptosCoin>(admin, signer::address_of(user1), 1000);

        // Buy pass
        let referrer = option::none();
        PodiumPass::buy_pass(user1, signer::address_of(target), 1, referrer);

        // Verify pass ownership
        let (has_access, tier) = PodiumPass::verify_access(
            signer::address_of(user1),
            signer::address_of(target)
        );
        assert!(has_access, 0);
        assert!(option::is_none(&tier), 1); // Lifetime pass has no tier
    }

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_subscription(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);

        // Create subscription tier
        let target_addr = signer::address_of(target);
        PodiumPass::create_subscription_tier(
            target,
            target_addr,
            string::utf8(b"premium"),
            100, // week price
            300, // month price
            3000, // year price
        );

        // Fund user account
        coin::register<AptosCoin>(user1);
        coin::transfer<AptosCoin>(admin, signer::address_of(user1), 1000);

        // Subscribe
        let referrer = option::none();
        PodiumPass::subscribe(
            user1,
            target_addr,
            string::utf8(b"premium"),
            PodiumPass::get_duration_month(),
            referrer
        );

        // Verify subscription
        let (has_access, tier) = PodiumPass::verify_access(
            signer::address_of(user1),
            target_addr
        );
        assert!(has_access, 0);
        assert!(option::is_some(&tier), 1);
        assert!(option::extract(&mut tier) == string::utf8(b"premium"), 2);
    }

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_bonding_curve_pricing(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);

        // Fund users
        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);
        coin::transfer<AptosCoin>(admin, signer::address_of(user1), 10000);
        coin::transfer<AptosCoin>(admin, signer::address_of(user2), 10000);

        let target_addr = signer::address_of(target);
        let referrer = option::none();

        // First purchase should be at initial price (1 $MOVE)
        PodiumPass::buy_pass(user1, target_addr, 1, referrer);

        // Second purchase should be more expensive in $MOVE
        PodiumPass::buy_pass(user2, target_addr, 1, referrer);

        // Verify increasing prices through balances
        assert!(coin::balance<AptosCoin>(signer::address_of(user2)) < coin::balance<AptosCoin>(signer::address_of(user1)), 0);
    }

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_subscription_expiration(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);

        // Create subscription tier
        let target_addr = signer::address_of(target);
        PodiumPass::create_subscription_tier(
            target,
            target_addr,
            string::utf8(b"basic"),
            100,
            300,
            3000,
        );

        // Fund user
        coin::register<AptosCoin>(user1);
        coin::transfer<AptosCoin>(admin, signer::address_of(user1), 1000);

        // Subscribe
        PodiumPass::subscribe(
            user1,
            target_addr,
            string::utf8(b"basic"),
            PodiumPass::get_duration_week(),
            option::none()
        );

        // Verify active subscription
        assert!(PodiumPass::is_subscription_active(signer::address_of(user1), target_addr), 0);

        // Move time forward past expiration
        timestamp::fast_forward_seconds(8 * 24 * 60 * 60); // 8 days

        // Verify subscription expired
        assert!(!PodiumPass::is_subscription_active(signer::address_of(user1), target_addr), 1);
    }

    // Helper functions
    fun setup_test(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        // Create test accounts
        account::create_account_for_test(@podium);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(target));

        // Setup coin for testing
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        coin::register<AptosCoin>(admin);
        coin::deposit(signer::address_of(admin), coin::mint<AptosCoin>(100000, &mint_cap));
        
        // Initialize modules
        PodiumPass::init_module_for_test(admin);
        PodiumPassCoin::init_module_for_test(admin);
        PodiumOutpost::init_module_for_test(admin);

        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
} 