module podium::PodiumOutpost {
    use std::string::{Self, String};
    use std::signer;
    use std::option::Self;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::event;
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_framework::table::{Self, Table};
    
    // Error codes
    const ENOT_ADMIN: u64 = 0x10001;  // 65537
    const EOUTPOST_EXISTS: u64 = 0x10002;  // 65538
    const EOUTPOST_NOT_FOUND: u64 = 0x10003;  // 65539
    const ENOT_OWNER: u64 = 0x10004;  // 65540
    const EINVALID_PRICE: u64 = 0x10005;  // 65541
    const EINVALID_FEE: u64 = 0x10006;  // 65542
    const EEMERGENCY_PAUSE: u64 = 0x10007;  // 65543

    // Constants
    const COLLECTION_NAME: vector<u8> = b"PodiumOutposts";
    const COLLECTION_DESCRIPTION: vector<u8> = b"Podium Protocol Outposts";
    const COLLECTION_URI: vector<u8> = b"https://podium.fi/outposts";
    const MAX_FEE_PERCENTAGE: u64 = 10000; // 100% = 10000 basis points

    /// Struct to store outpost-specific data
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct OutpostData has key, store {
        /// The outpost's name
        name: String,
        /// The outpost's description
        description: String,
        /// The outpost's URI
        uri: String,
        /// The outpost's price
        price: u64,
        /// The outpost's fee share (in basis points)
        fee_share: u64,
        /// Emergency pause flag
        emergency_pause: bool,
    }

    /// Event emitted when a new outpost is created
    #[event]
    struct OutpostCreatedEvent has drop, store {
        /// Address of the outpost creator
        creator: address,
        /// Address of the created outpost
        outpost_address: address,
        /// Name of the outpost
        name: String,
        /// Initial price of the outpost
        price: u64,
        /// Initial fee share of the outpost
        fee_share: u64,
    }

    /// Event emitted when an outpost's price is updated
    #[event]
    struct PriceUpdateEvent has drop, store {
        /// Address of the outpost being updated
        outpost_address: address,
        /// Previous price
        old_price: u64,
        /// New price
        new_price: u64,
    }

    /// Event emitted when an outpost's fee share is updated
    #[event]
    struct FeeUpdateEvent has drop, store {
        /// Address of the outpost being updated
        outpost_address: address,
        /// Previous fee share
        old_fee: u64,
        /// New fee share
        new_fee: u64,
    }

    /// Event emitted when an outpost's emergency pause status changes
    #[event]
    struct EmergencyPauseEvent has drop, store {
        /// Address of the outpost being updated
        outpost_address: address,
        /// New pause status
        paused: bool,
    }

    /// Event emitted when an outpost's metadata is updated
    #[event]
    struct MetadataUpdateEvent has drop, store {
        /// Address of the outpost being updated
        outpost_address: address,
        /// Old name of the outpost
        old_name: String,
        /// New name of the outpost
        new_name: String,
        /// Old description of the outpost
        old_description: String,
        /// New description of the outpost
        new_description: String,
        /// Old URI of the outpost
        old_uri: String,
        /// New URI of the outpost
        new_uri: String,
    }

    /// Get event creator address
    public fun get_event_creator(event: &OutpostCreatedEvent): address {
        event.creator
    }

    /// Get event outpost address
    public fun get_event_outpost_address(event: &OutpostCreatedEvent): address {
        event.outpost_address
    }

    /// Get event outpost name
    public fun get_event_name(event: &OutpostCreatedEvent): String {
        event.name
    }

    /// Get event price
    public fun get_event_price(event: &OutpostCreatedEvent): u64 {
        event.price
    }

    /// Get event fee share
    public fun get_event_fee_share(event: &OutpostCreatedEvent): u64 {
        event.fee_share
    }

