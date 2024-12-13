#[test_only]
module podium::PodiumPass_test {
    use std::string;
    use std::signer;
    use std::option;
    use std::debug::print as debug_print;
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
    const TREASURY: address = @admin;
    const USER1: address = @0x456;
    const USER2: address = @0x789;
    const TARGET: address = @0x123;

    // Test error codes
    const ENOT_AUTHORIZED: u64 = 1;
    const EINVALID_AMOUNT: u64 = 2;
    const ESUBSCRIPTION_ALREADY_EXISTS: u64 = 16;
    const EINVALID_SUBSCRIPTION_DURATION: u64 = 17;
    const EINVALID_SUBSCRIPTION_TIER: u64 = 18;
    const EINSUFFICIENT_PASS_BALANCE: u64 = 19;

    // Duration constants
    const DURATION_WEEK: u64 = 1;
    const DURATION_MONTH: u64 = 2;
    const DURATION_YEAR: u64 = 3;

    // Helper functions
    fun create_test_outpost(creator: &signer): Object<OutpostData> {
        debug_print(&string::utf8(b"Creating test outpost"));
        let outpost = PodiumOutpost::create_outpost_internal(
            creator,
            string::utf8(b"Test Outpost"),
            string::utf8(b"Test Description"),
            string::utf8(b"https://test.uri"),
            1000,
            500,
        );
        debug_print(&string::utf8(b"Test outpost created"));
        outpost
    }

    fun setup_test(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        debug_print(&string::utf8(b"Creating test accounts"));
        // Create test accounts
        account::create_account_for_test(@admin);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(target));

        // Setup coin for testing
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        
        debug_print(&string::utf8(b"Initializing modules"));
        // Initialize modules in correct order
        PodiumOutpost::init_collection(admin);
        debug_print(&string::utf8(b"PodiumOutpost initialized"));
        
        PodiumPassCoin::init_module_for_test(admin);
        debug_print(&string::utf8(b"PodiumPassCoin initialized"));
        
        PodiumPass::init_module_for_test(admin);
        debug_print(&string::utf8(b"PodiumPass initialized"));
        
