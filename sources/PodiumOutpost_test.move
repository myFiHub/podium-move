#[test_only]
module 0xYourAddress::PodiumOutpost_test {
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use 0xYourAddress::PodiumOutpost;

    // Test constants
    const ADMIN: address = @0x123;
    const OWNER: address = @0x456;
    
    fun setup(): (signer, signer) {
        let admin = account::create_account_for_test(ADMIN);
        let owner = account::create_account_for_test(OWNER);

        // Initialize Outpost
        PodiumOutpost::initialize(&admin, 1000000);

        (admin, owner)
    }

    #[test]
    fun test_create_outpost() {
        let (admin, owner) = setup();
        
        // Create outpost
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

        // Verify ownership
        assert!(PodiumOutpost::is_outpost_owner(OWNER, OWNER), 1);
    }
} 