#[test_only]
module 0xYourAddress::PodiumPassCoin_test {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use 0xYourAddress::PodiumPassCoin;

    // Test constants
    const ADMIN: address = @0x123;
    const USER1: address = @0x456;
    const USER2: address = @0x789;

    fun setup(): (signer, signer, signer) {
        let admin = account::create_account_for_test(ADMIN);
        let user1 = account::create_account_for_test(USER1);
        let user2 = account::create_account_for_test(USER2);

        // Initialize PassCoin
        PodiumPassCoin::initialize_target<ADMIN>(&admin, string::utf8(b"Test Pass"));

        (admin, user1, user2)
    }

    #[test]
    fun test_mint_and_burn() {
        let (admin, user1, _) = setup();
        
        // Mint pass
        PodiumPassCoin::mint_pass<ADMIN>(&admin, USER1, 1, 1);
        
        // Verify balance
        let balance = PodiumPassCoin::get_pass_balance<ADMIN>(USER1);
        assert!(balance.amount == 1, 1);
        assert!(balance.tier == 1, 2);

        // Burn pass
        PodiumPassCoin::burn_pass<ADMIN>(&user1, 1);
        
        // Verify zero balance
        let balance = PodiumPassCoin::get_pass_balance<ADMIN>(USER1);
        assert!(balance.amount == 0, 3);
    }
} 