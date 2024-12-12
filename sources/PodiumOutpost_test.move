#[test_only]
module podium::PodiumOutpost_test {
    use std::string;
    use std::vector;
    use std::option::{Self, Option};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability};
    use aptos_framework::aptos_coin::AptosCoin;

    use podium::PodiumOutpost;

    // Test addresses
    const ADMIN: address = @admin;
    const TREASURY: address = @treasury;
    const USER1: address = @0x456;
    const USER2: address = @0x789;

    struct TEST_TARGET {}

    fun setup(framework: &signer, admin: &signer) {
        timestamp::set_time_has_started_for_testing(framework);
        
        // Create test accounts
        account::create_account_for_test(@admin);
        account::create_account_for_test(@treasury);
        account::create_account_for_test(@0x456); // Test user
        
        // Initialize modules
        PodiumOutpost::initialize(admin);
    }

    fun setup_test_coins(admin: &signer, account: address, amount: u64) {
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
        if (!coin::is_account_registered<AptosCoin>(account)) {
            coin::register<AptosCoin>(&account::create_signer_for_test(account));
        };
        coin::deposit(account, coins);

        // Clean up capabilities
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_outpost_creation(framework: &signer, admin: &signer) {
        setup(framework, admin);
        
        // Setup test coins for admin
        setup_test_coins(admin, @admin, 1000000);
        
        // Create outpost
        let owner = account::create_signer_for_test(@0x456);
        setup_test_coins(admin, @0x456, 1000000);
        
        // Create outpost with proper Option parameters
        PodiumOutpost::create_outpost(
            &owner,
            string::utf8(b"Test Outpost"),
            option::some(string::utf8(b"Description")),
            option::some(string::utf8(b"Category")),
            string::utf8(b"uri"),
            1000000,
            option::some(vector[string::utf8(b"tag1")]),
            option::some(vector[string::utf8(b"link1")]),
            option::none()
        );

        // Verify outpost creation
        let metadata = PodiumOutpost::get_outpost_metadata(@0x456);
        assert!(option::is_some(&metadata), 1);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_purchase_outpost(framework: &signer, admin: &signer) {
        setup(framework, admin);
        setup_test_coins(admin, USER2, 10000000);

        // Create user signers
        let user1_signer = account::create_signer_for_test(USER1);
        let user2_signer = account::create_signer_for_test(USER2);

        // Create outpost
        PodiumOutpost::create_outpost(
            &user1_signer,
            string::utf8(b"Test Outpost"),
            option::some(string::utf8(b"Description")),
            option::some(string::utf8(b"Category")),
            string::utf8(b"uri"),
            1000000,
            option::some(vector[string::utf8(b"tag1")]),
            option::some(vector[string::utf8(b"link1")]),
            option::none()
        );

        // Purchase outpost
        let payment = coin::withdraw<AptosCoin>(&user2_signer, 1000000);
        PodiumOutpost::purchase_outpost(
            &user2_signer,
            USER1,
            payment
        );

        // Verify ownership transfer
        assert!(PodiumOutpost::is_outpost_owner(USER2, USER2), 1);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_set_tier_config(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Create outpost
        PodiumOutpost::create_outpost(
            &user1_signer,
            string::utf8(b"Test Outpost"),
            option::some(string::utf8(b"Description")),
            option::some(string::utf8(b"Category")),
            string::utf8(b"uri"),
            1000000,
            option::some(vector[string::utf8(b"tag1")]),
            option::some(vector[string::utf8(b"link1")]),
            option::none()
        );

        // Set tier configuration
        PodiumOutpost::set_tier_config(
            &user1_signer,
            vector[1000000, 2000000, 3000000],
            30,
            365,
            vector[string::utf8(b"Basic"), string::utf8(b"Premium"), string::utf8(b"Exclusive")]
        );

        // Verify tier configuration
        let config = PodiumOutpost::get_tier_config(USER1);
        assert!(option::is_some(&config), 1);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_fee_collection(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Create outpost
        PodiumOutpost::create_outpost(
            &user1_signer,
            string::utf8(b"Test Outpost"),
            option::some(string::utf8(b"Description")),
            option::some(string::utf8(b"Category")),
            string::utf8(b"uri"),
            1000000,
            option::some(vector[string::utf8(b"tag1")]),
            option::some(vector[string::utf8(b"link1")]),
            option::none()
        );

        // Collect fees
        PodiumOutpost::collect_fees<AptosCoin>(1000000, USER1);

        // Verify fee collection
        let (total_fees, _, _) = PodiumOutpost::get_fee_info(USER1);
        assert!(total_fees > 0, 1);
    }

    #[test(framework = @0x1, admin = @admin)]
    public fun test_update_outpost_price(framework: &signer, admin: &signer) {
        setup(framework, admin);

        // Create user signer
        let user1_signer = account::create_signer_for_test(USER1);

        // Create outpost
        PodiumOutpost::create_outpost(
            &user1_signer,
            string::utf8(b"Test Outpost"),
            option::some(string::utf8(b"Description")),
            option::some(string::utf8(b"Category")),
            string::utf8(b"uri"),
            1000000,
            option::some(vector[string::utf8(b"tag1")]),
            option::some(vector[string::utf8(b"link1")]),
            option::none()
        );

        // Update price
        PodiumOutpost::update_outpost_price(&user1_signer, 2000000);

        // Verify price update
        let price = PodiumOutpost::get_outpost_price(USER1);
        assert!(price == 2000000, 1);
    }
} 