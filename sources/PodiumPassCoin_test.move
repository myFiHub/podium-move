#[test_only]
module podium::PodiumPassCoin_test {
    use std::string::{Self, String};
    use std::signer;
    use std::vector;
    use std::debug;
    use aptos_framework::account;
    use aptos_framework::fungible_asset;
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
    const EASSET_DOES_NOT_EXIST: u64 = 4;

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789)]
    fun test_create_target_asset(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
    ) {
        // Setup test environment
        setup_test(admin, user1, user2);
        debug::print(&string::utf8(b"Test environment setup complete"));

        // Create a target asset with shorter symbol
        let target_id = string::utf8(b"T1");
        let name = string::utf8(b"Target Pass");
        let icon_uri = string::utf8(b"https://example.com/icon.png");
        let project_uri = string::utf8(b"https://example.com/project");

        debug::print(&string::utf8(b"Creating target asset with ID:"));
        debug::print(&target_id);

        PodiumPassCoin::create_target_asset_for_test(admin, target_id, name, icon_uri, project_uri);
        debug::print(&string::utf8(b"Target asset created"));

        // Generate and print the asset symbol for debugging
        let asset_symbol = generate_test_target_symbol(target_id);
        debug::print(&string::utf8(b"Generated asset symbol:"));
        debug::print(&asset_symbol);

        // Try to mint the asset
        debug::print(&string::utf8(b"Attempting to mint asset"));
        let fa = PodiumPassCoin::mint(admin, asset_symbol, 100);
        debug::print(&string::utf8(b"Asset minted successfully"));
        
        // Verify the metadata
        let metadata = fungible_asset::metadata_from_asset(&fa);
        let actual_name = fungible_asset::name(metadata);
        debug::print(&string::utf8(b"Expected name:"));
        debug::print(&name);
        debug::print(&string::utf8(b"Actual name:"));
        debug::print(&actual_name);
        assert!(actual_name == name, 1);
        
        // Clean up
        PodiumPassCoin::burn(admin, asset_symbol, fa);
        debug::print(&string::utf8(b"Test asset burned"));
    }

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789)]
    #[expected_failure(abort_code = 393220)] // EASSET_DOES_NOT_EXIST
    fun test_unauthorized_mint(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
    ) {
        setup_test(admin, user1, user2);
        debug::print(&string::utf8(b"Test environment setup complete for unauthorized mint test"));

        let asset_symbol = string::utf8(b"T_NONEXISTENT");
        debug::print(&string::utf8(b"Attempting unauthorized mint with symbol:"));
        debug::print(&asset_symbol);

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
        setup_test(admin, user1, user2);
        debug::print(&string::utf8(b"Test environment setup complete for mint and transfer test"));

        let target_id = string::utf8(b"T2");
        debug::print(&string::utf8(b"Creating test asset with ID:"));
        debug::print(&target_id);

        let asset_symbol = generate_test_target_symbol(target_id);
        debug::print(&string::utf8(b"Generated asset symbol:"));
        debug::print(&asset_symbol);

        create_test_asset(admin, target_id);
        debug::print(&string::utf8(b"Test asset created"));
        
        let amount = 100;
        debug::print(&string::utf8(b"Attempting to mint asset"));
        let fa = PodiumPassCoin::mint(admin, asset_symbol, amount);
        debug::print(&string::utf8(b"Asset minted successfully"));
        
        // Transfer to user1
        let user1_addr = signer::address_of(user1);
        debug::print(&string::utf8(b"Transferring to user1 at address:"));
        debug::print(&user1_addr);
        primary_fungible_store::deposit(user1_addr, fa);

        // Verify balance
        let balance = PodiumPassCoin::balance(user1_addr, asset_symbol);
        debug::print(&string::utf8(b"User1 balance:"));
        debug::print(&balance);
        assert!(balance == amount, 1);

        // Test transfer between users
        let user2_addr = signer::address_of(user2);
        debug::print(&string::utf8(b"Transferring to user2 at address:"));
        debug::print(&user2_addr);
        PodiumPassCoin::transfer(user1, asset_symbol, user2_addr, 50);

        let user2_balance = PodiumPassCoin::balance(user2_addr, asset_symbol);
        let user1_balance = PodiumPassCoin::balance(user1_addr, asset_symbol);
        debug::print(&string::utf8(b"Final balances - User1:"));
        debug::print(&user1_balance);
        debug::print(&string::utf8(b"User2:"));
        debug::print(&user2_balance);
        assert!(user2_balance == 50, 2);
        assert!(user1_balance == 50, 3);
    }

    // Helper functions
    fun setup_test(admin: &signer, user1: &signer, user2: &signer) {
        debug::print(&string::utf8(b"Creating test accounts"));
        account::create_account_for_test(@podium);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        
        debug::print(&string::utf8(b"Initializing PodiumPassCoin module"));
        PodiumPassCoin::init_module_for_test(&account::create_signer_for_test(@podium));
        
        debug::print(&string::utf8(b"Initializing PodiumPass module"));
        PodiumPass::initialize(&account::create_signer_for_test(@podium));
    }

    fun create_test_asset(admin: &signer, target_id: String) {
        debug::print(&string::utf8(b"Creating test asset with target_id:"));
        debug::print(&target_id);
        PodiumPassCoin::create_target_asset_for_test(
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
        debug::print(&string::utf8(b"Generated symbol:"));
        debug::print(&result);
        result
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium)]
    public fun test_asset_creation(
        aptos_framework: &signer,
        podium_signer: &signer,
    ) {
        // Initialize module
        PodiumPassCoin::init_module_for_test(podium_signer);
        
        // Create test asset
        let asset_symbol = string::utf8(b"TEST");
        PodiumPassCoin::create_target_asset_for_test(
            podium_signer,
            asset_symbol,
            string::utf8(b"Test Pass"),
            string::utf8(b"https://example.com/icon.png"),
            string::utf8(b"https://example.com/project"),
        );
        
        // Verify asset exists
        assert!(PodiumPassCoin::balance(signer::address_of(podium_signer), asset_symbol) >= 0, 0);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium)]
    #[expected_failure(abort_code = 393220)] // EASSET_DOES_NOT_EXIST
    public fun test_nonexistent_asset(
        aptos_framework: &signer,
        podium_signer: &signer,
    ) {
        // Initialize module
        PodiumPassCoin::init_module_for_test(podium_signer);
        
        // Try to get balance of nonexistent asset
        let asset_symbol = string::utf8(b"NONEXISTENT");
        PodiumPassCoin::balance(signer::address_of(podium_signer), asset_symbol);
    }
} 