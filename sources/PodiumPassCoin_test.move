#[test_only]
module podium::PodiumPassCoin_test {
    use std::signer;
    use std::string::String;
    use podium::PodiumPassCoin;

    public fun initialize_for_test(admin: &signer) {
        assert!(signer::address_of(admin) == @podium, 0);
        if (!PodiumPassCoin::is_initialized()) {
            PodiumPassCoin::initialize_for_test(admin);
        };
    }

    public fun create_test_asset(
        creator: &signer,
        asset_symbol: String,
        name: String,
        icon_uri: String,
        project_uri: String,
    ) {
        PodiumPassCoin::create_target_asset_test(
            creator,
            asset_symbol,
            name,
            icon_uri,
            project_uri
        );
    }
} 