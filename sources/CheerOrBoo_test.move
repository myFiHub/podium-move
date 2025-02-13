#[test_only]
module podium::CheerOrBoo_test {
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use podium::CheerOrBoo;

    const SENDER: address = @0x123;
    const TARGET: address = @0x456;
    const PARTICIPANT1: address = @0x789;
    const PARTICIPANT2: address = @0x321;

    #[test(aptos_framework = @0x1)]
    fun test_cheer(aptos_framework: &signer) {
        // Create test accounts
        let sender = account::create_account_for_test(SENDER);
        let target = account::create_account_for_test(TARGET);
        let participant1 = account::create_account_for_test(PARTICIPANT1);
        let participant2 = account::create_account_for_test(PARTICIPANT2);

        // Initialize AptosCoin for testing
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);

        // Register and fund accounts
        coin::register<AptosCoin>(&sender);
        coin::register<AptosCoin>(&target);
        coin::register<AptosCoin>(&participant1);
        coin::register<AptosCoin>(&participant2);

        // Fund sender with test coins
        let coins = coin::mint<AptosCoin>(1000000000, &mint_cap);
        coin::deposit(SENDER, coins);

        let participants = vector::empty<address>();
        vector::push_back(&mut participants, PARTICIPANT1);
        vector::push_back(&mut participants, PARTICIPANT2);

        let initial_target_balance = coin::balance<AptosCoin>(TARGET);
        let initial_p1_balance = coin::balance<AptosCoin>(PARTICIPANT1);
        let initial_p2_balance = coin::balance<AptosCoin>(PARTICIPANT2);

        // Send cheer with 1000 coins, 50% to target
        CheerOrBoo::cheer_or_boo(
            &sender,
            TARGET,
            participants,
            true, // is_cheer
            1000,
            50, // target_allocation
            b"test_cheer_1"
        );

        // Verify balances
        let fee = 1000 * 5 / 100; // 5% fee
        let net_amount = 1000 - fee;
        let target_amount = net_amount * 50 / 100;
        let participant_amount = (net_amount - target_amount) / 2;

        assert!(coin::balance<AptosCoin>(TARGET) == initial_target_balance + target_amount, 1);
        assert!(coin::balance<AptosCoin>(PARTICIPANT1) == initial_p1_balance + participant_amount, 2);
        assert!(coin::balance<AptosCoin>(PARTICIPANT2) == initial_p2_balance + participant_amount, 3);

