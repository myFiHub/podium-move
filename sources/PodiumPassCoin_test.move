#[test_only]
module podium::PodiumPassCoin_test {
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use std::signer;

    use podium::PodiumPass;
    use podium::PodiumPassCoin;
    use podium::PodiumPassCoin::{Self, PassBalance};

    // Test addresses
    const ADMIN: address = @admin;
    const TREASURY: address = @treasury;
    const USER1: address = @0x456;
    const USER2: address = @0x789;

    struct TEST_TARGET {}

    fun setup(framework: &signer, admin: &signer) {
        timestamp::set_time_has_started_for_testing(framework);
        account::create_account_for_test(ADMIN);
        account::create_account_for_test(TREASURY);
        account::create_account_for_test(USER1);
        account::create_account_for_test(USER2);
        
        // Initialize modules
        PodiumPass::initialize(admin);
        PodiumPassCoin::initialize_target<TEST_TARGET>(admin, string::utf8(b"Test Pass"));
    }

    fun setup_test_coins(admin: &signer, account: address, amount: u64) {
        let coins = coin::mint<AptosCoin>(amount, &aptos_coin::mint_capability());
        coin::deposit(account, coins);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_initialize_target(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Verify initialization by checking if we can get pass balance
        let balance = PodiumPassCoin::get_pass_balance<address>(ADMIN);
        assert!(balance.amount == 0, 1);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_pass_transfer(framework: &signer, admin: &signer) {
        setup(framework, admin);
        setup_test_coins(admin, USER1, 10000000);

        // Create user signers
        let user1_signer = account::create_signer_for_test(USER1);
        
        // Purchase pass through PodiumPass
        let payment = coin::withdraw<AptosCoin>(&user1_signer, 1000000);
        PodiumPass::purchase_lifetime_access<TEST_TARGET>(
            &user1_signer,
            USER1,
            1,
            payment
        );

        // Transfer pass to USER2
        PodiumPassCoin::transfer_pass<TEST_TARGET>(&user1_signer, USER2, 1);

        // Verify balances
        let balance1 = PodiumPassCoin::get_pass_balance<address>(USER1);
        let balance2 = PodiumPassCoin::get_pass_balance<address>(USER2);
        assert!(balance1.amount == 0, 1);
        assert!(balance2.amount == 1, 2);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_get_all_holdings(framework: &signer, admin: &signer) {
        setup(framework, admin);
        setup_test_coins(admin, USER1, 10000000);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Purchase pass through PodiumPass
        let payment = coin::withdraw<AptosCoin>(&user1_signer, 1000000);
        PodiumPass::purchase_lifetime_access<TEST_TARGET>(
            &user1_signer,
            USER1,
            1,
            payment
        );

        // Get all holdings
        let holdings = PodiumPassCoin::get_all_holdings(USER1);
        assert!(vector::length(&holdings) == 1, 1);

        let holding = vector::borrow(&holdings, 0);
        assert!(holding.amount == 1, 2);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_total_supply(framework: &signer, admin: &signer) {
        setup(framework, admin);
        setup_test_coins(admin, USER1, 10000000);

        // Get initial supply
        let initial_supply = PodiumPassCoin::get_total_supply<TEST_TARGET>();
        assert!(initial_supply == 0, 1);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Purchase pass through PodiumPass
        let payment = coin::withdraw<AptosCoin>(&user1_signer, 1000000);
        PodiumPass::purchase_lifetime_access<TEST_TARGET>(
            &user1_signer,
            USER1,
            1,
            payment
        );

        // Verify supply increased
        let final_supply = PodiumPassCoin::get_total_supply<TEST_TARGET>();
        assert!(final_supply == 1, 2);
    }

    #[test(framework = @0x1, admin = @admin)]
    #[expected_failure(abort_code = 2)]
    public fun test_insufficient_balance_transfer(framework: &signer, admin: &signer) {
        setup(framework, admin);
        setup_test_coins(admin, USER1, 10000000);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Try to transfer without having any passes (should fail)
        PodiumPassCoin::transfer_pass<TEST_TARGET>(&user1_signer, USER2, 1);
    }

    #[test(sender = @0x123)]
    public entry fun test_initialize(sender: &signer) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(sender);
        let coins = coin::mint<AptosCoin>(1000000000, &mint_cap);
        coin::register<AptosCoin>(sender);
        coin::deposit(signer::address_of(sender), coins);

        PodiumPassCoin::initialize(sender);
        let balance = PodiumPassCoin::get_pass_balance<address>(signer::address_of(sender));
        assert!(PodiumPassCoin::get_pass_balance_amount(&balance) == 0, 1);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
} 