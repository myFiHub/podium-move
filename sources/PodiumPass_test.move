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

    // Test addresses
    const ADMIN: address = @admin;
    const USER1: address = @0x456;
    const USER2: address = @0x789;
    const TARGET: address = @0x123;

    // Test error codes
    const ENOT_AUTHORIZED: u64 = 1;
    const EINVALID_AMOUNT: u64 = 2;
    const EINVALID_FEE: u64 = 3;
    const EINVALID_DURATION: u64 = 4;
    const EINVALID_TIER: u64 = 5;
    const ESUBSCRIPTION_NOT_FOUND: u64 = 6;
    const ESUBSCRIPTION_EXPIRED: u64 = 7;
    const ETIER_EXISTS: u64 = 8;
    const ETIER_NOT_FOUND: u64 = 9;
    const EINVALID_PRICE: u64 = 10;
    const EINSUFFICIENT_BALANCE: u64 = 11;
    const EPASS_NOT_FOUND: u64 = 12;
    const EINSUFFICIENT_PASS_BALANCE: u64 = 13;

    // Test constants
    const OUTPOST_PRICE: u64 = 1000;
    const OUTPOST_FEE_SHARE: u64 = 500; // 5%
    const PASS_AMOUNT: u64 = 1;
    const SUBSCRIPTION_WEEK_PRICE: u64 = 1000;
    const SUBSCRIPTION_MONTH_PRICE: u64 = 2000;
    const SUBSCRIPTION_YEAR_PRICE: u64 = 3000;

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

    fun setup_test(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        debug::print(&string::utf8(b"Creating test accounts"));
        account::create_account_for_test(@admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(target));

        // Setup coin for testing
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        
        debug::print(&string::utf8(b"Initializing modules"));
        // Initialize modules in correct order
        PodiumOutpost::init_collection(admin);
        debug::print(&string::utf8(b"PodiumOutpost initialized"));
        
        PodiumPassCoin::init_module_for_test(admin);
        debug::print(&string::utf8(b"PodiumPassCoin initialized"));
        
        PodiumPass::init_module_for_test(admin);
        debug::print(&string::utf8(b"PodiumPass initialized"));
        
        debug::print(&string::utf8(b"Registering and funding accounts"));
        // Register and fund accounts
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);
        coin::register<AptosCoin>(target);
        
        debug::print(&string::utf8(b"Funding accounts"));
        coin::deposit(signer::address_of(admin), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(user1), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(user2), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(target), coin::mint<AptosCoin>(100000, &mint_cap));

        // Set timestamp for testing
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
        
        debug::print(&string::utf8(b"Test setup complete"));
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = 65538)] // EINVALID_AMOUNT
    fun test_buy_pass_zero_amount(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);
        PodiumPass::buy_pass(user1, outpost, 0, option::none());
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = 15)] // ENOT_OWNER
    fun test_unauthorized_subscription_tier_creation(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);
        
        // User2 attempts to create tier without owning the outpost
        PodiumPass::create_subscription_tier(
            user2,
            outpost,
            string::utf8(b"premium"),
            SUBSCRIPTION_WEEK_PRICE,
            SUBSCRIPTION_MONTH_PRICE,
            SUBSCRIPTION_YEAR_PRICE,
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = 393225)] // ETIER_NOT_FOUND
    fun test_subscribe_without_pass(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Try to subscribe without owning a pass
        PodiumPass::subscribe(
            user2,
            outpost,
            string::utf8(b"premium"),
            PodiumPass::get_duration_month(),
            option::none(),
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = 393225)] // ETIER_NOT_FOUND
    fun test_subscribe_to_nonexistent_tier(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Create a subscription tier first
        PodiumPass::create_subscription_tier(
            target,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE,
            SUBSCRIPTION_MONTH_PRICE,
            SUBSCRIPTION_YEAR_PRICE,
        );

        // Try to subscribe to non-existent tier
        PodiumPass::subscribe(
            user2,
            outpost,
            string::utf8(b"nonexistent"),
            PodiumPass::get_duration_month(),
            option::none(),
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_complete_integration_flow(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        // Step 1: Setup test environment
        setup_test(aptos_framework, admin, user1, user2, target);
        debug::print(&string::utf8(b"Step 1: Test environment setup complete"));

        // Step 2: Create outpost
        let outpost = create_test_outpost(target);
        debug::print(&string::utf8(b"Step 2: Outpost created"));

        // Step 3: Transfer outpost to user1 (simulating purchase)
        object::transfer(target, outpost, signer::address_of(user1));
        debug::print(&string::utf8(b"Step 3: Outpost transferred to user1"));

        // Step 4: User1 (new owner) creates subscription tiers
        PodiumPass::create_subscription_tier(
            user1,
            outpost,
            string::utf8(b"basic"),
            SUBSCRIPTION_WEEK_PRICE / 2,
            SUBSCRIPTION_MONTH_PRICE / 2,
            SUBSCRIPTION_YEAR_PRICE / 2,
        );
        PodiumPass::create_subscription_tier(
            user1,
            outpost,
            string::utf8(b"premium"),
            SUBSCRIPTION_WEEK_PRICE,
            SUBSCRIPTION_MONTH_PRICE,
            SUBSCRIPTION_YEAR_PRICE,
        );
        debug::print(&string::utf8(b"Step 4: Subscription tiers created"));

        // Step 5: User2 buys a pass
        PodiumPass::buy_pass(user2, outpost, PASS_AMOUNT, option::none());
        debug::print(&string::utf8(b"Step 5: User2 bought pass"));

        // Step 6: Verify pass ownership
        assert!(PodiumPass::verify_pass_ownership(signer::address_of(user2), outpost), EPASS_NOT_FOUND);
        debug::print(&string::utf8(b"Step 6: Pass ownership verified"));

        // Step 7: User2 subscribes to basic tier
        PodiumPass::subscribe(
            user2,
            outpost,
            string::utf8(b"basic"),
            PodiumPass::get_duration_month(),
            option::none(),
        );
        debug::print(&string::utf8(b"Step 7: User2 subscribed to basic tier"));

        // Step 8: Verify subscription
        assert!(PodiumPass::verify_subscription(
            signer::address_of(user2),
            outpost,
            string::utf8(b"basic")
        ), ESUBSCRIPTION_NOT_FOUND);
        debug::print(&string::utf8(b"Step 8: Subscription verified"));

        // Step 9: User2 upgrades to premium tier
        PodiumPass::subscribe(
            user2,
            outpost,
            string::utf8(b"premium"),
            PodiumPass::get_duration_month(),
            option::none(),
        );
        debug::print(&string::utf8(b"Step 9: User2 upgraded to premium tier"));

        // Step 10: Verify premium subscription
        assert!(PodiumPass::verify_subscription(
            signer::address_of(user2),
            outpost,
            string::utf8(b"premium")
        ), ESUBSCRIPTION_NOT_FOUND);
        debug::print(&string::utf8(b"Step 10: Premium subscription verified"));
    }
}
