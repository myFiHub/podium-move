#[test_only]
module podium::PodiumOutpost_test {
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use podium::PodiumOutpost;

    // Test addresses
    const ADMIN: address = @podium;
    const FIHUB: address = @fihub;
    const USER1: address = @0x456;

    // Test error codes
    const ENOT_AUTHORIZED: u64 = 1;
    const EINVALID_PRICE: u64 = 2;

    #[test(aptos_framework = @0x1, admin = @podium, fihub = @fihub, user1 = @0x456)]
    fun test_create_outpost(
        aptos_framework: &signer,
        admin: &signer,
        fihub: &signer,
        user1: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, admin, fihub, user1);

        // Set default price
        PodiumOutpost::set_default_price(admin, 1000);

        // Create outpost
        let outpost_name = string::utf8(b"test_outpost");
        let description = string::utf8(b"Test Outpost");
        let metadata_uri = string::utf8(b"https://example.com/metadata");

        // Fund user account
        coin::register<AptosCoin>(user1);
        coin::transfer<AptosCoin>(admin, signer::address_of(user1), 2000);

        PodiumOutpost::create_outpost(user1, outpost_name, description, metadata_uri);

        // Verify ownership
        assert!(PodiumOutpost::is_outpost_owner(signer::address_of(user1), outpost_name), 0);
        
        // Verify payment
        assert!(coin::balance<AptosCoin>(FIHUB) == 1000, 1);
    }

    #[test(aptos_framework = @0x1, admin = @podium, fihub = @fihub, user1 = @0x456)]
    fun test_custom_pricing(
        aptos_framework: &signer,
        admin: &signer,
        fihub: &signer,
        user1: &signer,
    ) {
        setup_test(aptos_framework, admin, fihub, user1);

        // Set default and custom prices in $MOVE
        let outpost_name = string::utf8(b"premium_outpost");
        PodiumOutpost::set_default_price(admin, 1000);
        PodiumOutpost::set_custom_price(admin, outpost_name, 2000);

        // Fund user account
        coin::register<AptosCoin>(user1);
        coin::transfer<AptosCoin>(admin, signer::address_of(user1), 3000);

        // Create outpost with custom price
        let description = string::utf8(b"Premium Outpost");
        let metadata_uri = string::utf8(b"https://example.com/premium");
        
        PodiumOutpost::create_outpost(user1, outpost_name, description, metadata_uri);

        // Verify payment amount
        assert!(coin::balance<AptosCoin>(FIHUB) == 2000, 0);
    }

    #[test(aptos_framework = @0x1, admin = @podium, fihub = @fihub, user1 = @0x456)]
    #[expected_failure(abort_code = ENOT_AUTHORIZED)]
    fun test_unauthorized_price_setting(
        aptos_framework: &signer,
        admin: &signer,
        fihub: &signer,
        user1: &signer,
    ) {
        setup_test(aptos_framework, admin, fihub, user1);
        
        // Try to set price with unauthorized user
        PodiumOutpost::set_default_price(user1, 1000);
    }

    // Helper functions
    fun setup_test(aptos_framework: &signer, admin: &signer, fihub: &signer, user1: &signer) {
        // Create test accounts
        account::create_account_for_test(@podium);
        account::create_account_for_test(@fihub);
        account::create_account_for_test(signer::address_of(user1));

        // Setup coin for testing
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(fihub);
        coin::deposit(signer::address_of(admin), coin::mint<AptosCoin>(10000, &mint_cap));
        
        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
} 