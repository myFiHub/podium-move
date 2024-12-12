#[test_only]
module podium::PodiumIntegration_test {
    use std::string;
    use std::signer;
    use std::option;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use podium::PodiumPass;
    use podium::PodiumPassCoin;
    use podium::PodiumOutpost;

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789, fihub = @fihub)]
    fun test_outpost_and_pass_integration(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        fihub: &signer,
    ) {
        // Setup
        setup_test(aptos_framework, admin, user1, user2, fihub);

        // Create outpost
        let outpost_name = string::utf8(b"test_outpost");
        let description = string::utf8(b"Test Outpost");
        let metadata_uri = string::utf8(b"https://example.com/metadata");

        // Fund user accounts
        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);
        coin::transfer<AptosCoin>(admin, signer::address_of(user1), 10000);
        coin::transfer<AptosCoin>(admin, signer::address_of(user2), 10000);

        // Create outpost with user1
        PodiumOutpost::set_default_price(admin, 1000);
        PodiumOutpost::create_outpost(user1, outpost_name, description, metadata_uri);

        // Verify outpost ownership
        assert!(PodiumOutpost::is_outpost_owner(signer::address_of(user1), outpost_name), 0);

        // Create subscription tier for outpost
        let user1_addr = signer::address_of(user1);
        PodiumPass::create_subscription_tier(
            user1,
            user1_addr,
            string::utf8(b"vip"),
            500,
            1500,
            15000,
        );

        // User2 subscribes to outpost
        PodiumPass::subscribe(
            user2,
            user1_addr,
            string::utf8(b"vip"),
            PodiumPass::DURATION_MONTH,
            option::none()
        );

        // Verify subscription access
        let (has_access, tier) = PodiumPass::verify_access(signer::address_of(user2), user1_addr);
        assert!(has_access, 1);
        assert!(option::extract(&mut tier) == string::utf8(b"vip"), 2);

        // User2 buys lifetime pass
        PodiumPass::buy_pass(user2, user1_addr, 1, option::none());

        // Verify lifetime pass access
        let (has_access, tier) = PodiumPass::verify_access(signer::address_of(user2), user1_addr);
        assert!(has_access, 3);
        assert!(option::is_none(&tier), 4); // Lifetime pass has no tier
    }

    #[test(aptos_framework = @0x1, admin = @podium, user1 = @0x456, user2 = @0x789, fihub = @fihub)]
    fun test_fee_distribution(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        fihub: &signer,
    ) {
        setup_test(aptos_framework, admin, user1, user2, fihub);

        // Setup accounts
        let user1_addr = signer::address_of(user1);
        let treasury_addr = signer::address_of(admin);
        
        // Fund buyer
        coin::register<AptosCoin>(user2);
        coin::transfer<AptosCoin>(admin, signer::address_of(user2), 10000);

        // Record initial balances
        let initial_treasury = coin::balance<AptosCoin>(treasury_addr);
        let initial_subject = coin::balance<AptosCoin>(user1_addr);

        // Buy pass with referral
        PodiumPass::buy_pass(user2, user1_addr, 1, option::some(fihub));

        // Verify fee distribution
        let final_treasury = coin::balance<AptosCoin>(treasury_addr);
        let final_subject = coin::balance<AptosCoin>(user1_addr);
        let final_referral = coin::balance<AptosCoin>(signer::address_of(fihub));

        assert!(final_treasury > initial_treasury, 0); // Protocol fee received
        assert!(final_subject > initial_subject, 1);   // Subject fee received
        assert!(final_referral > 0, 2);               // Referral fee received
    }

    fun setup_test(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        fihub: &signer,
    ) {
        // Create test accounts
        account::create_account_for_test(@podium);
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(@fihub);

        // Setup coin for testing
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(fihub);
        coin::register<AptosCoin>(user1);
        coin::deposit(signer::address_of(admin), coin::mint<AptosCoin>(100000, &mint_cap));

        // Initialize all modules
        PodiumPass::init_module(admin);
        PodiumPassCoin::init_module(admin);
        PodiumOutpost::init_module(admin);

        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
} 