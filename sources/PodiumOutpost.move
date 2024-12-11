module podium::PodiumOutpost {
    use std::string::{Self, String};
    use aptos_framework::event;
    use aptos_framework::account;
    use aptos_framework::signer;
    use aptos_token::token::{Self, TokenDataId};
    use podium::PodiumPass;

    // Error codes
    const ENOT_AUTHORIZED: u64 = 1;
    const ENAME_TAKEN: u64 = 2;
    const EOUTPOST_NOT_FOUND: u64 = 3;
    const EINVALID_PRICE: u64 = 4;
    const INVALID_VERSION: u64 = 5;
    const NOT_ADMIN: u64 = 6;
    const ENOT_OWNER: u64 = 7;
    const EINVALID_METADATA: u64 = 8;
    const PAUSED: u64 = 9;

    // Add after other constants
    const SEED_PREFIX: vector<u8> = b"PODIUM_OUTPOST";

    // Admin capability for version control and price setting
    struct AdminCap has key {
        version: u64
    }

    struct OutpostMetadata has store, drop {
        description: String,
        category: String,
        tags: vector<String>,
        social_links: vector<String>,
        custom_fields: vector<(String, String)>, // Flexible key-value pairs
        last_updated: u64,
    }

    struct OutpostNFT has key, store {
        token_data_id: TokenDataId,
        name: String,
        owner: address,
        outpost_address: address,
        price: u64,
        shares_supply: u64,
        shares_balance: vector<u64>,
        metadata: OutpostMetadata,
    }

    struct OutpostRegistry has key {
        version: u64,
        outposts: vector<OutpostNFT>,
        create_events: event::EventHandle<CreateOutpostEvent>,
        metadata_update_events: event::EventHandle<MetadataUpdateEvent>,
    }

    struct CreateOutpostEvent has drop, store {
        creator: address,
        name: String,
        price: u64,
        timestamp: u64,
    }

    struct MetadataUpdateEvent has drop, store {
        outpost_name: String,
        owner: address,
        timestamp: u64,
    }

    public fun initialize(
        admin: &signer,
        initial_price: u64
    ) {
        let admin_addr = signer::address_of(admin);
        
        // Create admin capability
        move_to(admin, AdminCap { version: 1 });
        
        // Initialize registry
        move_to(admin, OutpostRegistry {
            version: 1,
            outposts: vector::empty(),
            create_events: account::new_event_handle<CreateOutpostEvent>(admin),
            metadata_update_events: account::new_event_handle<MetadataUpdateEvent>(admin),
        });
    }

    public entry fun create_outpost(
        creator: &signer,
        name: String,
        description: String,
        uri: String,
        initial_price: u64,
        category: String,
        tags: vector<String>,
        social_links: vector<String>
    ) acquires OutpostRegistry {
        assert!(!PodiumPass::is_paused(), PAUSED);
        
        let registry = borrow_global_mut<OutpostRegistry>(@admin);
        verify_version(registry.version);
        
        let creator_addr = signer::address_of(creator);
        let outpost_address = generate_outpost_address(creator_addr, name);

        // Create NFT
        let token_data_id = token::create_tokendata(
            creator,
            string::utf8(b"Podium Outpost"),
            name,
            description,
            1,
            uri,
            creator_addr,
            0,
            0,
            token::create_token_mutability_config(&vector<bool>[false, false, false, false, false]),
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[]
        );

        let metadata = OutpostMetadata {
            description,
            category,
            tags,
            social_links,
            custom_fields: vector::empty(),
            last_updated: timestamp::now_seconds(),
        };

        let outpost = OutpostNFT {
            token_data_id,
            name,
            owner: creator_addr,
            outpost_address,
            price: initial_price,
            shares_supply: 0,
            shares_balance: vector::empty(),
            metadata,
        };

        vector::push_back(&mut registry.outposts, outpost);

        event::emit_event(
            &mut registry.create_events,
            CreateOutpostEvent {
                creator: creator_addr,
                name,
                price: initial_price,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    public entry fun set_outpost_price(
        admin: &signer,
        outpost_name: String,
        new_price: u64
    ) acquires OutpostRegistry, AdminCap {
        assert!(exists<AdminCap>(signer::address_of(admin)), NOT_ADMIN);
        
        let registry = borrow_global_mut<OutpostRegistry>(@admin);
        verify_version(registry.version);
        
        let outpost = find_outpost_mut(&mut registry.outposts, outpost_name);
        outpost.price = new_price;
    }

    public entry fun upgrade_version(
        admin: &signer,
        new_version: u64,
    ) acquires AdminCap, OutpostRegistry {
        let admin_addr = signer::address_of(admin);
        assert!(exists<AdminCap>(admin_addr), NOT_ADMIN);
        
        let admin_cap = borrow_global_mut<AdminCap>(admin_addr);
        let registry = borrow_global_mut<OutpostRegistry>(admin_addr);
        
        assert!(new_version > admin_cap.version, INVALID_VERSION);
        
        admin_cap.version = new_version;
        registry.version = new_version;
    }

    fun verify_version(current_version: u64) acquires AdminCap {
        assert!(
            exists<AdminCap>(@admin) &&
            current_version == borrow_global<AdminCap>(@admin).version,
            INVALID_VERSION
        );
    }

    fun find_outpost_mut(outposts: &mut vector<OutpostNFT>, name: String): &mut OutpostNFT {
        let i = 0;
        while (i < vector::length(outposts)) {
            let outpost = vector::borrow_mut(outposts, i);
            if (outpost.name == name) {
                return outpost;
            };
            i = i + 1;
        };
        abort EOUTPOST_NOT_FOUND
    }

    // Add these public functions for integration with PodiumPass
    
    // Get the owner of an outpost
    public fun get_outpost_owner(outpost_address: address): address acquires OutpostRegistry {
        let registry = borrow_global<OutpostRegistry>(@admin);
        let i = 0;
        while (i < vector::length(&registry.outposts)) {
            let outpost = vector::borrow(&registry.outposts, i);
            if (outpost.owner == outpost_address) {
                return outpost.owner;
            };
            i = i + 1;
        };
        abort EOUTPOST_NOT_FOUND
    }

    // Check if an address is the owner of an outpost
    public fun is_outpost_owner(outpost_address: address, owner: address): bool acquires OutpostRegistry {
        let registry = borrow_global<OutpostRegistry>(@admin);
        let i = 0;
        while (i < vector::length(&registry.outposts)) {
            let outpost = vector::borrow(&registry.outposts, i);
            if (outpost.owner == outpost_address) {
                return outpost.owner == owner;
            };
            i = i + 1;
        };
        false
    }

    // Function to check if a user has access to an outpost
    public fun has_access(user: address, outpost_address: address): bool acquires OutpostRegistry {
        // If user is the owner, they have access
        if (is_outpost_owner(outpost_address, user)) {
            return true;
        }
        
        // Check if user has an active subscription through PodiumPass
        PodiumPass::is_subscribed_to_outpost(
            borrow_global<PodiumPass>(@admin),
            outpost_address,
            user
        )
    }

    // Add function to update metadata
    public entry fun update_outpost_metadata(
        owner: &signer,
        outpost_name: String,
        description: Option<String>,
        category: Option<String>,
        tags: Option<vector<String>>,
        social_links: Option<vector<String>>,
        custom_fields: Option<vector<(String, String)>>
    ) acquires OutpostRegistry {
        let registry = borrow_global_mut<OutpostRegistry>(@admin);
        verify_version(registry.version);
        
        let outpost = find_outpost_mut(&mut registry.outposts, outpost_name);
        
        // Verify ownership
        assert!(outpost.owner == signer::address_of(owner), ENOT_OWNER);
        
        // Update fields if provided
        if (option::is_some(&description)) {
            outpost.metadata.description = option::extract(&mut description);
        };
        
        if (option::is_some(&category)) {
            outpost.metadata.category = option::extract(&mut category);
        };
        
        if (option::is_some(&tags)) {
            outpost.metadata.tags = option::extract(&mut tags);
        };
        
        if (option::is_some(&social_links)) {
            outpost.metadata.social_links = option::extract(&mut social_links);
        };
        
        if (option::is_some(&custom_fields)) {
            outpost.metadata.custom_fields = option::extract(&mut custom_fields);
        };
        
        outpost.metadata.last_updated = timestamp::now_seconds();

        event::emit_event(
            &mut registry.metadata_update_events,
            MetadataUpdateEvent {
                outpost_name,
                owner: signer::address_of(owner),
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    // Add getter function for metadata
    public fun get_outpost_metadata(outpost_name: String): OutpostMetadata acquires OutpostRegistry {
        let registry = borrow_global<OutpostRegistry>(@admin);
        let outpost = find_outpost(&registry.outposts, outpost_name);
        *&outpost.metadata
    }

    // Add helper function to find outpost (read-only version)
    fun find_outpost(outposts: &vector<OutpostNFT>, name: String): &OutpostNFT {
        let i = 0;
        while (i < vector::length(outposts)) {
            let outpost = vector::borrow(outposts, i);
            if (outpost.name == name) {
                return outpost;
            };
            i = i + 1;
        };
        abort EOUTPOST_NOT_FOUND
    }

    // Add function to generate outpost address
    fun generate_outpost_address(creator: address, name: String): address {
        let seed = SEED_PREFIX;
        vector::append(&mut seed, bcs::to_bytes(&creator));
        vector::append(&mut seed, bcs::to_bytes(&name));
        account::create_resource_address(&creator, seed)
    }

    // Add safe way to check if address is an outpost
    public fun try_get_outpost_owner(outpost_address: address): Option<address> acquires OutpostRegistry {
        let registry = borrow_global<OutpostRegistry>(@admin);
        let i = 0;
        while (i < vector::length(&registry.outposts)) {
            let outpost = vector::borrow(&registry.outposts, i);
            if (outpost.outpost_address == outpost_address) {
                return option::some(outpost.owner);
            };
            i = i + 1;
        };
        option::none()
    }
} 