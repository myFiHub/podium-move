#[test_only]
module 0xYourAddress::PodiumIntegration_test {
    use std::string;
    use std::vector;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use 0xYourAddress::PodiumPass;
    use 0xYourAddress::PodiumPassCoin;
    use 0xYourAddress::PodiumOutpost;

    // Test constants
    const ADMIN: address = @0x123;
    const OUTPOST_OWNER: address = @0x456;
    const USER1: address = @0x789;
    const PROTOCOL_FEE: u64 = 4;
    const SUBJECT_FEE: u64 = 8;
    const REFERRAL_FEE: u64 = 2;

    fun setup(): (signer, signer, signer) {
        // Create test accounts
        let admin = account::create_account_for_test(ADMIN);
        let owner = account::create_account_for_test(OUTPOST_OWNER);
        let user1 = account::create_account_for_test(USER1);

        // Setup timestamp
        timestamp::set_time_has_started_for_testing(&admin);

        // Initialize AptosCoin for testing
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&admin);

        // Fund accounts
        coin::register<AptosCoin>(&owner);
        coin::register<AptosCoin>(&user1);
        let coins = coin::mint(1000000000, &mint_cap);
        coin::deposit(OUTPOST_OWNER, coins);
        let coins = coin::mint(1000000000, &mint_cap);
        coin::deposit(USER1, coins);

        // Initialize PodiumPass system
        PodiumPass::initialize(
            &admin,
            ADMIN,
            PROTOCOL_FEE,
            SUBJECT_FEE,
            REFERRAL_FEE
        );

        // Initialize PodiumOutpost
        PodiumOutpost::initialize(&admin, 1000000);

        (admin, owner, user1)
    }

    #[test]
    fun test_outpost_subscription_flow() {
        let (admin, owner, user1) = setup();

        // 1. Create an outpost
        PodiumOutpost::create_outpost(
            &owner,
            string::utf8(b"Test Outpost"),
            string::utf8(b"Description"),
            string::utf8(b"uri"),
            1000,
            string::utf8(b"Category"),
            vector::empty<String>(),
            vector::empty<String>()
        );

        // 2. User subscribes to outpost
        PodiumPass::create_subscription(
            &user1,
            OUTPOST_OWNER,
            30 * 24 * 60 * 60, // 30 days
            1 // tier
        );

        // 3. Verify subscription through both contracts
        let has_access = PodiumOutpost::has_access(USER1, OUTPOST_OWNER);
        assert!(has_access == true, 1);

        let status = PodiumPass::get_account_status<OUTPOST_OWNER>(USER1);
        assert!(status.has_subscription == true, 2);
    }

    #[test]
    fun test_lifetime_pass_with_outpost() {
        let (admin, owner, user1) = setup();

        // 1. Create an outpost
        PodiumOutpost::create_outpost(
            &owner,
            string::utf8(b"Test Outpost"),
            string::utf8(b"Description"),
            string::utf8(b"uri"),
            1000,
            string::utf8(b"Category"),
            vector::empty<String>(),
            vector::empty<String>()
        );

        // 2. Mint lifetime pass for user
        PodiumPass::mint_lifetime_access<OUTPOST_OWNER>(
            &admin,
            USER1,
            1, // amount
            1  // tier
        );

        // 3. Verify through both systems
        let has_access = PodiumOutpost::has_access(USER1, OUTPOST_OWNER);
        assert!(has_access == true, 1);

        let balance = PodiumPassCoin::get_pass_balance<OUTPOST_OWNER>(USER1);
        assert!(balance.amount == 1, 2);
        assert!(balance.tier == 1, 3);
    }

    #[test]
    fun test_outpost_fee_distribution() {
        let (admin, owner, user1) = setup();

        // 1. Create an outpost
        PodiumOutpost::create_outpost(
            &owner,
            string::utf8(b"Test Outpost"),
            string::utf8(b"Description"),
            string::utf8(b"uri"),
            1000,
            string::utf8(b"Category"),
            vector::empty<String>(),
            vector::empty<String>()
        );

        // Record initial balances
        let owner_initial = coin::balance<AptosCoin>(OUTPOST_OWNER);
        let admin_initial = coin::balance<AptosCoin>(ADMIN);

        // 2. User subscribes to outpost
        PodiumPass::create_subscription(
            &user1,
            OUTPOST_OWNER,
            30 * 24 * 60 * 60,
            1
        );

        // 3. Verify fee distribution
        let owner_final = coin::balance<AptosCoin>(OUTPOST_OWNER);
        let admin_final = coin::balance<AptosCoin>(ADMIN);

        assert!(owner_final > owner_initial, 1); // Owner received their fee
        assert!(admin_final > admin_initial, 2); // Admin received protocol fee
    }

    #[test]
    #[expected_failure(abort_code = 6)]
    fun test_pause_affects_all_systems() {
        let (admin, owner, user1) = setup();

        // 1. Create an outpost
        PodiumOutpost::create_outpost(
            &owner,
            string::utf8(b"Test Outpost"),
            string::utf8(b"Description"),
            string::utf8(b"uri"),
            1000,
            string::utf8(b"Category"),
            vector::empty<String>(),
            vector::empty<String>()
        );

        // 2. Pause the system
        PodiumPass::pause(&admin);

        // 3. Try to create subscription - should fail
        PodiumPass::create_subscription(
            &user1,
            OUTPOST_OWNER,
            30 * 24 * 60 * 60,
            1
        );
    }
} 