    /// Internal function to create an outpost and return the object
    public fun create_outpost_internal(
        creator: &signer,
        name: String,
        description: String,
        uri: String,
        price: u64,
        fee_share: u64,
    ): Object<OutpostData> {
        // Validate inputs
        assert!(fee_share <= MAX_FEE_PERCENTAGE, EINVALID_FEE);
        assert!(price > 0, EINVALID_PRICE);

        // Get collection address and verify it exists
        let collection_addr = collection::create_collection_address(&@podium, &string::utf8(COLLECTION_NAME));
        assert!(object::is_object(collection_addr), EOUTPOST_NOT_FOUND);

        // Create outpost token
        let constructor_ref = token::create_named_token(
            creator,
            string::utf8(COLLECTION_NAME),
            description,
            name,
            option::none(),
            uri,
        );

        // Generate signer and extend the token object
        let outpost_signer = object::generate_signer(&constructor_ref);
        
        // Initialize outpost data
        move_to(&outpost_signer, OutpostData {
            name,
            description,
            uri,
            price,
            fee_share,
            emergency_pause: false,
        });

        // Get the object reference
        let object = object::object_from_constructor_ref<OutpostData>(&constructor_ref);

        // Emit creation event
        event::emit(OutpostCreatedEvent {
            creator: signer::address_of(creator),
            outpost_address: object::object_address<OutpostData>(&object),
            name,
            price,
            fee_share,
        });

        object
    }

    /// Entry function to create a new outpost
    public entry fun create_outpost(
        creator: &signer,
        name: String,
        description: String,
        uri: String,
        price: u64,
        fee_share: u64,
    ) {
        create_outpost_internal(creator, name, description, uri, price, fee_share);
    }

    /// Create the Podium Outposts collection (admin only)
    public fun create_podium_collection(creator: &signer) {
        assert!(signer::address_of(creator) == @podium, ENOT_ADMIN);
        
        collection::create_unlimited_collection(
            creator,
            string::utf8(COLLECTION_DESCRIPTION),
            string::utf8(COLLECTION_NAME),
            option::none(), // No royalty
            string::utf8(COLLECTION_URI),
        );
    }

    /// Update outpost price (owner only)
    public entry fun update_price(
        owner: &signer,
        outpost: Object<OutpostData>,
        new_price: u64,
    ) acquires OutpostData {
        // Validate owner
        assert!(object::is_owner(outpost, signer::address_of(owner)), ENOT_OWNER);
        assert!(new_price > 0, EINVALID_PRICE);
        
        let outpost_addr = object::object_address(&outpost);
        let outpost_data = borrow_global_mut<OutpostData>(outpost_addr);
        
        // Validate state
        assert!(!outpost_data.emergency_pause, EEMERGENCY_PAUSE);

        // Emit price update event
        event::emit(PriceUpdateEvent {
            outpost_address: outpost_addr,
            old_price: outpost_data.price,
            new_price,
        });

        outpost_data.price = new_price;
    }

    /// Update fee share (owner only)
    public entry fun update_fee_share(
        owner: &signer,
        outpost: Object<OutpostData>,
        new_fee_share: u64,
    ) acquires OutpostData {
        // Validate owner and input
        assert!(object::is_owner(outpost, signer::address_of(owner)), ENOT_OWNER);
        assert!(new_fee_share <= MAX_FEE_PERCENTAGE, EINVALID_FEE);
        
        let outpost_addr = object::object_address(&outpost);
        let outpost_data = borrow_global_mut<OutpostData>(outpost_addr);
        
        // Validate state
        assert!(!outpost_data.emergency_pause, EEMERGENCY_PAUSE);

        // Emit fee update event
        event::emit(FeeUpdateEvent {
            outpost_address: outpost_addr,
            old_fee: outpost_data.fee_share,
            new_fee: new_fee_share,
        });

        outpost_data.fee_share = new_fee_share;
    }

