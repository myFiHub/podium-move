#[test_only]
module podium::PodiumPass_test {
    use std::string;
    use std::signer;
    use std::option;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use podium::PodiumPass;
    use podium::PodiumPassCoin;
    use podium::PodiumOutpost::{Self, OutpostData};

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

    // Test helper function to create test accounts
    fun create_test_account(): signer {
        account::create_account_for_test(@0x123)
    }

    // Test helper function to create target account
    fun create_target_account(): signer {
        account::create_account_for_test(@0x456)
    }

    // Test helper function to create outpost
    fun create_test_outpost(creator: &signer): Object<OutpostData> {
        PodiumOutpost::create_outpost_internal(
            creator,
            string::utf8(b"Test Outpost"),
            string::utf8(b"Test Description"),
            string::utf8(b"https://test.uri"),
            1000,
            500,
        )
    }

    #[test(admin = @admin)]
    fun test_buy_pass_success(admin: &signer) {
        // Create accounts
        let user1 = create_test_account();
        let target = create_target_account();
        let referrer = create_test_account();

        // Create outpost
        let outpost = create_test_outpost(&target);

        // Buy pass
        PodiumPass::buy_pass(&user1, outpost, 1, option::some(signer::address_of(&referrer)));
    }

    #[test(admin = @admin)]
    fun test_subscription_tier_creation(admin: &signer) {
        // Create accounts
        let target = create_target_account();
        
        // Create outpost
        let outpost = create_test_outpost(&target);

        // Create subscription tier
        PodiumPass::create_subscription_tier(
            &target,
            outpost,
            string::utf8(b"premium"),
            1000, // month price
            2000, // renewal price
            3000, // year price
        );
    }

    #[test(admin = @admin)]
    fun test_subscription_success(admin: &signer) {
        // Create accounts
        let user1 = create_test_account();
        let target = create_target_account();
        let referrer = create_test_account();

        // Create outpost
        let outpost = create_test_outpost(&target);

        // Create subscription tier
        PodiumPass::create_subscription_tier(
            &target,
            outpost,
            string::utf8(b"premium"),
            1000,
            2000,
            3000,
        );

        // Subscribe
        PodiumPass::subscribe(
            &user1,
            outpost,
            string::utf8(b"premium"),
            PodiumPass::get_duration_month(),
            option::some(signer::address_of(&referrer))
        );
    }

    #[test(admin = @admin)]
    fun test_multiple_pass_purchases(admin: &signer) {
        // Create accounts
        let user1 = create_test_account();
        let user2 = create_test_account();
        let target = create_target_account();
        let referrer = create_test_account();

        // Create outpost
        let outpost = create_test_outpost(&target);

        // Buy passes
        PodiumPass::buy_pass(&user1, outpost, 1, option::some(signer::address_of(&referrer)));
        PodiumPass::buy_pass(&user2, outpost, 1, option::some(signer::address_of(&referrer)));
    }

    #[test(admin = @admin)]
    fun test_multiple_subscription_tiers(admin: &signer) {
        // Create accounts
        let user1 = create_test_account();
        let target = create_target_account();

        // Create outpost
        let outpost = create_test_outpost(&target);

        // Create subscription tiers
        PodiumPass::create_subscription_tier(
            &target,
            outpost,
            string::utf8(b"basic"),
            1000,
            2000,
            3000,
        );

        // Subscribe to basic tier
        PodiumPass::subscribe(
            &user1,
            outpost,
            string::utf8(b"basic"),
            PodiumPass::get_duration_week(),
            option::none()
        );
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
        PodiumOutpost::init_collection(admin);

        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
} 