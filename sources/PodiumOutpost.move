module podium::PodiumOutpost {
    friend podium::PodiumPass;

    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use std::option::Self;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_token_objects::collection;
    use aptos_token_objects::token::{Self, Token};
    use aptos_token_objects::royalty;
    use aptos_framework::coin;
    use aptos_framework::aptos_account;

    /// Error codes
    /// When a non-admin tries to perform restricted operations
    const ENOT_AUTHORIZED: u64 = 1;
    /// When trying to create/modify an outpost with invalid price
    const EINVALID_PRICE: u64 = 2;
    /// When trying to create an outpost that already exists
    const EOUTPOST_EXISTS: u64 = 3;
    /// When trying to operate on a non-existent outpost
    const EOUTPOST_NOT_FOUND: u64 = 4;
    /// When trying to transfer more coins than available balance
    const INSUFFICIENT_BALANCE: u64 = 5;

    /// Constants for collection configuration
    /// Name of the NFT collection for all outposts
    const COLLECTION_NAME: vector<u8> = b"Podium Outposts";
    /// Description of what outposts represent
    const COLLECTION_DESCRIPTION: vector<u8> = b"Exclusive spaces in the Podium ecosystem";
    /// Base URI for the collection
    const COLLECTION_URI: vector<u8> = b"https://podium.network/outposts";
    /// Default royalty percentage (5%)
    const DEFAULT_ROYALTY_NUMERATOR: u64 = 5;
    /// Denominator for royalty calculation (100 = percentage)
    const DEFAULT_ROYALTY_DENOMINATOR: u64 = 100;

    /// Stores data specific to each outpost NFT
    /// This data is stored in the token object itself
    struct OutpostData has key {
        /// Purchase price paid for the outpost
        price: u64,
        /// URI pointing to outpost-specific metadata
        metadata_uri: String,
    }

    /// Helper function to check if an address has OutpostData
    public fun has_outpost_data(addr: address): bool {
        exists<OutpostData>(addr)
    }

    /// Global configuration for the outpost system
    /// Stores collection-wide settings and pricing information
    struct Config has key {
        /// Default price for new outposts
        default_price: u64,
        /// List of custom prices for specific outposts
        custom_prices: vector<CustomPrice>,
        /// Reference to the NFT collection object
        collection: Object<collection::Collection>,
    }

    /// Defines custom pricing for specific outposts
    /// Allows for different pricing tiers or special outposts
    struct CustomPrice has store {
        /// Name of the outpost this price applies to
        outpost_name: String,
        /// Custom price for this specific outpost
        price: u64,
    }

    /// Initializes the PodiumOutpost module
    /// Sets up the NFT collection with royalties
    /// @param admin: The signer of the module creator
    #[test_only]
    /// Initialize module for testing
    public fun init_module_for_test(admin: &signer) {
        init_module(admin)
    }

    /// Initialize module with the given admin signer
    /// @param admin The signer of the module creator
    fun init_module(admin: &signer) {
        // Create royalty config
        let royalty = royalty::create(
            DEFAULT_ROYALTY_NUMERATOR,
            DEFAULT_ROYALTY_DENOMINATOR,
            @fihub // FiHub receives royalties
        );

        // Create the collection
        let constructor_ref = collection::create_unlimited_collection(
            admin,
            string::utf8(COLLECTION_DESCRIPTION),
            string::utf8(COLLECTION_NAME),
            option::some(royalty),
            string::utf8(COLLECTION_URI),
        );

        let collection = object::object_from_constructor_ref<collection::Collection>(&constructor_ref);

        // Initialize config
        move_to(admin, Config {
            default_price: 0,
            custom_prices: vector::empty(),
            collection,
        });
    }

    /// Sets the default price for new outposts
    /// Only callable by admin
    /// @param admin: The admin signer
    /// @param price: New default price in $MOVE
    public entry fun set_default_price(admin: &signer, price: u64) acquires Config {
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_AUTHORIZED));
        let config = borrow_global_mut<Config>(@podium);
        config.default_price = price;
    }

    /// Sets a custom price for a specific outpost
    /// Only callable by admin
    /// @param admin: The admin signer
    /// @param outpost_name: Name of the outpost
    /// @param price: Custom price in $MOVE
    public entry fun set_custom_price(
        admin: &signer,
        outpost_name: String,
        price: u64
    ) acquires Config {
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_AUTHORIZED));
        let config = borrow_global_mut<Config>(@podium);
        
        let i = 0;
        let len = vector::length(&config.custom_prices);
        while (i < len) {
            let custom_price = vector::borrow_mut(&mut config.custom_prices, i);
            if (custom_price.outpost_name == outpost_name) {
                custom_price.price = price;
                return
            };
            i = i + 1;
        };

        vector::push_back(&mut config.custom_prices, CustomPrice { outpost_name, price });
    }

    /// Safely transfers APT coins with recipient account verification
    /// @param sender: The signer of the sender
    /// @param recipient: The recipient address
    /// @param amount: Amount of APT to transfer
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

    /// Creates a new outpost NFT
    /// Mints the NFT and transfers payment to FiHub
    /// @param buyer: The signer purchasing the outpost
    /// @param outpost_name: Name for the new outpost
    /// @param description: Description of the outpost
    /// @param metadata_uri: URI for outpost metadata
    public entry fun create_outpost(
        buyer: &signer,
        outpost_name: String,
        description: String,
        metadata_uri: String
    ) acquires Config {
        let config = borrow_global<Config>(@podium);
        
        // Get price for this outpost
        let price = get_outpost_price(&config.custom_prices, &outpost_name, config.default_price);
        assert!(price > 0, error::invalid_argument(EINVALID_PRICE));

        // Use safe transfer instead of direct transfer
        transfer_with_check(buyer, @fihub, price);

        // Create the token
        let constructor_ref = &token::create(
            buyer,
            string::utf8(COLLECTION_NAME),
            description,
            outpost_name,
            option::none(), // Use collection-level royalty
            metadata_uri,
        );

        // Add outpost data
        let token_signer = object::generate_signer(constructor_ref);
        move_to(&token_signer, OutpostData {
            price,
            metadata_uri,
        });
    }

    /// Determines the price for a specific outpost
    /// Checks custom prices first, falls back to default
    /// @param custom_prices: List of custom price configurations
    /// @param outpost_name: Name of the outpost to price
    /// @param default_price: Fallback price if no custom price exists
    /// @return The price for the outpost
    fun get_outpost_price(
        custom_prices: &vector<CustomPrice>,
        outpost_name: &String,
        default_price: u64
    ): u64 {
        let i = 0;
        let len = vector::length(custom_prices);
        while (i < len) {
            let custom_price = vector::borrow(custom_prices, i);
            if (custom_price.outpost_name == *outpost_name) {
                return custom_price.price
            };
            i = i + 1;
        };
        default_price
    }

    /// Verifies if an address owns a specific outpost
    /// @param owner: Address to check
    /// @param outpost_name: Name of the outpost
    /// @return Boolean indicating ownership
    public fun is_outpost_owner(owner: address, outpost_name: String): bool acquires Config {
        let config = borrow_global<Config>(@podium);
        let token_address = token::create_token_address(
            &@podium,
            &string::utf8(COLLECTION_NAME),
            &outpost_name
        );
        object::is_owner(object::address_to_object<Token>(token_address), owner)
    }

    /// Gets the collection object
    /// Used for integration with other modules
    /// @return The collection object
    public fun get_collection(): Object<collection::Collection> acquires Config {
        borrow_global<Config>(@podium).collection
    }
}
   