    /// Toggle emergency pause (owner only)
    public entry fun toggle_emergency_pause(
        owner: &signer,
        outpost: Object<OutpostData>,
    ) acquires OutpostData {
        assert!(object::is_owner(outpost, signer::address_of(owner)), ENOT_OWNER);
        
        let outpost_addr = object::object_address(&outpost);
        let outpost_data = borrow_global_mut<OutpostData>(outpost_addr);
        
        outpost_data.emergency_pause = !outpost_data.emergency_pause;

        event::emit(EmergencyPauseEvent {
            outpost_address: outpost_addr,
            paused: outpost_data.emergency_pause,
        });
    }

    // Getter functions for outpost data
    #[view]
    public fun get_price(outpost: Object<OutpostData>): u64 acquires OutpostData {
        borrow_global<OutpostData>(object::object_address(&outpost)).price
    }

    #[view]
    public fun get_fee_share(outpost: Object<OutpostData>): u64 acquires OutpostData {
        borrow_global<OutpostData>(object::object_address(&outpost)).fee_share
    }

    #[view]
    public fun is_paused(outpost: Object<OutpostData>): bool acquires OutpostData {
        borrow_global<OutpostData>(object::object_address(&outpost)).emergency_pause
    }

    #[view]
    public fun verify_access(outpost: Object<OutpostData>): bool acquires OutpostData {
        !borrow_global<OutpostData>(object::object_address(&outpost)).emergency_pause
    }

    /// Collection data for outposts
    struct OutpostCollection has key {
        collection: Object<collection::Collection>,
        outposts: Table<address, Object<OutpostData>>,
    }

    /// Initialize the collection for outposts
    public fun init_collection(creator: &signer) {
        // Only admin can initialize collection
        assert!(signer::address_of(creator) == @podium, ENOT_ADMIN);

        if (!exists<OutpostCollection>(@podium)) {
            // Create collection
            collection::create_unlimited_collection(
                creator,
                string::utf8(COLLECTION_DESCRIPTION),
                string::utf8(COLLECTION_NAME),
                option::none(),
                string::utf8(COLLECTION_URI),
            );

            // Get collection address and object
            let collection_addr = collection::create_collection_address(&@podium, &string::utf8(COLLECTION_NAME));
            let collection_object = object::address_to_object<collection::Collection>(collection_addr);
            
            // Store collection data
            move_to(creator, OutpostCollection {
                collection: collection_object,
                outposts: table::new(),
            });
        };
    }

    /// Verify ownership of an outpost
    public fun verify_ownership(outpost: Object<OutpostData>, owner: address): bool {
        object::is_owner(outpost, owner)
    }

    /// Check if an object has outpost data
    public fun has_outpost_data(outpost: Object<OutpostData>): bool {
        exists<OutpostData>(object::object_address(&outpost))
    }

    /// Get outpost object from token address
    public fun get_outpost_from_token_address(token_address: address): Object<OutpostData> {
        object::address_to_object<OutpostData>(token_address)
    }

    /// Update outpost metadata (owner only)
    public entry fun update_metadata(
        owner: &signer,
        outpost: Object<OutpostData>,
        new_name: String,
        new_description: String,
        new_uri: String,
    ) acquires OutpostData {
        // Validate owner
        assert!(object::is_owner(outpost, signer::address_of(owner)), ENOT_OWNER);

        let outpost_addr = object::object_address(&outpost);
        let outpost_data = borrow_global_mut<OutpostData>(outpost_addr);
        
        // Validate state
        assert!(!outpost_data.emergency_pause, EEMERGENCY_PAUSE);

        // Emit metadata update event
        event::emit(MetadataUpdateEvent {
            outpost_address: outpost_addr,
            old_name: outpost_data.name,
            new_name,
            old_description: outpost_data.description,
            new_description,
            old_uri: outpost_data.uri,
            new_uri,
        });

        outpost_data.name = new_name;
        outpost_data.description = new_description;
        outpost_data.uri = new_uri;
    }
}
