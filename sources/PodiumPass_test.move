#[test_only]
module podium::PodiumPass_test {
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::{Self, AptosCoin};

    use podium::PodiumPass;
    use podium::PodiumPassCoin;
    use podium::PodiumOutpost;

    // Test addresses
    const ADMIN: address = @admin;
    const TREASURY: address = @treasury;
    const USER1: address = @0x456;
    const USER2: address = @0x789;

    struct TEST_TARGET {}
    struct TEST_OUTPOST {}

    fun setup(framework: &signer, admin: &signer) {
        timestamp::set_time_has_started_for_testing(framework);
        account::create_account_for_test(ADMIN);
        account::create_account_for_test(TREASURY);
        account::create_account_for_test(USER1);
        account::create_account_for_test(USER2);
        
        // Initialize modules
        PodiumPass::initialize(admin);
        PodiumPassCoin::initialize_target<TEST_TARGET>(admin, string::utf8(b"Test Pass"));
        PodiumOutpost::initialize(admin);
    }

    fun setup_test_coins(admin: &signer, amount: u64) {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<AptosCoin>(
            admin,
            string::utf8(b"APT"),
            string::utf8(b"APT"),
            8,
            true
        );
        coin::destroy_freeze_cap(freeze_cap);
        
        // Mint coins and register accounts
        let coins = coin::mint(amount, &mint_cap);
        if (!coin::is_account_registered<AptosCoin>(USER1)) {
            coin::register<AptosCoin>(&account::create_signer_for_test(USER1));
        };
        coin::deposit(USER1, coins);

        // Clean up capabilities
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_initialize(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Verify initialization
        assert!(!PodiumPass::is_paused(), 0);
        assert!(PodiumPass::get_protocol_fee() == 100, 1); // 1%
        assert!(PodiumPass::get_subject_fee() == 900, 2); // 9%
        assert!(PodiumPass::get_referral_fee() == 100, 3); // 1%
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_lifetime_pass_purchase_and_redemption(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Setup test coins
        setup_test_coins(admin, 10000000);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Purchase lifetime pass
        let payment = coin::withdraw<AptosCoin>(&user1_signer, 1000000);
        PodiumPass::purchase_lifetime_access<TEST_TARGET>(
            &user1_signer,
            USER1,
            1,
            payment
        );

        // Verify purchase
        let status = PodiumPass::get_account_status<TEST_TARGET>(USER1);
        assert!(status.has_lifetime_access == true, 1);
        assert!(status.lifetime_balance == 1, 2);

        // Redeem lifetime pass
        PodiumPass::redeem_lifetime_access<TEST_TARGET>(&user1_signer, 1);

        // Verify redemption
        let status = PodiumPass::get_account_status<TEST_TARGET>(USER1);
        assert!(status.has_lifetime_access == false, 3);
        assert!(status.lifetime_balance == 0, 4);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_subscription_creation_and_verification(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Setup test coins
        setup_test_coins(admin, 10000000);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Create subscription
        let payment = coin::withdraw<AptosCoin>(&user1_signer, 1000000);
        PodiumPass::create_subscription<TEST_TARGET>(
            &user1_signer,
            USER1,
            30,
            1,
            payment
        );

        // Verify subscription
        let status = PodiumPass::get_account_status<TEST_TARGET>(USER1);
        assert!(status.has_subscription == true, 1);
        assert!(status.tier == 1, 2);
        assert!(status.subscription_end_time > timestamp::now_seconds(), 3);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_target_tier_configuration(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Create target signer
        let target_signer = account::create_signer_for_test(@target);

        // Set tier configuration
        let tier_prices = vector[1000000, 2000000, 3000000];
        PodiumPass::set_target_config<TEST_TARGET>(
            &target_signer,
            tier_prices,
            30,
            365
        );

        // Setup test coins
        setup_test_coins(admin, 10000000);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Create subscription with custom tier price
        let payment = coin::withdraw<AptosCoin>(&user1_signer, 2000000);
        PodiumPass::create_subscription<TEST_TARGET>(
            &user1_signer,
            USER1,
            30,
            2,
            payment
        );

        // Verify subscription
        let status = PodiumPass::get_account_status<TEST_TARGET>(USER1);
        assert!(status.has_subscription == true, 1);
        assert!(status.tier == 2, 2);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_bonding_curve_pricing(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Test buy price calculation
        let buy_price_1 = PodiumPass::calculate_buy_price(0, 1);
        let buy_price_2 = PodiumPass::calculate_buy_price(1, 1);
        assert!(buy_price_2 > buy_price_1, 1); // Price should increase with supply

        // Test sell price calculation
        let sell_price_1 = PodiumPass::calculate_sell_price(2, 1);
        let sell_price_2 = PodiumPass::calculate_sell_price(1, 1);
        assert!(sell_price_1 > sell_price_2, 2); // Price should decrease with lower supply
    }

    #[test(framework = @0x1, admin = @admin)]
    #[expected_failure(abort_code = 11)]
    public fun test_non_whole_number_lifetime_pass(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Setup test coins
        setup_test_coins(admin, 10000000);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Try to purchase non-whole number of passes (should fail)
        let payment = coin::withdraw<AptosCoin>(&user1_signer, 1000000);
        PodiumPass::purchase_lifetime_access<TEST_TARGET>(
            &user1_signer,
            USER1,
            0,  // Invalid amount
            payment
        );
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_fee_distribution(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Setup test coins
        setup_test_coins(admin, 10000000);

        // Record initial balances
        let initial_treasury = coin::balance<AptosCoin>(TREASURY);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Purchase lifetime pass
        let payment = coin::withdraw<AptosCoin>(&user1_signer, 1000000);
        PodiumPass::purchase_lifetime_access<TEST_TARGET>(
            &user1_signer,
            USER1,
            1,
            payment
        );

        // Verify fee distribution
        let final_treasury = coin::balance<AptosCoin>(TREASURY);
        assert!(final_treasury > initial_treasury, 1);
    }
} 