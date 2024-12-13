#[test_only]
module podium::PodiumOutpost_test {
    use std::string;
    use std::signer;
    use std::vector;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use aptos_framework::event;
    use podium::PodiumOutpost::{Self, OutpostData};

    // Test constants
    const OUTPOST_NAME: vector<u8> = b"Test Outpost";
    const OUTPOST_DESCRIPTION: vector<u8> = b"Test Description";
    const OUTPOST_URI: vector<u8> = b"https://test.uri";
    const INITIAL_PRICE: u64 = 1000;
    const INITIAL_FEE_SHARE: u64 = 500; // 5%
    const UPDATED_PRICE: u64 = 2000;
    const UPDATED_FEE_SHARE: u64 = 1000; // 10%

    // Error constants for testing
    const INVALID_PRICE: u64 = 0;
    const INVALID_FEE_SHARE: u64 = 15000; // 150%

    // Test helper function to create test accounts
    fun create_test_account(): signer {
        account::create_account_for_test(@0x123)
    }

    // Test helper function to create unauthorized account
    fun create_unauthorized_account(): signer {
        account::create_account_for_test(@0x789)
    }

    // Test helper to create an outpost
    fun create_test_outpost(admin: &signer, creator: &signer, name: string::String): Object<OutpostData> {
        // Initialize collection if needed
        PodiumOutpost::init_collection(admin);
        
        PodiumOutpost::create_outpost_internal(
            creator,
            name,
            string::utf8(OUTPOST_DESCRIPTION),
            string::utf8(OUTPOST_URI),
            INITIAL_PRICE,
            INITIAL_FEE_SHARE,
        )
    }

    #[test(admin = @admin)]
    /// Test successful outpost creation
    fun test_create_outpost_success(admin: &signer) {
        // Create test account and outpost
        let creator = create_test_account();
        let outpost = create_test_outpost(admin, &creator, string::utf8(OUTPOST_NAME));

        // Verify outpost data
        assert!(PodiumOutpost::get_price(outpost) == INITIAL_PRICE, 5002);
        assert!(PodiumOutpost::get_fee_share(outpost) == INITIAL_FEE_SHARE, 5003);
        assert!(!PodiumOutpost::is_paused(outpost), 5004);
        assert!(object::is_owner(outpost, signer::address_of(&creator)), 5005);
    }

    #[test(admin = @admin)]
    #[expected_failure(abort_code = 0x10005)] // EINVALID_PRICE
    fun test_create_outpost_invalid_price(admin: &signer) {
        let creator = create_test_account();
        
        PodiumOutpost::init_collection(admin);
        PodiumOutpost::create_outpost(
            &creator,
            string::utf8(OUTPOST_NAME),
            string::utf8(OUTPOST_DESCRIPTION),
            string::utf8(OUTPOST_URI),
            INVALID_PRICE,
            INITIAL_FEE_SHARE,
        );
    }

    #[test(admin = @admin)]
    #[expected_failure(abort_code = 0x10006)] // EINVALID_FEE
    fun test_create_outpost_invalid_fee(admin: &signer) {
        let creator = create_test_account();
        
        PodiumOutpost::init_collection(admin);
        PodiumOutpost::create_outpost(
            &creator,
            string::utf8(OUTPOST_NAME),
            string::utf8(OUTPOST_DESCRIPTION),
            string::utf8(OUTPOST_URI),
            INITIAL_PRICE,
            INVALID_FEE_SHARE,
        );
    }

    #[test(admin = @admin)]
    fun test_update_price_success(admin: &signer) {
        let creator = create_test_account();
        let outpost = create_test_outpost(admin, &creator, string::utf8(OUTPOST_NAME));

        // Update price
        PodiumOutpost::update_price(&creator, outpost, UPDATED_PRICE);

        // Verify price was updated
        assert!(PodiumOutpost::get_price(outpost) == UPDATED_PRICE, 5006);
        
        // Verify event was emitted
        let events = event::emitted_events<PodiumOutpost::PriceUpdateEvent>();
        assert!(vector::length(&events) == 1, 5007);
    }

    #[test(admin = @admin)]
    #[expected_failure(abort_code = 0x10004)] // ENOT_OWNER
    fun test_update_price_unauthorized(admin: &signer) {
        // Create test account and outpost
        let creator = create_test_account();
        let unauthorized = create_unauthorized_account();
        
        // Create outpost with creator account
        let outpost = create_test_outpost(admin, &creator, string::utf8(OUTPOST_NAME));

        // Try to update price with unauthorized account
        PodiumOutpost::update_price(&unauthorized, outpost, UPDATED_PRICE);
    }

    #[test(admin = @admin)]
    fun test_update_fee_share_success(admin: &signer) {
        let creator = create_test_account();
        let outpost = create_test_outpost(admin, &creator, string::utf8(OUTPOST_NAME));

        // Update fee share
        PodiumOutpost::update_fee_share(&creator, outpost, UPDATED_FEE_SHARE);

        // Verify fee share was updated
        assert!(PodiumOutpost::get_fee_share(outpost) == UPDATED_FEE_SHARE, 5008);
        
        // Verify event was emitted
        let events = event::emitted_events<PodiumOutpost::FeeUpdateEvent>();
        assert!(vector::length(&events) == 1, 5009);
    }

    #[test(admin = @admin)]
    fun test_emergency_pause(admin: &signer) {
        let creator = create_test_account();
        let outpost = create_test_outpost(admin, &creator, string::utf8(OUTPOST_NAME));

        // Toggle emergency pause
        PodiumOutpost::toggle_emergency_pause(&creator, outpost);
        assert!(PodiumOutpost::is_paused(outpost), 5010);
        assert!(!PodiumOutpost::verify_access(outpost), 5011);

        // Verify event was emitted
        let events = event::emitted_events<PodiumOutpost::EmergencyPauseEvent>();
        assert!(vector::length(&events) == 1, 5012);

        // Test that price updates fail when paused
        PodiumOutpost::toggle_emergency_pause(&creator, outpost);
        assert!(!PodiumOutpost::is_paused(outpost), 5013);
        assert!(PodiumOutpost::verify_access(outpost), 5014);
    }

    #[test(admin = @admin)]
    #[expected_failure(abort_code = 0x10007)] // EEMERGENCY_PAUSE
    fun test_update_during_emergency_pause(admin: &signer) {
        let creator = create_test_account();
        let outpost = create_test_outpost(admin, &creator, string::utf8(OUTPOST_NAME));

        // Enable emergency pause
        PodiumOutpost::toggle_emergency_pause(&creator, outpost);
        
        // Try to update price while paused
        PodiumOutpost::update_price(&creator, outpost, UPDATED_PRICE);
    }

    #[test(admin = @admin)]
    #[expected_failure(abort_code = 0x10001)] // ENOT_ADMIN
    fun test_collection_creation_unauthorized(admin: &signer) {
        // Try to initialize collection with non-admin account
        let creator = create_unauthorized_account();
        
        // Collection should not exist yet, and creator is not admin
        PodiumOutpost::init_collection(&creator);
    }
}
