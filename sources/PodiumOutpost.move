module podium::PodiumOutpost {
    use std::string::{Self, String};
    use std::signer;
    use std::option::{Self, Option};
    use aptos_framework::object::{Self, Object, ConstructorRef};
    use aptos_framework::event;
    use aptos_framework::error;
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_token_objects::royalty::{Self, Royalty};
    use aptos_framework::table::{Self, Table};
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use std::debug;
    use aptos_framework::aggregator_v2;
    
    // Error codes
    const ENOT_ADMIN: u64 = 0x10001;  // 65537
    const EOUTPOST_EXISTS: u64 = 0x10002;  // 65538
    const EOUTPOST_NOT_FOUND: u64 = 0x10003;  // 65539
    const ENOT_OWNER: u64 = 0x10004;  // 65540
    const EINVALID_PRICE: u64 = 0x10005;  // 65541
    const EINVALID_FEE: u64 = 0x10006;  // 65542
    const EEMERGENCY_PAUSE: u64 = 0x10007;  // 65543

    // Constants - internal to module
    const COLLECTION_NAME_BYTES: vector<u8> = b"PodiumOutposts";
    const COLLECTION_DESCRIPTION_BYTES: vector<u8> = b"Podium Protocol Outposts";
    const COLLECTION_URI_BYTES: vector<u8> = b"https://podium.fi/outposts";
    const MAX_FEE_PERCENTAGE: u64 = 10000; // 100% = 10000 basis points

    // Constants for outpost pricing and fees
    const OUTPOST_FEE_SHARE: u64 = 500;

    public fun get_outpost_fee_share(): u64 {
        OUTPOST_FEE_SHARE
    }

    /// Struct to store outpost-specific data
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct OutpostData has key, store {
        /// The collection this outpost belongs to
        collection: Object<collection::Collection>,
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

    /// Our custom token struct that maintains compatibility with token module interface
    struct PodiumToken has key, store {
        collection: Object<collection::Collection>,
        description: String,
        name: String,
        uri: String,
        mutation_events: event::EventHandle<token::MutationEvent>,
        royalty: Option<Object<royalty::Royalty>>,
        index: Option<aggregator_v2::AggregatorSnapshot<u64>>,  // Add index field to match token module
    }

    /// Creates a new token with a deterministic address based on creator and token name,
    /// but allows specifying a separate collection object.
    /// This is similar to create_named_token but works with an existing collection object
    /// rather than requiring the collection to be at the creator's address.
    fun create_named_token_with_collection(
        creator: &signer,
        collection: Object<collection::Collection>,
        description: String,
        name: String,
        royalty: Option<Royalty>,
        uri: String,
    ): ConstructorRef {
        // Create seed by concatenating collection name and token name
        let seed = token::create_token_seed(&collection::name(collection), &name);
        
        // Create object with deterministic address
        let constructor_ref = object::create_named_object(creator, seed);
        let object_signer = object::generate_signer(&constructor_ref);

        // Initialize royalty if provided
        let royalty_object = if (option::is_some(&royalty)) {
            // Initialize royalty directly on the token object
            royalty::init(&constructor_ref, option::extract(&mut royalty));
            // Get the royalty object from the token object
            let creator_addr = signer::address_of(creator);
            option::some(object::address_to_object<royalty::Royalty>(
                object::create_object_address(&creator_addr, seed)
            ))
        } else {
            option::none()
        };

        // Initialize our custom token data
        let token = PodiumToken {
            collection,
            description,
            name,
            uri,
            mutation_events: object::new_event_handle(&object_signer),
            royalty: royalty_object,
            index: option::none(),  // Initialize index as none since we don't need it
        };
        move_to(&object_signer, token);

        constructor_ref
    }

    /// Internal function to create an outpost and return the object
    public fun create_outpost_internal(
        creator: &signer,
        name: String,
        description: String,
        uri: String,
    ): Object<OutpostData> acquires OutpostCollection {
        debug::print(&string::utf8(b"=== Starting create_outpost_internal ==="));
        
        // Handle payment and print
        debug::print(&string::utf8(b"Processing payment of:"));
        let purchase_price = get_outpost_purchase_price();
        debug::print(&purchase_price);
        coin::transfer<AptosCoin>(creator, @podium, purchase_price);
        debug::print(&string::utf8(b"Payment processed"));
        
        // Print creator info
        debug::print(&string::utf8(b"Creator address:"));
        debug::print(&signer::address_of(creator));

        // Get collection data
        assert!(exists<OutpostCollection>(@podium), error::not_found(EOUTPOST_NOT_FOUND));
        let collection_data = borrow_global_mut<OutpostCollection>(@podium);
        
        debug::print(&string::utf8(b"Collection address:"));
        debug::print(&collection_data.collection_addr);

        // Print collection details before token creation
        let collection_name = get_collection_name();
        debug::print(&string::utf8(b"Collection name:"));
        debug::print(&collection_name);
        
        // Print seed calculation for deterministic address
        let seed = token::create_token_seed(&collection_name, &name);
        debug::print(&string::utf8(b"Token seed:"));
        debug::print(&seed);
        
        // Print expected object address
        let expected_obj_addr = object::create_object_address(&signer::address_of(creator), seed);
        debug::print(&string::utf8(b"Expected object address:"));
        debug::print(&expected_obj_addr);

        // Get collection object
        let collection = object::address_to_object<collection::Collection>(collection_data.collection_addr);
        
        // Create token using our custom function that handles collection properly
        let constructor_ref = create_named_token_with_collection(
            creator,
            collection,
            description,
            name,
            option::none<Royalty>(), // Explicitly specify type
            uri,
        );

        // Initialize outpost data
        let outpost_signer = object::generate_signer(&constructor_ref);
        move_to(&outpost_signer, OutpostData {
            collection,
            name,
            description,
            uri,
            price: purchase_price,
            fee_share: OUTPOST_FEE_SHARE,
            emergency_pause: false,
        });

        // Now get the object reference after data is initialized
        let token = object::object_from_constructor_ref<OutpostData>(&constructor_ref);
        let token_addr = object::object_address(&token);
        debug::print(&string::utf8(b"Token created at address:"));
        debug::print(&token_addr);

        // Store outpost in collection
        table::add(&mut collection_data.outposts, token_addr, token);

        // Emit creation event
        event::emit(OutpostCreatedEvent {
            creator: signer::address_of(creator),
            outpost_address: token_addr,
            name,
            price: purchase_price,
            fee_share: OUTPOST_FEE_SHARE,
        });

        debug::print(&string::utf8(b"=== Finished create_outpost_internal ==="));
        token
    }

    /// Entry function to create a new outpost
    public entry fun create_outpost(
        creator: &signer,
        name: String,
        description: String,
        uri: String,
    ) acquires OutpostCollection {
        let _outpost = create_outpost_internal(creator, name, description, uri);
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

    /// Update fee share (admin only)
    public entry fun update_fee_share(
        admin: &signer,
        outpost: Object<OutpostData>,
        new_fee_share: u64,
    ) acquires OutpostData {
        // Validate admin and input
        assert!(signer::address_of(admin) == @podium, ENOT_ADMIN);
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

    /// Collection data for outposts - now includes a capability
    struct OutpostCollection has key {
        collection_addr: address,
        outposts: Table<address, Object<OutpostData>>,
        purchase_price: u64,
    }

    /// Capability to manage outposts
    struct OutpostManagerCap has key, store {
        collection_addr: address,
    }

    /// Initialize the collection for outposts
    public fun init_collection(creator: &signer) {
        assert!(signer::address_of(creator) == @podium, ENOT_ADMIN);

        if (!exists<OutpostCollection>(@podium)) {
            debug::print(&string::utf8(b"Creating collection..."));
            
            let constructor_ref = collection::create_unlimited_collection(
                creator,
                string::utf8(COLLECTION_DESCRIPTION_BYTES),
                string::utf8(COLLECTION_NAME_BYTES),
                option::none(),
                string::utf8(COLLECTION_URI_BYTES),
            );

            let collection_addr = object::address_from_constructor_ref(&constructor_ref);
            debug::print(&string::utf8(b"Collection created at address:"));
            debug::print(&collection_addr);

            move_to(creator, OutpostCollection {
                collection_addr,
                outposts: table::new(),
                purchase_price: 1000,
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

    /// Get the expected token address for a given creator and token name
    public fun get_token_address(creator: address, name: String): address {
        // Create seed by concatenating collection name and token name
        let seed = token::create_token_seed(
            &string::utf8(COLLECTION_NAME_BYTES),
            &name,
        );
        
        // Create object address using creator and seed
        object::create_object_address(&creator, seed)
    }

    /// Verify that a token exists at the expected address
    public fun verify_token_address(creator: address, name: String, token: Object<OutpostData>): bool {
        let expected_address = get_token_address(creator, name);
        object::object_address(&token) == expected_address
    }

    // Public functions to access collection constants
    public fun get_collection_name(): String {
        string::utf8(COLLECTION_NAME_BYTES)
    }

    public fun get_collection_description(): String {
        string::utf8(COLLECTION_DESCRIPTION_BYTES)
    }

    public fun get_collection_uri(): String {
        string::utf8(COLLECTION_URI_BYTES)
    }

    /// Get the collection address
    public fun get_collection_address(): address acquires OutpostCollection {
        let collection_data = borrow_global<OutpostCollection>(@podium);
        collection_data.collection_addr
    }

    #[view]
    /// Get the collection object
    public fun get_collection(): Object<collection::Collection> acquires OutpostCollection {
        let collection_data = borrow_global<OutpostCollection>(@podium);
        object::address_to_object<collection::Collection>(collection_data.collection_addr)
    }

    #[view]
    /// Get collection object from an outpost
    public fun collection_object(outpost: Object<OutpostData>): Object<collection::Collection> acquires OutpostData {
        borrow_global<OutpostData>(object::object_address(&outpost)).collection
    }

    #[view]
    /// Get the collection data
    public fun get_collection_data(): address acquires OutpostCollection {
        let collection_data = borrow_global<OutpostCollection>(@podium);
        collection_data.collection_addr
    }

    #[view]
    /// Check if outpost exists in collection
    public fun contains_outpost(outpost_addr: address): bool acquires OutpostCollection {
        let collection_data = borrow_global<OutpostCollection>(@podium);
        table::contains(&collection_data.outposts, outpost_addr)
    }

    /// Add function to update purchase price (admin only)
    public entry fun update_outpost_price(admin: &signer, new_price: u64) acquires OutpostCollection {
        assert!(signer::address_of(admin) == @podium, ENOT_ADMIN);
        assert!(new_price > 0, EINVALID_PRICE);
        
        let collection_data = borrow_global_mut<OutpostCollection>(@podium);
        collection_data.purchase_price = new_price;
    }

    /// Add getter for outpost purchase price
    public fun get_outpost_purchase_price(): u64 acquires OutpostCollection {
        borrow_global<OutpostCollection>(@podium).purchase_price
    }

    /// Check if an address belongs to an outpost
    #[view]
    public fun is_outpost(addr: address): bool acquires OutpostCollection {
        let collection_data = borrow_global<OutpostCollection>(@podium);
        table::contains(&collection_data.outposts, addr)
    }
}
