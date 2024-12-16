#[test_only]
module podium::PodiumOutpost_test {
    use std::string;
    use std::signer;
    use std::debug;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::object;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_token_objects::token;
    use podium::PodiumOutpost;

    #[test(aptos_framework = @0x1, podium_signer = @podium, buyer = @0x456)]
    public fun test_outpost_creation(
        aptos_framework: &signer,
        podium_signer: &signer,
        buyer: &signer,
    ) {
        // Setup
        account::create_account_for_test(@podium);
        account::create_account_for_test(signer::address_of(buyer));
        
        // Initialize coin and fund buyer
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        coin::register<AptosCoin>(buyer);
        coin::deposit(signer::address_of(buyer), coin::mint<AptosCoin>(10000, &mint_cap));

        // Initialize collection
        PodiumOutpost::init_collection(podium_signer);

        // Calculate expected token address
        let name = string::utf8(b"Test Outpost");
        let seed = token::create_token_seed(
            &PodiumOutpost::get_collection_name(),
            &name
        );
        let expected_addr = object::create_object_address(&signer::address_of(buyer), seed);
        debug::print(&string::utf8(b"Expected token address:"));
        debug::print(&expected_addr);

        // Create outpost
        let outpost = PodiumOutpost::create_outpost_internal(
            buyer,
            name,
            string::utf8(b"Test Description"),
            string::utf8(b"https://test.uri"),
        );

        // Verify token is at derived address
        let actual_addr = object::object_address(&outpost);
        debug::print(&string::utf8(b"Actual token address:"));
        debug::print(&actual_addr);
        assert!(actual_addr == expected_addr, 0);

        // Verify outpost data
        assert!(PodiumOutpost::get_price(outpost) == PodiumOutpost::get_outpost_purchase_price(), 1);
        assert!(PodiumOutpost::get_fee_share(outpost) == PodiumOutpost::get_outpost_fee_share(), 2);
        assert!(!PodiumOutpost::is_paused(outpost), 3);

        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, podium_signer = @podium, buyer = @0x456)]
    #[expected_failure(abort_code = 65537)] // ENOT_ADMIN
    public fun test_unauthorized_fee_update(
        aptos_framework: &signer,
        podium_signer: &signer,
        buyer: &signer,
    ) {
        // Setup and create outpost
        test_outpost_creation(aptos_framework, podium_signer, buyer);
        
        // Try to update fee share as non-admin (should fail)
        let outpost = PodiumOutpost::create_outpost_internal(
            buyer,
            string::utf8(b"Test Outpost"),
            string::utf8(b"Test Description"),
            string::utf8(b"https://test.uri"),
        );
        PodiumOutpost::update_fee_share(buyer, outpost, 1000);
    }
}
