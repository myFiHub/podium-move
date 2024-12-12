module podium::PodiumPassCoin {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::option;
    use std::vector;
    use aptos_framework::object::{Self, Object, ConstructorRef};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset, MintRef, TransferRef, BurnRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::table::{Self, Table};

    /// Error codes
    const ENOT_PODIUM_PASS: u64 = 1;
    const EZERO_AMOUNT: u64 = 2;
    const EASSET_ALREADY_EXISTS: u64 = 3;
    const EASSET_DOES_NOT_EXIST: u64 = 4;

    /// Constants
    const DECIMALS: u8 = 0; // Since passes are whole units
    const PREFIX_TARGET: vector<u8> = b"TARGET_";
    const PREFIX_OUTPOST: vector<u8> = b"OUTPOST_";

    /// Stores capabilities for all asset types
    struct AssetCapabilities has key {
        mint_refs: Table<String, MintRef>,
        burn_refs: Table<String, BurnRef>,
        transfer_refs: Table<String, TransferRef>,
        metadata_objects: Table<String, Object<Metadata>>,
    }

    /// Initialize the PodiumPassCoin module
    fun init_module(admin: &signer) {
        move_to(admin, AssetCapabilities {
            mint_refs: table::new(),
            burn_refs: table::new(),
            transfer_refs: table::new(),
            metadata_objects: table::new(),
        });
    }

    /// Create a new asset type for a target account
    public fun create_target_asset(
        caller: &signer,
        target_id: String,
        name: String,
        icon_uri: String,
        project_uri: String
    ) acquires AssetCapabilities {
        // Only PodiumPass contract can call this
        assert!(is_podium_pass(caller), error::permission_denied(ENOT_PODIUM_PASS));
        
        let asset_symbol = generate_target_symbol(target_id);
        create_asset(caller, asset_symbol, name, icon_uri, project_uri);
    }

    /// Create a new asset type for an outpost
    public fun create_outpost_asset(
        caller: &signer,
        outpost_id: String,
        name: String,
        icon_uri: String,
        project_uri: String
    ) acquires AssetCapabilities {
        // Only PodiumPass contract can call this
        assert!(is_podium_pass(caller), error::permission_denied(ENOT_PODIUM_PASS));
        
        let asset_symbol = generate_outpost_symbol(outpost_id);
        create_asset(caller, asset_symbol, name, icon_uri, project_uri);
    }

    /// Internal function to create a new asset type
    fun create_asset(
        admin: &signer,
        asset_symbol: String,
        name: String,
        icon_uri: String,
        project_uri: String,
    ) acquires AssetCapabilities {
        let caps = borrow_global_mut<AssetCapabilities>(@podium);
        assert!(!table::contains(&caps.metadata_objects, asset_symbol), error::already_exists(EASSET_ALREADY_EXISTS));

        // Create metadata object
        let constructor_ref = &object::create_named_object(
            admin,
            *string::bytes(&asset_symbol)
        );

        // Initialize the fungible asset with metadata
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(), // No maximum supply
            name,
            asset_symbol,
            DECIMALS,
            icon_uri,
            project_uri,
        );

        // Generate and store capabilities
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        
        let metadata = object::address_to_object<Metadata>(
            object::create_object_address(&@podium, *string::bytes(&asset_symbol))
        );

        table::add(&mut caps.mint_refs, asset_symbol, mint_ref);
        table::add(&mut caps.burn_refs, asset_symbol, burn_ref);
        table::add(&mut caps.transfer_refs, asset_symbol, transfer_ref);
        table::add(&mut caps.metadata_objects, asset_symbol, metadata);
    }

    /// Mint new passes for a specific asset type
    public fun mint(
        caller: &signer,
        asset_symbol: String,
        amount: u64
    ): FungibleAsset acquires AssetCapabilities {
        assert!(amount > 0, error::invalid_argument(EZERO_AMOUNT));
        assert!(is_podium_pass(caller), error::permission_denied(ENOT_PODIUM_PASS));
        
        let caps = borrow_global<AssetCapabilities>(@podium);
        assert!(table::contains(&caps.mint_refs, asset_symbol), error::not_found(EASSET_DOES_NOT_EXIST));
        
        let mint_ref = table::borrow(&caps.mint_refs, asset_symbol);
        fungible_asset::mint(mint_ref, amount)
    }

    /// Burn passes of a specific asset type
    public fun burn(
        caller: &signer,
        asset_symbol: String,
        fa: FungibleAsset
    ) acquires AssetCapabilities {
        assert!(is_podium_pass(caller), error::permission_denied(ENOT_PODIUM_PASS));
        
        let caps = borrow_global<AssetCapabilities>(@podium);
        assert!(table::contains(&caps.burn_refs, asset_symbol), error::not_found(EASSET_DOES_NOT_EXIST));
        
        let burn_ref = table::borrow(&caps.burn_refs, asset_symbol);
        fungible_asset::burn(burn_ref, fa)
    }

    /// Transfer passes between accounts for a specific asset type
    public fun transfer(
        from: &signer,
        asset_symbol: String,
        to: address,
        amount: u64,
    ) acquires AssetCapabilities {
        let caps = borrow_global<AssetCapabilities>(@podium);
        assert!(table::contains(&caps.metadata_objects, asset_symbol), error::not_found(EASSET_DOES_NOT_EXIST));
        
        let metadata = table::borrow(&caps.metadata_objects, asset_symbol);
        primary_fungible_store::transfer(from, *metadata, to, amount);
    }

    /// Get balance of an account for a specific asset type
    public fun balance(account: address, asset_symbol: String): u64 acquires AssetCapabilities {
        let caps = borrow_global<AssetCapabilities>(@podium);
        assert!(table::contains(&caps.metadata_objects, asset_symbol), error::not_found(EASSET_DOES_NOT_EXIST));
        
        let metadata = table::borrow(&caps.metadata_objects, asset_symbol);
        primary_fungible_store::balance(account, *metadata)
    }

    /// Helper function to generate target asset symbol
    fun generate_target_symbol(target_id: String): String {
        string::utf8(vector::append(PREFIX_TARGET, *string::bytes(&target_id)))
    }

    /// Helper function to generate outpost asset symbol
    fun generate_outpost_symbol(outpost_id: String): String {
        string::utf8(vector::append(PREFIX_OUTPOST, *string::bytes(&outpost_id)))
    }

    /// Get metadata object for a specific asset type
    public fun get_metadata(asset_symbol: String): Object<Metadata> acquires AssetCapabilities {
        let caps = borrow_global<AssetCapabilities>(@podium);
        assert!(table::contains(&caps.metadata_objects, asset_symbol), error::not_found(EASSET_DOES_NOT_EXIST));
        *table::borrow(&caps.metadata_objects, asset_symbol)
    }

    /// Helper function to check if caller is the PodiumPass contract
    fun is_podium_pass(caller: &signer): bool {
        let caller_address = signer::address_of(caller);
        caller_address == @podium && exists<podium::PodiumPass::Config>(caller_address)
    }
} 