        debug_print(&string::utf8(b"Registering and funding accounts"));
        // Register and fund accounts
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);
        coin::register<AptosCoin>(target);
        
        debug_print(&string::utf8(b"Funding accounts"));
        coin::deposit(signer::address_of(admin), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(user1), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(user2), coin::mint<AptosCoin>(100000, &mint_cap));
        coin::deposit(signer::address_of(target), coin::mint<AptosCoin>(100000, &mint_cap));

        // Set timestamp for testing
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
        
        debug_print(&string::utf8(b"Test setup complete"));
    }

    // Update each test function to include debug prints
    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_buy_pass_success(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        debug_print(&string::utf8(b"Starting test_buy_pass_success"));
        setup_test(aptos_framework, admin, user1, user2, target);

        let outpost = create_test_outpost(target);
        debug_print(&string::utf8(b"Buying pass"));
        PodiumPass::buy_pass(user1, outpost, 1, option::some(signer::address_of(user2)));

        debug_print(&string::utf8(b"Verifying pass balance"));
        PodiumPass::assert_pass_balance(signer::address_of(user1), outpost, 1);
        debug_print(&string::utf8(b"Test completed successfully"));
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = EINVALID_AMOUNT)]
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
    fun test_subscription_tier_creation(
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
            1000, // week price
            2000, // month price
            3000, // year price
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_subscription_success(
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
            1000,
            2000,
            3000,
        );

        // Subscribe
        PodiumPass::subscribe(
            user1,
            outpost,
            string::utf8(b"premium"),
            PodiumPass::get_duration_month(),
            option::some(signer::address_of(user2))
        );

        // Verify subscription
        PodiumPass::assert_subscription_exists(
            signer::address_of(user1),
            outpost,
            string::utf8(b"premium"),
            PodiumPass::get_duration_month(),
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = EINVALID_SUBSCRIPTION_TIER)]
    fun test_subscription_invalid_tier(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Try to subscribe to non-existent tier
        PodiumPass::subscribe(
            user1,
            outpost,
            string::utf8(b"nonexistent"),
            PodiumPass::get_duration_month(),
            option::none()
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = EINVALID_SUBSCRIPTION_DURATION)]
    fun test_subscription_invalid_duration(
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
            1000,
            2000,
            3000,
        );

        // Try to subscribe with invalid duration
        PodiumPass::subscribe(
            user1,
            outpost,
            string::utf8(b"premium"),
            99, // Invalid duration
            option::none()
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_subscription_cancellation(
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
            1000,
            2000,
            3000,
        );

        // Subscribe
        PodiumPass::subscribe(
            user1,
            outpost,
            string::utf8(b"premium"),
            PodiumPass::get_duration_month(),
            option::none()
        );

        // Cancel subscription
        PodiumPass::cancel_subscription(user1, outpost);

        // Verify subscription is cancelled
        assert!(!PodiumPass::verify_subscription(
            signer::address_of(user1),
            outpost,
            string::utf8(b"premium")
        ), 0);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_subscription_tier_update(
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
            1000,
            2000,
            3000,
        );

        // Update tier prices
        PodiumPass::update_subscription_tier(
            target,
            outpost,
            string::utf8(b"premium"),
            1500, // New week price
            2500, // New month price
            3500, // New year price
        );

        // Subscribe with new price
        PodiumPass::subscribe(
            user1,
            outpost,
            string::utf8(b"premium"),
            PodiumPass::get_duration_month(),
            option::none()
        );
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_multiple_pass_purchases(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Buy passes
        PodiumPass::buy_pass(user1, outpost, 2, option::none());
        PodiumPass::buy_pass(user2, outpost, 3, option::none());

        // Verify balances
        PodiumPass::assert_pass_balance(signer::address_of(user1), outpost, 2);
        PodiumPass::assert_pass_balance(signer::address_of(user2), outpost, 3);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_pass_sell_success(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Buy passes first
        PodiumPass::buy_pass(user1, outpost, 5, option::none());
        PodiumPass::assert_pass_balance(signer::address_of(user1), outpost, 5);

        // Sell some passes back
        PodiumPass::sell_pass(user1, outpost, 2);
        PodiumPass::assert_pass_balance(signer::address_of(user1), outpost, 3);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = EINVALID_AMOUNT)]
    fun test_pass_sell_zero_amount(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Try to sell zero passes
        PodiumPass::sell_pass(user1, outpost, 0);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    #[expected_failure(abort_code = EINSUFFICIENT_PASS_BALANCE)]
    fun test_pass_sell_insufficient_balance(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Buy some passes
        PodiumPass::buy_pass(user1, outpost, 2, option::none());
        
        // Try to sell more passes than owned
        PodiumPass::sell_pass(user1, outpost, 3);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_pass_buy_sell_price_changes(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Buy passes to increase price
        PodiumPass::buy_pass(user1, outpost, 10, option::none());
        PodiumPass::buy_pass(user2, outpost, 5, option::none());

        // Sell passes to decrease price
        PodiumPass::sell_pass(user1, outpost, 5);
        PodiumPass::sell_pass(user2, outpost, 2);

        // Verify final balances
        PodiumPass::assert_pass_balance(signer::address_of(user1), outpost, 5);
        PodiumPass::assert_pass_balance(signer::address_of(user2), outpost, 3);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_buy_fee_distribution(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Record initial balances
        let initial_treasury_balance = coin::balance<AptosCoin>(@treasury);
        let initial_target_balance = coin::balance<AptosCoin>(signer::address_of(target));
        let initial_referrer_balance = coin::balance<AptosCoin>(signer::address_of(user2));
        let initial_buyer_balance = coin::balance<AptosCoin>(signer::address_of(user1));

        // Buy pass with referrer
        PodiumPass::buy_pass(user1, outpost, 1, option::some(signer::address_of(user2)));

        // Calculate expected fees (based on base price of 1)
        let base_price = 1;
        let protocol_fee = (base_price * 4) / 100; // 4%
        let subject_fee = (base_price * 8) / 100;  // 8%
        let referral_fee = (base_price * 2) / 100; // 2%

        // Verify fee distribution
        assert!(coin::balance<AptosCoin>(@treasury) == initial_treasury_balance + base_price + protocol_fee, 1);
        assert!(coin::balance<AptosCoin>(signer::address_of(target)) == initial_target_balance + subject_fee, 2);
        assert!(coin::balance<AptosCoin>(signer::address_of(user2)) == initial_referrer_balance + referral_fee, 3);
        assert!(coin::balance<AptosCoin>(signer::address_of(user1)) == initial_buyer_balance - base_price - protocol_fee - subject_fee - referral_fee, 4);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_sell_fee_distribution(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Buy pass first
        PodiumPass::buy_pass(user1, outpost, 1, option::none());

        // Record balances before sell
        let initial_treasury_balance = coin::balance<AptosCoin>(@treasury);
        let initial_target_balance = coin::balance<AptosCoin>(signer::address_of(target));
        let initial_seller_balance = coin::balance<AptosCoin>(signer::address_of(user1));

        // Sell pass
        PodiumPass::sell_pass(user1, outpost, 1);

        // Calculate expected fees (based on discounted sell price)
        let base_price = 1;
        let sell_price = (base_price * (100 - 5)) / 100; // 5% sell discount
        let protocol_fee = (sell_price * 4) / 100; // 4%
        let subject_fee = (sell_price * 8) / 100;  // 8%
        let seller_payment = sell_price - protocol_fee - subject_fee;

        // Verify fee distribution
        assert!(coin::balance<AptosCoin>(@treasury) == initial_treasury_balance - sell_price, 1);
        assert!(coin::balance<AptosCoin>(signer::address_of(target)) == initial_target_balance + subject_fee, 2);
        assert!(coin::balance<AptosCoin>(signer::address_of(user1)) == initial_seller_balance + seller_payment, 3);
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_buy_sell_bonding_curve_funds(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Record initial contract balance
        let initial_contract_balance = coin::balance<AptosCoin>(@treasury);

        // Buy multiple passes to increase price
        PodiumPass::buy_pass(user1, outpost, 5, option::none());
        PodiumPass::buy_pass(user2, outpost, 3, option::none());

        // Record mid-state contract balance
        let mid_contract_balance = coin::balance<AptosCoin>(@treasury);
        assert!(mid_contract_balance > initial_contract_balance, 1);

        // Sell some passes
        PodiumPass::sell_pass(user1, outpost, 2);
        PodiumPass::sell_pass(user2, outpost, 1);

        // Verify final contract balance
        let final_contract_balance = coin::balance<AptosCoin>(@treasury);
        assert!(final_contract_balance < mid_contract_balance, 2); // Balance decreased due to sells
        assert!(final_contract_balance > initial_contract_balance, 3); // But still higher than initial
    }

    #[test(aptos_framework = @0x1, admin = @admin, user1 = @0x456, user2 = @0x789, target = @0x123)]
    fun test_multiple_buy_sell_fee_accuracy(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        target: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, target);
        let outpost = create_test_outpost(target);

        // Record initial balances
        let initial_treasury_balance = coin::balance<AptosCoin>(@treasury);
        let initial_target_balance = coin::balance<AptosCoin>(signer::address_of(target));

        // Perform multiple buys and sells
        PodiumPass::buy_pass(user1, outpost, 3, option::none());
        PodiumPass::buy_pass(user2, outpost, 2, option::none());
        PodiumPass::sell_pass(user1, outpost, 1);
        PodiumPass::buy_pass(user2, outpost, 1, option::none());
        PodiumPass::sell_pass(user2, outpost, 2);

        // Verify final balances are consistent
        let final_treasury_balance = coin::balance<AptosCoin>(@treasury);
        let final_target_balance = coin::balance<AptosCoin>(signer::address_of(target));

        assert!(final_treasury_balance >= initial_treasury_balance, 1); // Treasury should never decrease
        assert!(final_target_balance >= initial_target_balance, 2); // Target balance should never decrease
    }
} 