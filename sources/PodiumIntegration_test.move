#[test_only]
module podium::PodiumIntegration_test {
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use std::option;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use podium::PodiumPass;
    use podium::PodiumOutpost;
    use podium::PodiumPassCoin;

    const OUTPOST_OWNER: address = @0x123;
    const USER1: address = @0x456;
    const USER2: address = @0x789;

    #[test(admin = @admin, owner = @0x123, user1 = @0x456, user2 = @0x789)]
    public fun test_integration_flow(admin: &signer, owner: &signer, user1: &signer, user2: &signer) {
        // Initialize modules
        PodiumPass::initialize(admin);
        PodiumOutpost::initialize(admin);

        // Create outpost
        PodiumOutpost::create_outpost(
            owner,
            string::utf8(b"Test Outpost"),
            option::some(string::utf8(b"Description")),
            option::some(string::utf8(b"https://example.com")),
            option::some(string::utf8(b"https://example.com/image.png")),
            option::some(string::utf8(b"https://example.com/banner.png")),
            option::some(string::utf8(b"https://example.com/avatar.png")),
            option::some(vector::empty<String>())
        );

        // Create subscription
        let payment = coin::mint<AptosCoin>(100, admin);
        PodiumPass::create_subscription<address>(
            user1,
            OUTPOST_OWNER,
            30 * 24 * 60 * 60, // 30 days
            1, // tier
            payment
        );

        // Verify subscription
        let status = PodiumPass::get_account_status<address>(USER1);
        assert!(PodiumPass::has_subscription(&status) == true, 2);

        // ... rest of the test ...
    }
} 