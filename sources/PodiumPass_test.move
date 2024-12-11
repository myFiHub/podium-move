#[test_only]
module 0xYourAddress::PodiumPass_test {
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use 0xYourAddress::PodiumPass;

    // Test constants
    const ADMIN: address = @0x123;
    const USER1: address = @0x456;
    const USER2: address = @0x789;
    const PROTOCOL_FEE: u64 = 4;
    const SUBJECT_FEE: u64 = 8;
    const REFERRAL_FEE: u64 = 2;

    // Test setup helper
    fun setup(): (signer, signer, signer) {
        // Create test accounts
        let admin = account::create_account_for_test(ADMIN);
        let user1 = account::create_account_for_test(USER1);
        let user2 = account::create_account_for_test(USER2);

        // Setup timestamp for testing
        timestamp::set_time_has_started_for_testing(&admin);

        // Initialize PodiumPass
        PodiumPass::initialize(
            &admin, 
            ADMIN, 
            PROTOCOL_FEE,
            SUBJECT_FEE,
            REFERRAL_FEE
        );

        (admin, user1, user2)
    }

    #[test]
    fun test_initialization() {
        let (admin, _, _) = setup();
        
        // Verify initialization
        assert!(PodiumPass::verify_access(ADMIN, ADMIN, 1) == false, 0);
    }

    #[test]
    fun test_mint_lifetime_access() {
        let (admin, user1, _) = setup();
        
        // Mint pass to user1
        PodiumPass::mint_lifetime_access<ADMIN>(&admin, USER1, 1, 1);
        
        // Verify access
        assert!(PodiumPass::verify_access(USER1, ADMIN, 1) == true, 1);
    }

    #[test]
    fun test_create_subscription() {
        let (admin, user1, _) = setup();
        
        // Create subscription
        PodiumPass::create_subscription(&user1, ADMIN, 30 * 24 * 60 * 60, 1);
        
        // Verify subscription
        let status = PodiumPass::get_account_status<ADMIN>(USER1);
        assert!(status.has_subscription == true, 2);
    }

    #[test]
    #[expected_failure(abort_code = 6)]
    fun test_pause_functionality() {
        let (admin, user1, _) = setup();
        
        // Pause system
        PodiumPass::pause(&admin);
        
        // Try to mint - should fail
        PodiumPass::mint_lifetime_access<ADMIN>(&admin, USER1, 1, 1);
    }
} 