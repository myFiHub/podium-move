module podium::PodiumPassCoin {
    friend podium::PodiumPass;

    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::option;
    use std::vector;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset, MintRef, TransferRef, BurnRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::table::{Self, Table};
    use aptos_framework::coin;
    use aptos_framework::aptos_account;
    use aptos_framework::aptos_coin::AptosCoin;

    /// Error codes
    /// When a non-PodiumPass contract tries to perform restricted operations
    const ENOT_PODIUM_PASS: u64 = 1;
    /// When attempting to mint/transfer zero tokens
    const EZERO_AMOUNT: u64 = 2;
    /// When trying to create an asset type that already exists
    const EASSET_ALREADY_EXISTS: u64 = 3;
    /// When trying to operate on a non-existent asset type
    const EASSET_DOES_NOT_EXIST: u64 = 4;
    /// When trying to transfer more coins than available balance
    const INSUFFICIENT_BALANCE: u64 = 5;

    /// Constants for asset configuration
    /// No decimal places as passes are whole units only
    const DECIMALS: u8 = 0;
    /// Prefix for target account assets to distinguish them
    const PREFIX_TARGET: vector<u8> = b"TARGET_";
    /// Prefix for outpost assets to distinguish them
    const PREFIX_OUTPOST: vector<u8> = b"OUTPOST_";

    /// Central storage for all fungible asset capabilities
    /// This structure holds all the permissions and references needed to manage
    /// multiple types of fungible assets (passes) in the system
    struct AssetCapabilities has key {
        /// Stores mint permissions for each asset type
        mint_refs: Table<String, MintRef>,
        /// Stores burn permissions for each asset type
        burn_refs: Table<String, BurnRef>,
        /// Stores transfer permissions for each asset type
        transfer_refs: Table<String, TransferRef>,
        /// Stores metadata objects for each asset type
        metadata_objects: Table<String, Object<Metadata>>,
    }

    /// Verifies if the caller is the PodiumPass contract
    /// Checks both address and presence of AssetCapabilities resource
    /// @param caller: The signer to verify
    /// @return Boolean indicating if caller is PodiumPass
    fun is_podium_pass(caller: &signer): bool {
        let caller_address = signer::address_of(caller);
        caller_address == @podium && exists<AssetCapabilities>(@podium)
    }

    /// Initializes the PodiumPassCoin module
    /// Creates the central storage for managing all pass types
    /// @param admin: The signer of the module creator (podium address)
    public fun init_module_for_test(admin: &signer) {
        init_module(admin)
    }

    /// Internal initialization function
    fun init_module(admin: &signer) {
        move_to(admin, AssetCapabilities {
            mint_refs: table::new(),
            burn_refs: table::new(),
            transfer_refs: table::new(),
            metadata_objects: table::new(),
        });
    }

    /// Creates a new fungible asset type for a target account
    /// Only callable by the PodiumPass contract
    /// @param caller: The signer of the calling contract (must be PodiumPass)
    /// @param target_id: Unique identifier for the target account
    /// @param name: Display name for the asset
    /// @param icon_uri: URI for the asset's icon
    /// @param project_uri: URI for the asset's project details
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

    /// Creates a new fungible asset type for an outpost
    /// Similar to create_target_asset but specifically for outpost passes
    /// @param caller: The signer of the calling contract (must be PodiumPass)
    /// @param outpost_id: Unique identifier for the outpost
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

    /// Internal function to handle asset creation logic
    /// Sets up all necessary capabilities and metadata for a new asset type
    /// @param admin: The signer creating the asset
    /// @param asset_symbol: Unique identifier for the asset
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

    /// Mints new passes of a specific asset type
    /// Only callable by PodiumPass contract
    /// @param caller: The signer of the calling contract
    /// @param asset_symbol: The asset type to mint
    /// @param amount: Number of passes to mint
    /// @return The newly minted fungible asset
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

    /// Burns (destroys) passes of a specific asset type
    /// Only callable by PodiumPass contract
    /// @param caller: The signer of the calling contract
    /// @param asset_symbol: The asset type to burn
    /// @param fa: The fungible asset to burn
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

    /// Transfers passes between accounts
    /// Can be called by any account that owns passes
    /// @param from: The signer of the sender
    /// @param asset_symbol: The asset type to transfer
    /// @param to: Recipient address
    /// @param amount: Number of passes to transfer
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

    /// Checks the balance of a specific asset type for an account
    /// @param account: The address to check
    /// @param asset_symbol: The asset type to check
    /// @return The number of passes owned
    public fun balance(account: address, asset_symbol: String): u64 acquires AssetCapabilities {
        let caps = borrow_global<AssetCapabilities>(@podium);
        assert!(table::contains(&caps.metadata_objects, asset_symbol), error::not_found(EASSET_DOES_NOT_EXIST));
        
        let metadata = table::borrow(&caps.metadata_objects, asset_symbol);
        primary_fungible_store::balance(account, *metadata)
    }

    /// Generates a standardized symbol for target account assets
    /// @param target_id: The target account identifier
    /// @return The formatted asset symbol
    public(friend) fun generate_target_symbol(target_id: String): String {
        let prefix = string::utf8(b"TARGET_");
        let result = string::utf8(vector::empty());
        string::append(&mut result, prefix);
        string::append(&mut result, target_id);
        result
    }

    /// Generates a standardized symbol for outpost assets
    /// @param outpost_id: The outpost identifier
    /// @return The formatted asset symbol
    fun generate_outpost_symbol(outpost_id: String): String {
        let prefix = string::utf8(b"OUTPOST_");
        let result = string::utf8(vector::empty());
        string::append(&mut result, prefix);
        string::append(&mut result, outpost_id);
        result
    }

    /// Retrieves the metadata object for a specific asset type
    /// @param asset_symbol: The asset type to look up
    /// @return The metadata object for the asset
    public fun get_metadata(asset_symbol: String): Object<Metadata> acquires AssetCapabilities {
        let caps = borrow_global<AssetCapabilities>(@podium);
        assert!(table::contains(&caps.metadata_objects, asset_symbol), error::not_found(EASSET_DOES_NOT_EXIST));
        *table::borrow(&caps.metadata_objects, asset_symbol)
    }

    /// Safely transfers $MOVE coins with recipient account verification
    /// Handles both registered and unregistered recipient accounts
    /// @param sender: The signer of the sender
    /// @param recipient: The recipient address
    /// @param amount: Amount of $MOVE to transfer
    fun transfer_with_check(sender: &signer, recipient: address, amount: u64) {
        let sender_addr = signer::address_of(sender);
        assert!(
            coin::balance<AptosCoin>(sender_addr) >= amount,
            error::invalid_argument(INSUFFICIENT_BALANCE)
        );

        if (coin::is_account_registered<AptosCoin>(recipient)) {
            coin::transfer<AptosCoin>(sender, recipient, amount);
        } else {
            aptos_account::transfer(sender, recipient, amount);
        };
    }
} 