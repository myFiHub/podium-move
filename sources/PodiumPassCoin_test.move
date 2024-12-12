#[test_only]
module podium::PodiumPassCoin_test {
    use std::string::{Self, String};
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self};
    use aptos_framework::primary_fungible_store;
    use podium::PodiumPassCoin;
    use podium::PodiumPass;

    // Test addresses
    const ADMIN: address = @0x123;
    const USER1: address = @0x456;
    const USER2: address = @0x789;

    // Test error codes
    const ENOT_PODIUM_PASS: u64 = 1;
    const EZERO_AMOUNT: u64 = 2;

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789)]
    fun test_create_target_asset(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
    ) {
        // Setup test environment
        setup_test(aptos_framework, admin, user1, user2);

        // Create a target asset
        let target_id = string::utf8(b"target1");
        let name = string::utf8(b"Target Pass");
        let icon_uri = string::utf8(b"https://example.com/icon.png");
        let project_uri = string::utf8(b"https://example.com/project");

        PodiumPassCoin::create_target_asset(admin, target_id, name, icon_uri, project_uri);

        // Verify asset was created by checking metadata exists
        let asset_symbol = generate_test_target_symbol(target_id);
        let metadata = PodiumPassCoin::get_metadata(asset_symbol);
        assert!(fungible_asset::name<fungible_asset::Metadata>(metadata) == name, 0);
    }

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789)]
    #[expected_failure(abort_code = ENOT_PODIUM_PASS)]
    fun test_unauthorized_mint(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2);

        // Try to mint with unauthorized user
        let asset_symbol = string::utf8(b"TEST_ASSET");
        let fa = PodiumPassCoin::mint(user1, asset_symbol, 100);
        primary_fungible_store::deposit(signer::address_of(user1), fa);
    }

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789)]
    fun test_mint_and_transfer(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2);

        // Create and mint asset
        let target_id = string::utf8(b"target1");
        let asset_symbol = generate_test_target_symbol(target_id);
        create_test_asset(admin, target_id);
        
        let amount = 100;
        let fa = PodiumPassCoin::mint(admin, asset_symbol, amount);
        
        // Transfer to user1
        let user1_addr = signer::address_of(user1);
        primary_fungible_store::deposit(user1_addr, fa);

        // Verify balance
        assert!(PodiumPassCoin::balance(user1_addr, asset_symbol) == amount, 0);

        // Test transfer between users
        PodiumPassCoin::transfer(user1, asset_symbol, signer::address_of(user2), 50);
        assert!(PodiumPassCoin::balance(signer::address_of(user2), asset_symbol) == 50, 1);
        assert!(PodiumPassCoin::balance(user1_addr, asset_symbol) == 50, 2);
    }

    // Helper functions
    fun setup_test(_aptos_framework: &signer, admin: &signer, user1: &signer, user2: &signer) {
        // Create test accounts
        account::create_account_for_test(@podium);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        
        // Initialize PodiumPass (required for authorization)
        PodiumPass::init_module_for_test(admin);
    }

    fun create_test_asset(admin: &signer, target_id: String) {
        PodiumPassCoin::create_target_asset(
            admin,
            target_id,
            string::utf8(b"Test Pass"),
            string::utf8(b"https://example.com/icon.png"),
            string::utf8(b"https://example.com/project"),
        );
    }

    fun generate_test_target_symbol(target_id: String): String {
        let prefix = string::utf8(b"TARGET_");
        let result = string::utf8(vector::empty());
        string::append(&mut result, prefix);
        string::append(&mut result, target_id);
        result
    }
} 