        // Clean up
        coin::destroy_burn_cap<AptosCoin>(burn_cap);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
    }

    #[test(aptos_framework = @0x1)]
    fun test_boo(aptos_framework: &signer) {
        // Create test accounts
        let sender = account::create_account_for_test(SENDER);
        let target = account::create_account_for_test(TARGET);
        let participant1 = account::create_account_for_test(PARTICIPANT1);

        // Initialize AptosCoin for testing
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);

        // Register and fund accounts
        coin::register<AptosCoin>(&sender);
        coin::register<AptosCoin>(&target);
        coin::register<AptosCoin>(&participant1);

        // Fund sender with test coins
        let coins = coin::mint<AptosCoin>(1000000000, &mint_cap);
        coin::deposit(SENDER, coins);
        
        let participants = vector::empty<address>();
        vector::push_back(&mut participants, PARTICIPANT1);

        let initial_target_balance = coin::balance<AptosCoin>(TARGET);
        let initial_p1_balance = coin::balance<AptosCoin>(PARTICIPANT1);

        // Send boo with 1000 coins, 30% to target
        CheerOrBoo::cheer_or_boo(
            &sender,
            TARGET,
            participants,
            false, // is_boo
            1000,
            30, // target_allocation
            b"test_boo_1"
        );

        // Verify balances
        let fee = 1000 * 5 / 100; // 5% fee
        let net_amount = 1000 - fee;
        let target_amount = net_amount * 30 / 100;
        let participant_amount = net_amount - target_amount;

        assert!(coin::balance<AptosCoin>(TARGET) == initial_target_balance + target_amount, 1);
        assert!(coin::balance<AptosCoin>(PARTICIPANT1) == initial_p1_balance + participant_amount, 2);

        // Clean up
        coin::destroy_burn_cap<AptosCoin>(burn_cap);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
    }

    #[test(aptos_framework = @0x1)]
    #[expected_failure(abort_code = 102)]
    fun test_insufficient_balance(aptos_framework: &signer) {
        // Create test accounts
        let sender = account::create_account_for_test(SENDER);
        let target = account::create_account_for_test(TARGET);
        let participant1 = account::create_account_for_test(PARTICIPANT1);

        // Initialize AptosCoin for testing
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);

        // Register accounts
        coin::register<AptosCoin>(&sender);
        coin::register<AptosCoin>(&target);
        coin::register<AptosCoin>(&participant1);
        
        let participants = vector::empty<address>();
        vector::push_back(&mut participants, PARTICIPANT1);

        // Try to send more than we have
        CheerOrBoo::cheer_or_boo(
            &sender,
            TARGET,
            participants,
            true,
            2000000000, // More than funded amount
            50,
            b"test_insufficient"
        );

        // Clean up
        coin::destroy_burn_cap<AptosCoin>(burn_cap);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
    }

    #[test(aptos_framework = @0x1)]
    fun test_rounding_behavior() {
        let aptos_framework = account::create_signer_for_test(@0x1);
        let sender = account::create_account_for_test(@0x123);
        let p1 = account::create_account_for_test(@0x101);
        let p2 = account::create_account_for_test(@0x102);
        let p3 = account::create_account_for_test(@0x103);
        
        // Initialize AptosCoin
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        coin::register<AptosCoin>(&sender);
        coin::register<AptosCoin>(&p1);
        coin::register<AptosCoin>(&p2);
        coin::register<AptosCoin>(&p3);
        
        // Fund sender with 100 OCTA
        let coins = coin::mint<AptosCoin>(100, &mint_cap);
        coin::deposit(@0x123, coins);

        let participants = vector::empty<address>();
        vector::push_back(&mut participants, @0x101);
        vector::push_back(&mut participants, @0x102);
        vector::push_back(&mut participants, @0x103);

        CheerOrBoo::cheer_or_boo(
            &sender,
            @0x999,
            participants,
            true,
            100,  // Total amount
            0,    // 0% to target
            b"rounding_test"
        );

        // Verify distribution (100 - 5% fee = 95)
        // 95 / 3 = 31 with 2 remainder
        assert!(coin::balance<AptosCoin>(@0x101) == 31, 0);
        assert!(coin::balance<AptosCoin>(@0x102) == 31, 1);
        assert!(coin::balance<AptosCoin>(@0x103) == 31, 2);
        
        // Remainder 2 should stay in sender's account
        assert!(coin::balance<AptosCoin>(@0x123) == 100 - 5 - 31*3, 3);

        coin::destroy_burn_cap<AptosCoin>(burn_cap);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
    }

    #[test(aptos_framework = @0x1)]
    #[expected_failure(abort_code = 104)]
    fun test_max_participants_limit() {
        let aptos_framework = account::create_signer_for_test(@0x1);
        let sender = account::create_account_for_test(@0x123);
        
        let participants = vector::empty<address>();
        let i = 0;
        while (i < CheerOrBoo::get_max_participants() + 1) {
            vector::push_back(&mut participants, @0x1);
            i = i + 1;
        };

        CheerOrBoo::cheer_or_boo(
            &sender,
            @0x999,
            participants,
            true,
            1000,
            0,
            b"max_participants_test"
        );
    }

    #[test(aptos_framework = @0x1)]
    #[expected_failure(abort_code = 103)]
    fun test_empty_participants() {
        let aptos_framework = account::create_signer_for_test(@0x1);
        let sender = account::create_account_for_test(@0x123);
        
        // Initialize AptosCoin and fund sender
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        coin::register<AptosCoin>(&sender);
        coin::deposit(@0x123, coin::mint<AptosCoin>(1000, &mint_cap));
        
        // Ensure fee address exists
        let fee_account = account::create_account_for_test(@fihub);

        CheerOrBoo::cheer_or_boo(
            &sender,
            @0x999,
            vector::empty<address>(), // Empty participants
            true,
            1000,
            0,
            b"empty_participants_test"
        );

        coin::destroy_burn_cap<AptosCoin>(burn_cap);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
    }

    #[test(aptos_framework = @0x1)]
    fun test_full_target_allocation() {
        let aptos_framework = account::create_signer_for_test(@0x1);
        let sender = account::create_account_for_test(@0x123);
        let target = account::create_account_for_test(@0x999);
        
        // Initialize AptosCoin properly
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        
        coin::register<AptosCoin>(&sender);
        coin::register<AptosCoin>(&target);
        
        // Fund sender
        let coins = coin::mint<AptosCoin>(1000, &mint_cap);
        coin::deposit(@0x123, coins);

        CheerOrBoo::cheer_or_boo(
            &sender,
            @0x999,
            vector::empty<address>(), // No participants
            true,
            1000,
            100, // 100% to target
            b"full_target_test"
        );

        // 1000 - 5% fee = 950
        assert!(coin::balance<AptosCoin>(@0x999) == 950, 0);

        // Clean up
        coin::destroy_burn_cap<AptosCoin>(burn_cap);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
    }
} 