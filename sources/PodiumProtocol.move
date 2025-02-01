module podium::PodiumProtocol {
    use std::string::{Self, String};
    use std::signer;
    use std::option::{Self, Option};
    use std::vector;
    use aptos_framework::object::{Self, Object, ConstructorRef};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::error;
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_token_objects::royalty::{Self, Royalty};
    use aptos_framework::table::{Self, Table};
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use std::debug;
    use aptos_framework::aggregator_v2;
    use aptos_framework::code;
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset, MintRef, TransferRef, BurnRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::account;
    use aptos_framework::aptos_account;
    use std::bcs;

    // Error constants - Core Protocol
    const ENOT_ADMIN: u64 = 1;
    const EINVALID_FEE_VALUE: u64 = 2;
    const EUNAUTHORIZED: u64 = 3;
    const EACCOUNT_NOT_REGISTERED: u64 = 4;
    const EINVALID_AMOUNT: u64 = 5;
    const EINVALID_FEE: u64 = 6;
    const EPROTOCOL_NOT_INITIALIZED: u64 = 7;

    // Error constants - Outpost Related
    const EOUTPOST_EXISTS: u64 = 8;
    const EOUTPOST_NOT_FOUND: u64 = 9;
    const EINVALID_PRICE: u64 = 10;
    const EINSUFFICIENT_BALANCE: u64 = 11;
    const ENOT_OWNER: u64 = 12;
    const EEMERGENCY_PAUSE: u64 = 13;

    // Error constants - Pass Related
    const EPASS_NOT_FOUND: u64 = 14;
    const INSUFFICIENT_BALANCE: u64 = 15;

    // Error constants - Subscription Related
    const ESUBSCRIPTION_NOT_FOUND: u64 = 16;
    const ESUBSCRIPTION_EXPIRED: u64 = 17;
    const ESUBSCRIPTION_ALREADY_EXISTS: u64 = 18;
    const EINVALID_SUBSCRIPTION_DURATION: u64 = 19;
    const EINVALID_SUBSCRIPTION_TIER: u64 = 20;

    // Error constants - Tier Related
    const EINVALID_TIER: u64 = 21;
    const ETIER_EXISTS: u64 = 22;
    const ETIER_NOT_FOUND: u64 = 23;
    const EINVALID_DURATION: u64 = 24;
    const EINVALID_TIER_PRICE: u64 = 25;
    const EINVALID_TIER_DURATION: u64 = 26;

    // Constants - Outpost related
    const COLLECTION_NAME_BYTES: vector<u8> = b"PodiumOutposts";
    const COLLECTION_DESCRIPTION_BYTES: vector<u8> = b"Podium Protocol Outposts";
    const COLLECTION_URI_BYTES: vector<u8> = b"https://podium.fi/outposts";
    const MAX_FEE_PERCENTAGE: u64 = 10000; // 100% = 10000 basis points
    const OUTPOST_FEE_SHARE: u64 = 500;

    // Constants - Fee related (in basis points)
    const BPS: u64 = 10000; // 100% = 10000 basis points
    const MAX_REFERRAL_FEE_PERCENT: u64 = 200; // 2% in basis points
    const MAX_PROTOCOL_FEE_PERCENT: u64 = 400; // 4% in basis points
    const MAX_SUBJECT_FEE_PERCENT: u64 = 800; // 8% in basis points

    // Constants for scaling and bonding curve calculations
    const INPUT_SCALE: u64 = 1000000; // K factor for overflow prevention
    const INITIAL_PRICE: u64 = 100000000; // 1 APT in OCTA units (10^8)
    const DEFAULT_WEIGHT_A: u64 = 173; // 1.73% in basis points
    const DEFAULT_WEIGHT_B: u64 = 257; // 2.57% in basis points
    const DEFAULT_WEIGHT_C: u64 = 23; // 
    const OCTA: u64 = 100000000; // 10^8 scaling
    const DECIMALS: u8 = 8; // 8 decimals for OCTA

    // Time constants
    const SECONDS_PER_WEEK: u64 = 7 * 24 * 60 * 60;
    const SECONDS_PER_MONTH: u64 = 30 * 24 * 60 * 60;
    const SECONDS_PER_YEAR: u64 = 365 * 24 * 60 * 60;
    const DURATION_WEEK: u64 = 1;
    const DURATION_MONTH: u64 = 2;
    const DURATION_YEAR: u64 = 3;

    // Calculate the minimum unit (1 whole pass)
    const MIN_WHOLE_PASS: u64 = 100000000; // One whole pass unit (10^8)

    // ============ Core Data Structures ============

    /// Outpost data structure
    struct OutpostData has key, store {
        collection: Object<collection::Collection>,
        name: String,
        description: String,
        uri: String,
        price: u64,
        fee_share: u64,
        emergency_pause: bool,
    }

    /// Pass token structure
    struct PodiumToken has key, store {
        collection: Object<collection::Collection>,
        description: String,
        name: String,
        uri: String,
        mutation_events: event::EventHandle<token::MutationEvent>,
        royalty: Option<Object<royalty::Royalty>>,
        index: Option<aggregator_v2::AggregatorSnapshot<u64>>,
    }

    /// Central configuration
    struct Config has key {
        // Fee configuration
        protocol_fee_percent: u64,
        subject_fee_percent: u64,
        referral_fee_percent: u64,
        protocol_subscription_fee: u64, // basis points (e.g. 500 = 5%)
        protocol_pass_fee: u64,        // basis points
        referrer_fee: u64,             // basis points
        treasury: address,
        
        
        // Bonding curve parameters
        weight_a: u64,
        weight_b: u64,
        weight_c: u64,
        
        // Collections and stats
        collection_addr: address,
        outposts: Table<address, Object<OutpostData>>,
        pass_stats: Table<address, PassStats>,
        
        // Subscription management
        subscription_configs: Table<address, SubscriptionConfig>,
        
        // Event handles
        pass_purchase_events: EventHandle<PassPurchaseEvent>,
        pass_sell_events: EventHandle<PassSellEvent>,
        subscription_events: EventHandle<SubscriptionEvent>,
        subscription_created_events: EventHandle<SubscriptionCreatedEvent>,
        subscription_cancelled_events: EventHandle<SubscriptionCancelledEvent>,
        tier_updated_events: EventHandle<TierUpdatedEvent>,
        outpost_config_events: EventHandle<OutpostSubscriptionConfigEvent>,
        fee_update_events: EventHandle<ProtocolFeeUpdateEvent>,
        outpost_created_events: EventHandle<OutpostCreatedEvent>,
        outpost_price: u64,
    }

    /// Asset capabilities for fungible tokens
    struct AssetCapabilities has key {
        mint_refs: Table<String, MintRef>,
        burn_refs: Table<String, BurnRef>,
        transfer_refs: Table<String, TransferRef>,
        metadata_objects: Table<String, Object<Metadata>>,
    }

    /// Pass statistics tracking
    struct PassStats has key, store {
        total_supply: u64,
        last_price: u64
    }

    /// Subscription configuration
    struct SubscriptionConfig has key, store {
        tiers: vector<SubscriptionTier>,
        subscriptions: Table<address, Subscription>,
        max_tiers: u64,
    }

    /// Subscription tier details
    struct SubscriptionTier has store, copy, drop {
        name: String,
        price: u64,
        duration: u64,
    }

    /// Active subscription data
    struct Subscription has store, copy, drop {
        tier_id: u64,
        start_time: u64,
        end_time: u64,
    }

    /// Redemption vault for holding funds
    struct RedemptionVault has key {
        coins: coin::Coin<AptosCoin>,
    }

    /// Upgrade capability
    struct UpgradeCapability has key, store {
        version: u64
    }

    // ============ Events ============

    /// Event emitted when a new outpost is created
    struct OutpostCreatedEvent has drop, store {
        creator: address,
        outpost_address: address,
        name: String,
        price: u64,
        fee_share: u64,
    }

    /// Event emitted when passes are purchased
    struct PassPurchaseEvent has drop, store {
        buyer: address,
        target_or_outpost: address,
        amount: u64,
        price: u64,
        referrer: Option<address>,
    }

    /// Event emitted when passes are sold
    struct PassSellEvent has drop, store {
        seller: address,
        target_or_outpost: address,
        amount: u64,
        price: u64,
    }

    /// Event emitted for subscriptions
    struct SubscriptionEvent has drop, store {
        subscriber: address,
        target_or_outpost: address,
        tier: String,
        duration: u64,
        price: u64,
        referrer: Option<address>,
    }

    /// Event for subscription creation
    struct SubscriptionCreatedEvent has drop, store {
        outpost_addr: address,
        subscriber: address,
        tier_id: u64,
        timestamp: u64
    }

    /// Event for subscription cancellation
    struct SubscriptionCancelledEvent has drop, store {
        outpost_addr: address,
        subscriber: address,
        tier_id: u64,
        timestamp: u64
    }

    /// Event for tier updates
    struct TierUpdatedEvent has drop, store {
        outpost_addr: address,
        tier_id: u64,
        price: u64,
        duration: u64,
        timestamp: u64
    }

    /// Event for outpost subscription configuration updates
    struct OutpostSubscriptionConfigEvent has drop, store {
        outpost_addr: address,
        max_tiers: u64,
        timestamp: u64
    }

    /// Event for protocol fee updates
    struct ProtocolFeeUpdateEvent has drop, store {
        old_fee: u64,
        new_fee: u64,
        fee_type: String,  // Identifies which fee was updated (subscription, pass, referrer)
        timestamp: u64
    }

    // ============ Initialization Functions ============

    /// Initialize the protocol
    public entry fun initialize(admin: &signer) {
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_ADMIN));
        
        if (!exists<Config>(@podium)) {
            // Create collection
            let constructor_ref = collection::create_unlimited_collection(
                admin,
                string::utf8(COLLECTION_DESCRIPTION_BYTES),
                string::utf8(COLLECTION_NAME_BYTES),
                option::none(),
                string::utf8(COLLECTION_URI_BYTES),
            );

            let collection_addr = object::address_from_constructor_ref(&constructor_ref);

            // Initialize main config
            move_to(admin, Config {
                protocol_fee_percent: MAX_PROTOCOL_FEE_PERCENT,
                subject_fee_percent: MAX_SUBJECT_FEE_PERCENT,
                referral_fee_percent: MAX_REFERRAL_FEE_PERCENT,
                protocol_subscription_fee: 500,  // 5% default
                protocol_pass_fee: 250,         // 2.5% default
                referrer_fee: 1000,            // 10% default
                treasury: @podium,
                weight_a: DEFAULT_WEIGHT_A,
                weight_b: DEFAULT_WEIGHT_B,
                weight_c: DEFAULT_WEIGHT_C,
                collection_addr,
                outposts: table::new(),
                pass_stats: table::new(),
                subscription_configs: table::new(),
                pass_purchase_events: account::new_event_handle<PassPurchaseEvent>(admin),
                pass_sell_events: account::new_event_handle<PassSellEvent>(admin),
                subscription_events: account::new_event_handle<SubscriptionEvent>(admin),
                subscription_created_events: account::new_event_handle<SubscriptionCreatedEvent>(admin),
                subscription_cancelled_events: account::new_event_handle<SubscriptionCancelledEvent>(admin),
                tier_updated_events: account::new_event_handle<TierUpdatedEvent>(admin),
                outpost_config_events: account::new_event_handle<OutpostSubscriptionConfigEvent>(admin),
                fee_update_events: account::new_event_handle<ProtocolFeeUpdateEvent>(admin),
                outpost_created_events: account::new_event_handle<OutpostCreatedEvent>(admin),
                outpost_price: 1000,
            });

            // Initialize asset capabilities
            move_to(admin, AssetCapabilities {
                mint_refs: table::new(),
                burn_refs: table::new(),
                transfer_refs: table::new(),
                metadata_objects: table::new(),
            });

            // Initialize redemption vault
            move_to(admin, RedemptionVault {
                coins: coin::zero<AptosCoin>()
            });

            // Initialize upgrade capability
            move_to(admin, UpgradeCapability {
                version: 1
            });
        }
    }

    // ============ Outpost Management Functions ============

    /// Creates a new outpost
    public fun create_outpost_internal(
        creator: &signer,
        name: String,
        description: String,
        uri: String,
    ): Object<OutpostData> acquires Config {
        // Verify protocol is initialized
        assert!(exists<Config>(@podium), error::not_found(EPROTOCOL_NOT_INITIALIZED));

        // Verify creator has a valid account
        assert!(account::exists_at(signer::address_of(creator)), error::not_found(EACCOUNT_NOT_REGISTERED));

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
        let config = borrow_global_mut<Config>(@podium);
        let collection_addr = config.collection_addr;
        
        debug::print(&string::utf8(b"Collection address:"));
        debug::print(&collection_addr);

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
        let collection = object::address_to_object<collection::Collection>(collection_addr);
        
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
        table::add(&mut config.outposts, token_addr, token);

        // Emit creation event
        event::emit_event(
            &mut config.outpost_created_events,
            OutpostCreatedEvent {
                creator: signer::address_of(creator),
                outpost_address: token_addr,
                name,
                price: purchase_price,
                fee_share: OUTPOST_FEE_SHARE,
            }
        );

        debug::print(&string::utf8(b"=== Finished create_outpost_internal ==="));
        token
    }

    /// Entry function to create a new outpost
    public entry fun create_outpost(
        creator: &signer,
        name: String,
        description: String,
        uri: String,
    ) acquires Config {
        let _outpost = create_outpost_internal(creator, name, description, uri);
    }

    /// Creates a new token with a deterministic address
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

    /// Update outpost price (owner only)
    public entry fun update_outpost_price(
        owner: &signer,
        outpost: Object<OutpostData>,
        new_price: u64,
    ) acquires OutpostData {
        // Validate owner
        assert!(object::is_owner(outpost, signer::address_of(owner)), error::permission_denied(ENOT_OWNER));
        assert!(new_price > 0, error::invalid_argument(EINVALID_PRICE));
        
        let outpost_data = borrow_global_mut<OutpostData>(object::object_address(&outpost));
        
        // Validate state
        assert!(!outpost_data.emergency_pause, error::invalid_state(EEMERGENCY_PAUSE));

        outpost_data.price = new_price;
    }

    /// Toggle emergency pause (owner only)
    public entry fun toggle_emergency_pause(
        owner: &signer,
        outpost: Object<OutpostData>,
    ) acquires OutpostData {
        assert!(object::is_owner(outpost, signer::address_of(owner)), error::permission_denied(ENOT_OWNER));
        
        let outpost_data = borrow_global_mut<OutpostData>(object::object_address(&outpost));
        outpost_data.emergency_pause = !outpost_data.emergency_pause;
    }

    // ============ Pass Token Management Functions ============

    /// Mint new passes
    public fun mint_pass(
        creator: &signer,
        asset_symbol: String,
        amount: u64
    ): FungibleAsset acquires AssetCapabilities {
        let caps = borrow_global<AssetCapabilities>(@podium);
        let mint_ref = table::borrow(&caps.mint_refs, asset_symbol);
        fungible_asset::mint(mint_ref, amount)
    }

    /// Burn passes
    public fun burn_pass(
        owner: &signer,
        asset_symbol: String,
        fa: FungibleAsset
    ) acquires AssetCapabilities {
        let caps = borrow_global<AssetCapabilities>(@podium);
        let burn_ref = table::borrow(&caps.burn_refs, asset_symbol);
        fungible_asset::burn(burn_ref, fa);
    }

    /// Transfer passes between accounts
    public fun transfer_pass(
        from: &signer,
        to: address,
        asset_symbol: String,
        amount: u64
    ) acquires AssetCapabilities {
        let caps = borrow_global<AssetCapabilities>(@podium);
        let metadata = table::borrow(&caps.metadata_objects, asset_symbol);
        primary_fungible_store::transfer(from, *metadata, to, amount);
    }

    // ============ Pass Trading & Bonding Curve Functions ============

    /// Calculates total buy price including all fees and referral bonus
    /// * `target_addr` - The target address for the pass
    /// * `amount` - Amount of passes to buy
    /// * `referrer` - Optional referrer address
    /// * Returns (price, protocol_fee, subject_fee, referral_fee)
    #[view]
    public fun calculate_buy_price_with_fees(
        target_addr: address,
        amount: u64,
        referrer: Option<address>
    ): (u64, u64, u64, u64) acquires Config {
        // Get current supply
        let current_supply = get_total_supply(target_addr);
        
        // Get raw price from bonding curve
        let price = calculate_price(current_supply, amount, false);
        
        // Calculate fees using basis points (BPS = 10000)
        let config = borrow_global<Config>(@podium);
        let protocol_fee = (price * config.protocol_fee_percent) / BPS;
        let subject_fee = (price * config.subject_fee_percent) / BPS;
        let referral_fee = if (option::is_some(&referrer)) {
            (price * config.referral_fee_percent) / BPS
        } else {
            0
        };
        
        (price, protocol_fee, subject_fee, referral_fee)
    }

    /// Calculates sell price and fees when selling passes
    /// * `target_addr` - The target address for the pass
    /// * `amount` - Amount of passes to sell
    /// * Returns (amount_received, protocol_fee, subject_fee)
    #[view]
    public fun calculate_sell_price_with_fees(
        target_addr: address,
        amount: u64
    ): (u64, u64, u64) acquires Config {
        // Get current supply
        let current_supply = get_total_supply(target_addr);
        
        // Basic validations matching Solidity
        if (current_supply == 0 || amount == 0 || current_supply < amount) {
            return (0, 0, 0)
        };

        // Get raw price from bonding curve
        // For sells, we calculate based on the supply AFTER the sell
        let price = calculate_price(current_supply - amount, amount, true);
        
        // Calculate fees based on total price using basis points
        let config = borrow_global<Config>(@podium);
        let protocol_fee = (price * config.protocol_fee_percent) / BPS;
        let subject_fee = (price * config.subject_fee_percent) / BPS;
        
        // Add debug prints
        debug::print(&string::utf8(b"[calculate_sell_price_with_fees] Calculation:"));
        debug::print(&string::utf8(b"Current supply:"));
        debug::print(&current_supply);
        debug::print(&string::utf8(b"Amount to sell:"));
        debug::print(&amount);
        debug::print(&string::utf8(b"Raw price:"));
        debug::print(&price);
        debug::print(&string::utf8(b"Protocol fee:"));
        debug::print(&protocol_fee);
        debug::print(&string::utf8(b"Subject fee:"));
        debug::print(&subject_fee);
        
        // Return raw price and fees
        (price, protocol_fee, subject_fee)
    }

    /// Calculates price using bonding curve
    /// * `supply` - Current supply of passes (in actual units, e.g., 1 = one pass)
    /// * `amount` - Amount of passes to buy/sell (in actual units)
    /// * `is_sell` - Whether this is a sell operation
    /// * Returns the calculated price in OCTA units (scaled for APT)
    #[view]
    public fun calculate_price(supply: u64, amount: u64, is_sell: bool): u64 {
        debug::print(&string::utf8(b"=== Starting price calculation ==="));
        debug::print(&string::utf8(b"Input parameters:"));
        debug::print(&string::utf8(b"Supply (actual units):"));
        debug::print(&supply);
        debug::print(&string::utf8(b"Amount (actual units):"));
        debug::print(&amount);
        debug::print(&string::utf8(b"Is sell:"));
        debug::print(&is_sell);

        let total_price = 0;
        let i = 0;
        
        while (i < amount) {
            // For buys: calculate price at current supply level
            // For sells: calculate price at current supply level - 1
            // This ensures buying the Nth pass costs the same as selling the Nth pass
            let current_supply = if (is_sell) {
                // Prevent underflow for sells
                if (supply <= i + 1) {
                    0  // Return initial price for selling last pass
                } else {
                    supply - i - 1  // When selling, we look at price at supply-1
                }
            } else {
                supply + i      // When buying, we look at price at current supply
            };
            
            // Calculate price for this single pass
            let pass_price = calculate_single_pass_price(current_supply);
            total_price = total_price + pass_price;
            
            i = i + 1;
        };
        
        debug::print(&string::utf8(b"=== Final total price calculated ==="));
        debug::print(&total_price);
        total_price
    }

    /// Calculate price for a single pass at a given supply level
    /// * `supply` - Current supply of passes (in actual units)
    /// * Returns the calculated price in OCTA units (scaled for APT)
    #[view]
    public fun calculate_single_pass_price(supply: u64): u64 {
        // Early return for first purchase
        if (supply == 0) {
            debug::print(&string::utf8(b"First purchase - returning initial price"));
            return INITIAL_PRICE
        };

        // Calculate n = s + c - 1
        let s_plus_c = supply + DEFAULT_WEIGHT_C;
        if (s_plus_c <= 1) {
            debug::print(&string::utf8(b"Supply + C <= 1 - returning initial price"));
            return INITIAL_PRICE
        };
        let n = s_plus_c - 1;

        // Calculate summation at this supply level
        let s = calculate_summation(n);

        // Apply weights directly without scaling
        let weighted_a = (s * DEFAULT_WEIGHT_A) / BPS;
        let weighted_b = (weighted_a * DEFAULT_WEIGHT_B) / BPS;

        // Scale to OCTA
        let price = weighted_b * OCTA;

        // Return at least initial price
        if (price < INITIAL_PRICE) {
            INITIAL_PRICE
        } else {
            price
        }
    }

    /// Helper function to calculate summation term: (n * (n + 1) * (2n + 1)) / 6
    /// This calculates the area under the curve from 0 to n
    /// We use strategic factoring and intermediate steps to prevent overflow while maintaining precision
    fun calculate_summation(n: u64): u64 {
        if (n == 0) {
            return 0
        };

      

        // First, handle 2n + 1
        let two_n = 2 * n;  // This won't overflow as n is u64
        let two_n_plus_1 = two_n + 1;
        
        // Now we need to calculate (n * (n + 1) * (2n + 1)) / 6
        // To prevent overflow, we can factor this as:
        // n * ((n + 1) * (2n + 1)) / 6
        // = n * (2n^2 + 3n + 1) / 6
        
        // Calculate (n + 1) * (2n + 1) = 2n^2 + 3n + 1
        // Do this in steps to prevent overflow
        let n_squared = n * n;
        let two_n_squared = 2 * n_squared;
        let three_n = 3 * n;
        
        // 2n^2 + 3n + 1
        let inner_sum = two_n_squared + three_n + 1;
        
        // Finally multiply by n and divide by 6
        // To minimize precision loss, we:
        // 1. First check if inner_sum is divisible by 2 or 3
        // 2. Apply those divisions first before multiplying by n
        // 3. Then apply remaining division
        
        let mut_inner_sum = inner_sum;
        let mut_n = n;
        let mut_result = 0;
        
        // Try to divide by 2 first if possible
        if (mut_inner_sum % 2 == 0) {
            mut_inner_sum = mut_inner_sum / 2;
        } else if (mut_n % 2 == 0) {
            mut_n = mut_n / 2;
        };
        
        // Try to divide by 3 if possible
        if (mut_inner_sum % 3 == 0) {
            mut_inner_sum = mut_inner_sum / 3;
        } else if (mut_n % 3 == 0) {
            mut_n = mut_n / 3;
        };
        
        // Now multiply remaining terms
        mut_result = mut_n * mut_inner_sum;
        
        // Apply any remaining divisions needed
        if (inner_sum % 2 != 0 && n % 2 != 0) {
            mut_result = mut_result / 2;
        };
        if (inner_sum % 3 != 0 && n % 3 != 0) {
            mut_result = mut_result / 3;
        };

        
        mut_result
    }

    /// Buy passes with automatic target asset creation
    public entry fun buy_pass(
        buyer: &signer,
        target_addr: address,
        amount: u64,  // amount in interface units (1 = one whole pass)
        referrer: Option<address>
    ) acquires Config, RedemptionVault, AssetCapabilities {
        // Validate amount is a whole number
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        
        // Get current supply in interface units
        let current_supply = get_total_supply(target_addr);
        
        // Initialize pass stats if needed
        init_pass_stats(target_addr);
        
        // Get or create the target asset
        let asset_symbol = get_asset_symbol(target_addr);
        let caps = borrow_global<AssetCapabilities>(@podium);
        if (!table::contains(&caps.metadata_objects, asset_symbol)) {
            // Auto-create target asset with default metadata
            let name = string::utf8(b"Pass Token for ");
            string::append(&mut name, asset_symbol);
            create_pass_token(
                buyer,
                target_addr,
                name,
                string::utf8(b"Automatically created pass token"),
                string::utf8(b"https://podium.fi/pass/") // Default URI
            );
        };
        
        // Calculate prices and fees with interface units
        let (base_price, protocol_fee, subject_fee, referral_fee) = 
            calculate_buy_price_with_fees(target_addr, amount, referrer);
        let total_payment_required = base_price + protocol_fee + subject_fee + referral_fee;
        
        // Debug prints for tracking
        debug::print(&string::utf8(b"[buy_pass] Details:"));
        debug::print(&string::utf8(b"Amount (interface/internal units):"));
        debug::print(&amount);
        debug::print(&string::utf8(b"Total cost (OCTA):"));
        debug::print(&total_payment_required);
        
        // Withdraw full payment from buyer
        let payment_coins = coin::withdraw<AptosCoin>(buyer, total_payment_required);
        
        // Extract base price for redemption pool
        let redemption_coins = coin::extract(&mut payment_coins, base_price);
        deposit_to_vault(redemption_coins);
        
        // Handle fee distributions
        let config = borrow_global<Config>(@podium);
        
        // Protocol fee to treasury
        if (protocol_fee > 0) {
            let protocol_coins = coin::extract(&mut payment_coins, protocol_fee);
            if (!coin::is_account_registered<AptosCoin>(config.treasury)) {
                aptos_account::create_account(config.treasury);
            };
            coin::deposit(config.treasury, protocol_coins);
        };
        
        // Subject fee to target
        if (subject_fee > 0) {
            let subject_coins = coin::extract(&mut payment_coins, subject_fee);
            if (!coin::is_account_registered<AptosCoin>(target_addr)) {
                aptos_account::create_account(target_addr);
            };
            coin::deposit(target_addr, subject_coins);
        };
        
        // Referral fee if applicable
        if (referral_fee > 0 && option::is_some(&referrer)) {
            let referrer_addr = option::extract(&mut referrer);
            let referral_coins = coin::extract(&mut payment_coins, referral_fee);
            if (!coin::is_account_registered<AptosCoin>(referrer_addr)) {
                aptos_account::create_account(referrer_addr);
            };
            coin::deposit(referrer_addr, referral_coins);
        };
        
        // Any remaining dust goes to treasury
        coin::deposit(config.treasury, payment_coins);
        
        // Mint and transfer passes using internal units
        let asset_symbol = get_asset_symbol(target_addr);
        let fa = mint_pass(buyer, asset_symbol, amount);
        primary_fungible_store::deposit(signer::address_of(buyer), fa);
        
        // Update stats with interface units
        update_stats(target_addr, amount, base_price, false);
        
        // Emit purchase event with interface units
        emit_purchase_event(signer::address_of(buyer), target_addr, amount, base_price, referrer);
    }

    /// Sell passes
    public entry fun sell_pass(
        seller: &signer,
        target_addr: address,
        amount: u64  // amount in interface units (1 = one whole pass)
    ) acquires Config, RedemptionVault, AssetCapabilities {
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        
        // Calculate sell price and fees using interface units
        let (base_price, protocol_fee, subject_fee) = 
            calculate_sell_price_with_fees(target_addr, amount);
        let amount_received = base_price - protocol_fee - subject_fee;
        assert!(amount_received > 0, error::invalid_argument(EINVALID_AMOUNT));
        
        // Debug prints for tracking
        debug::print(&string::utf8(b"[sell_pass] Details:"));
        debug::print(&string::utf8(b"Amount (interface/internal units):"));
        debug::print(&amount);
        debug::print(&string::utf8(b"Amount received (OCTA):"));
        debug::print(&amount_received);
        
        // Get asset symbol and burn the passes using internal units
        let asset_symbol = get_asset_symbol(target_addr);
        let caps = borrow_global<AssetCapabilities>(@podium);
        let metadata = table::borrow(&caps.metadata_objects, asset_symbol);
        let fa = primary_fungible_store::withdraw(seller, *metadata, amount);
        burn_pass(seller, asset_symbol, fa);
        
        // Withdraw from redemption vault
        let vault = borrow_global_mut<RedemptionVault>(@podium);
        debug::print(&string::utf8(b"[vault] Attempting withdrawal from vault:"));
        debug::print(&base_price);
        debug::print(&string::utf8(b"[vault] Current vault balance:"));
        debug::print(&coin::value(&vault.coins));
        
        let total_payment = coin::extract<AptosCoin>(&mut vault.coins, base_price);
        
        // Protocol fee payment
        if (protocol_fee > 0) {
            assert!(
                coin::is_account_registered<AptosCoin>(@podium),
                error::not_found(EACCOUNT_NOT_REGISTERED)
            );
            coin::deposit(@podium, coin::extract(&mut total_payment, protocol_fee));
        };
        
        // Subject fee payment
        if (subject_fee > 0) {
            assert!(
                coin::is_account_registered<AptosCoin>(target_addr),
                error::not_found(EACCOUNT_NOT_REGISTERED)
            );
            coin::deposit(target_addr, coin::extract(&mut total_payment, subject_fee));
        };
        
        // Seller payment (remaining amount)
        let seller_addr = signer::address_of(seller);
        assert!(
            coin::is_account_registered<AptosCoin>(seller_addr),
            error::not_found(EACCOUNT_NOT_REGISTERED)
        );
        coin::deposit(seller_addr, total_payment);
        
        // Update stats with interface units
        update_stats(target_addr, amount, base_price, true);
        
        // Emit sell event with interface units
        emit_sell_event(seller_addr, target_addr, amount, amount_received);
    }

    // ============ Vault Management Functions ============

    /// Deposit coins into vault
    fun deposit_to_vault(coins: coin::Coin<AptosCoin>) acquires RedemptionVault {
        let vault = borrow_global_mut<RedemptionVault>(@podium);
        let deposit_amount = coin::value(&coins);
        debug::print(&string::utf8(b"[vault] Depositing to redemption vault:"));
        debug::print(&deposit_amount);
        let previous_balance = coin::value(&vault.coins);
        debug::print(&string::utf8(b"[vault] Previous vault balance:"));
        debug::print(&previous_balance);
        
        coin::merge(&mut vault.coins, coins);
        
        let new_balance = coin::value(&vault.coins);
        debug::print(&string::utf8(b"[vault] New vault balance:"));
        debug::print(&new_balance);
    }

    /// Withdraw coins from vault
    fun withdraw_from_vault(amount: u64): coin::Coin<AptosCoin> acquires RedemptionVault {
        let vault = borrow_global_mut<RedemptionVault>(@podium);
        let current_balance = coin::value(&vault.coins);
        debug::print(&string::utf8(b"[vault] Attempting withdrawal from vault:"));
        debug::print(&amount);
        debug::print(&string::utf8(b"[vault] Current vault balance:"));
        debug::print(&current_balance);
        
        assert!(current_balance >= amount, error::invalid_state(EINSUFFICIENT_BALANCE));
        coin::extract(&mut vault.coins, amount)
    }

    // ============ Additional Helper Functions ============

    /// Initialize pass stats
    fun init_pass_stats(target_addr: address) acquires Config {
        let config = borrow_global_mut<Config>(@podium);
        if (!table::contains(&config.pass_stats, target_addr)) {
            table::add(&mut config.pass_stats, target_addr, PassStats {
                total_supply: 0,
                last_price: INITIAL_PRICE
            });
        };
    }

    /// Get total supply
    fun get_total_supply(target_addr: address): u64 acquires Config {
        let config = borrow_global<Config>(@podium);
        if (!table::contains(&config.pass_stats, target_addr)) {
            return 0
        };
        table::borrow(&config.pass_stats, target_addr).total_supply
    }

    /// Update pass stats
    fun update_stats(target_addr: address, amount: u64, price: u64, is_sell: bool) acquires Config {
        let config = borrow_global_mut<Config>(@podium);
        if (!table::contains(&config.pass_stats, target_addr)) {
            table::add(&mut config.pass_stats, target_addr, PassStats {
                total_supply: 0,
                last_price: INITIAL_PRICE
            });
        };
        let stats = table::borrow_mut(&mut config.pass_stats, target_addr);
        if (is_sell) {
            stats.total_supply = stats.total_supply - amount;
        } else {
            stats.total_supply = stats.total_supply + amount;
        };
        stats.last_price = price;
    }

    /// Get asset symbol for a target/outpost
    public fun get_asset_symbol(target: address): String {
        debug::print(&string::utf8(b"[get_asset_symbol] Creating symbol"));
        // Create a prefix for the symbol
        let symbol = string::utf8(b"P");
        
        // Convert address to bytes and take first few bytes
        let addr_bytes = bcs::to_bytes(&target);
        let len = vector::length<u8>(&addr_bytes);
        let take_bytes = if (len > 3) 3 else len;
        
        // Convert bytes to hex string and append
        let hex_chars = b"0123456789ABCDEF";
        let i = 0;
        while (i < take_bytes) {
            let byte = *vector::borrow(&addr_bytes, i);
            let hi = byte >> 4;
            let lo = byte & 0xF;
            let hi_char = vector::singleton(*vector::borrow(&hex_chars, (hi as u64)));
            let lo_char = vector::singleton(*vector::borrow(&hex_chars, (lo as u64)));
            string::append(&mut symbol, string::utf8(hi_char));
            string::append(&mut symbol, string::utf8(lo_char));
            i = i + 1;
        };
        
        debug::print(&string::utf8(b"Generated symbol:"));
        debug::print(&symbol);
        symbol
    }

    /// Get asset symbol from string
    public fun get_asset_symbol_from_string(target_id: String): String {
        debug::print(&string::utf8(b"[get_asset_symbol] Creating symbol"));
        let symbol = string::utf8(b"T1");
        debug::print(&string::utf8(b"Generated symbol:"));
        debug::print(&symbol);
        symbol
    }

    /// Get metadata object address
    fun get_metadata_object_address(asset_symbol: String): address acquires AssetCapabilities {
        let caps = borrow_global<AssetCapabilities>(@podium);
        assert!(table::contains(&caps.metadata_objects, asset_symbol), error::not_found(EPASS_NOT_FOUND));
        
        let metadata = table::borrow(&caps.metadata_objects, asset_symbol);
        object::object_address(metadata)
    }

    /// Safely transfer coins with recipient account verification
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

    /// Emit purchase event
    fun emit_purchase_event(
        buyer_addr: address,
        target_addr: address,
        amount: u64,
        price: u64,
        referrer: Option<address>
    ) acquires Config {
        event::emit_event(
            &mut borrow_global_mut<Config>(@podium).pass_purchase_events,
            PassPurchaseEvent {
                buyer: buyer_addr,
                target_or_outpost: target_addr,
                amount,
                price,
                referrer,
            },
        );
    }

    /// Emit sell event
    fun emit_sell_event(
        seller_addr: address,
        target_addr: address,
        amount: u64,
        amount_received: u64
    ) acquires Config {
        event::emit_event(
            &mut borrow_global_mut<Config>(@podium).pass_sell_events,
            PassSellEvent {
                seller: seller_addr,
                target_or_outpost: target_addr,
                amount,
                price: amount_received,
            },
        );
    }

    // ============ Helper Functions ============

    /// Get collection name
    #[view]
    public fun get_collection_name(): String {
        string::utf8(COLLECTION_NAME_BYTES)
    }

    /// Get outpost purchase price
    #[view]
    public fun get_outpost_purchase_price(): u64 acquires Config {
        borrow_global<Config>(@podium).outpost_price
    }

    /// Verify outpost ownership
    #[view]
    public fun verify_ownership(outpost: Object<OutpostData>, owner: address): bool {
        object::is_owner(outpost, owner)
    }

    /// Check if an object has outpost data
    #[view]
    public fun has_outpost_data(outpost: Object<OutpostData>): bool {
        exists<OutpostData>(object::object_address(&outpost))
    }

    // ============ Subscription Management Functions ============

    /// Initialize subscription configuration for an outpost
    public fun init_subscription_config(
        creator: &signer,
        outpost: Object<OutpostData>
    ) acquires Config {
        let outpost_addr = object::object_address(&outpost);
        
        // Verify ownership
        assert!(verify_ownership(outpost, signer::address_of(creator)), 
            error::permission_denied(ENOT_OWNER));
        
        // Initialize subscription config
        let config = borrow_global_mut<Config>(@podium);
        if (!table::contains(&config.subscription_configs, outpost_addr)) {
            table::add(&mut config.subscription_configs, outpost_addr, SubscriptionConfig {
                tiers: vector::empty(),
                subscriptions: table::new(),
                max_tiers: 0,
            });
        };
    }

    /// Create subscription tier
    public fun create_subscription_tier(
        creator: &signer,
        outpost: Object<OutpostData>,
        tier_name: String,
        price: u64,
        duration: u64,
    ) acquires Config {
        let outpost_addr = object::object_address(&outpost);
        debug::print(&string::utf8(b"[create_subscription_tier] Outpost address:"));
        debug::print(&outpost_addr);
        debug::print(&string::utf8(b"[create_subscription_tier] Creator address:"));
        debug::print(&signer::address_of(creator));
        
        assert!(verify_ownership(outpost, signer::address_of(creator)), error::permission_denied(ENOT_OWNER));
        debug::print(&string::utf8(b"[create_subscription_tier] Ownership verified"));
        
        let config = borrow_global_mut<Config>(@podium);
        debug::print(&string::utf8(b"[create_subscription_tier] Checking if config exists..."));
        assert!(table::contains(&config.subscription_configs, outpost_addr), error::not_found(ETIER_NOT_FOUND));
        debug::print(&string::utf8(b"[create_subscription_tier] Config exists"));

        let sub_config = table::borrow_mut(&mut config.subscription_configs, outpost_addr);
        debug::print(&string::utf8(b"[create_subscription_tier] Current number of tiers:"));
        debug::print(&vector::length(&sub_config.tiers));
        
        // Verify tier doesn't already exist
        let i = 0;
        let len = vector::length(&sub_config.tiers);
        while (i < len) {
            let tier = vector::borrow(&sub_config.tiers, i);
            assert!(tier.name != tier_name, error::already_exists(ETIER_EXISTS));
            i = i + 1;
        };

        // Add new tier
        vector::push_back(&mut sub_config.tiers, SubscriptionTier {
            name: tier_name,
            price,
            duration,
        });

        // Emit tier updated event
        event::emit_event(
            &mut config.tier_updated_events,
            TierUpdatedEvent {
                outpost_addr,
                tier_id: len, // New tier ID is the previous length
                price,
                duration,
                timestamp: timestamp::now_seconds(),
            }
        );

        debug::print(&string::utf8(b"[create_subscription_tier] Tier added successfully"));
    }

    /// Subscribe to a tier
    public entry fun subscribe(
        subscriber: &signer,
        outpost: Object<OutpostData>,
        tier_id: u64,
        referrer: Option<address>
    ) acquires Config {
        let outpost_addr = object::object_address(&outpost);
        debug::print(&string::utf8(b"[subscribe] Outpost address:"));
        debug::print(&outpost_addr);
        debug::print(&string::utf8(b"[subscribe] Subscriber address:"));
        debug::print(&signer::address_of(subscriber));
        
        let config = borrow_global_mut<Config>(@podium);
        debug::print(&string::utf8(b"[subscribe] Checking if config exists..."));
        assert!(table::contains(&config.subscription_configs, outpost_addr), error::not_found(ETIER_NOT_FOUND));
        debug::print(&string::utf8(b"[subscribe] Config exists"));
        
        let sub_config = table::borrow_mut(&mut config.subscription_configs, outpost_addr);
        let subscriber_addr = signer::address_of(subscriber);

        // Get tier and price
        assert!(tier_id < vector::length(&sub_config.tiers), error::invalid_argument(EINVALID_SUBSCRIPTION_TIER));
        let tier = vector::borrow(&sub_config.tiers, tier_id);
        let price = tier.price;
        let duration = tier.duration;
        let tier_name = tier.name;

        assert!(!table::contains(&sub_config.subscriptions, subscriber_addr), error::already_exists(ESUBSCRIPTION_ALREADY_EXISTS));

        // Handle fee distribution
        let protocol_fee = (price * config.protocol_subscription_fee) / 10000;
        let referral_fee = if (option::is_some(&referrer)) {
            (price * config.referrer_fee) / 10000
        } else {
            0
        };
        // Subject gets everything remaining after protocol and referral fees
        let subject_fee = price - protocol_fee - referral_fee;

        // Transfer fees
        transfer_with_check(subscriber, config.treasury, protocol_fee);
        transfer_with_check(subscriber, outpost_addr, subject_fee);
        if (option::is_some(&referrer)) {
            transfer_with_check(subscriber, option::extract(&mut referrer), referral_fee);
        };

        // Create subscription
        let now = timestamp::now_seconds();
        let end_time = now + get_duration_seconds(duration);
        table::add(&mut sub_config.subscriptions, subscriber_addr, Subscription {
            tier_id,
            start_time: now,
            end_time,
        });

        // Emit events
        event::emit_event(
            &mut config.subscription_events,
            SubscriptionEvent {
                subscriber: subscriber_addr,
                target_or_outpost: outpost_addr,
                tier: tier_name,
                duration,
                price,
                referrer,
            },
        );

        event::emit_event(
            &mut config.subscription_created_events,
            SubscriptionCreatedEvent {
                outpost_addr,
                subscriber: subscriber_addr,
                tier_id,
                timestamp: now,
            }
        );
    }

    /// Cancel subscription
    public entry fun cancel_subscription(
        subscriber: &signer,
        outpost: Object<OutpostData>
    ) acquires Config {
        let outpost_addr = object::object_address(&outpost);
        let subscriber_addr = signer::address_of(subscriber);
        
        // Verify subscription exists
        assert_subscription_exists(outpost_addr);
        
        let config = borrow_global_mut<Config>(@podium);
        let subscription_config = table::borrow_mut(&mut config.subscription_configs, outpost_addr);
        
        // Verify subscriber has an active subscription
        assert!(table::contains(&subscription_config.subscriptions, subscriber_addr), 
            error::not_found(ESUBSCRIPTION_NOT_FOUND));
        
        let subscription = table::remove(&mut subscription_config.subscriptions, subscriber_addr);
        let tier_id = subscription.tier_id;

        // Emit subscription cancelled event
        event::emit_event(
            &mut config.subscription_cancelled_events,
            SubscriptionCancelledEvent {
                outpost_addr,
                subscriber: subscriber_addr,
                tier_id,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Update subscription configuration
    public entry fun update_subscription_config(
        admin: &signer,
        outpost: Object<OutpostData>,
        max_tiers: u64
    ) acquires Config {
        let outpost_addr = object::object_address(&outpost);
        
        // Verify admin
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_ADMIN));
        
        // Verify subscription exists
        assert_subscription_exists(outpost_addr);
        
        let config = borrow_global_mut<Config>(@podium);
        let subscription_config = table::borrow_mut(&mut config.subscription_configs, outpost_addr);
        
        // Update config
        subscription_config.max_tiers = max_tiers;

        // Emit config updated event
        emit_outpost_config_event(outpost_addr, max_tiers);
    }

    /// Verify if a subscription is valid
    #[view]
    public fun verify_subscription(
        subscriber: address,
        outpost: Object<OutpostData>,
        tier_id: u64
    ): bool acquires Config {
        let outpost_addr = object::object_address(&outpost);
        let config = borrow_global<Config>(@podium);
        
        if (!table::contains(&config.subscription_configs, outpost_addr)) {
            return false
        };
        
        let sub_config = table::borrow(&config.subscription_configs, outpost_addr);
        
        if (!table::contains(&sub_config.subscriptions, subscriber)) {
            return false
        };
        
        let subscription = table::borrow(&sub_config.subscriptions, subscriber);
        subscription.tier_id == tier_id && subscription.end_time > timestamp::now_seconds()
    }

    /// Get subscription details
    #[view]
    public fun get_subscription(
        subscriber: address,
        outpost: Object<OutpostData>
    ): (u64, u64, u64) acquires Config {
        let outpost_addr = object::object_address(&outpost);
        let config = borrow_global<Config>(@podium);
        assert!(table::contains(&config.subscription_configs, outpost_addr), error::not_found(ESUBSCRIPTION_NOT_FOUND));
        
        let sub_config = table::borrow(&config.subscription_configs, outpost_addr);
        assert!(table::contains(&sub_config.subscriptions, subscriber), error::not_found(ESUBSCRIPTION_NOT_FOUND));
        
        let subscription = table::borrow(&sub_config.subscriptions, subscriber);
        (subscription.tier_id, subscription.start_time, subscription.end_time)
    }

    // ============ Subscription Helper Functions ============

    /// Convert duration type to seconds
    fun get_duration_seconds(duration_type: u64): u64 {
        if (duration_type == DURATION_WEEK) {
            SECONDS_PER_WEEK
        } else if (duration_type == DURATION_MONTH) {
            SECONDS_PER_MONTH
        } else if (duration_type == DURATION_YEAR) {
            SECONDS_PER_YEAR
        } else {
            abort error::invalid_argument(EINVALID_DURATION)
        }
    }

    /// Verify subscription exists
    fun assert_subscription_exists(outpost_addr: address) acquires Config {
        let config = borrow_global<Config>(@podium);
        assert!(table::contains(&config.subscription_configs, outpost_addr), error::not_found(ESUBSCRIPTION_NOT_FOUND));
    }

    /// Get subscription tier details
    #[view]
    public fun get_tier_details(
        outpost: Object<OutpostData>,
        tier_id: u64
    ): (String, u64, u64) acquires Config {
        let outpost_addr = object::object_address(&outpost);
        let config = borrow_global<Config>(@podium);
        assert!(table::contains(&config.subscription_configs, outpost_addr), error::not_found(ETIER_NOT_FOUND));
        
        let sub_config = table::borrow(&config.subscription_configs, outpost_addr);
        assert!(tier_id < vector::length(&sub_config.tiers), error::invalid_argument(EINVALID_TIER));
        
        let tier = vector::borrow(&sub_config.tiers, tier_id);
        (tier.name, tier.price, tier.duration)
    }

    /// Get number of tiers
    #[view]
    public fun get_tier_count(outpost: Object<OutpostData>): u64 acquires Config {
        let outpost_addr = object::object_address(&outpost);
        let config = borrow_global<Config>(@podium);
        if (!table::contains(&config.subscription_configs, outpost_addr)) {
            return 0
        };
        
        let sub_config = table::borrow(&config.subscription_configs, outpost_addr);
        vector::length(&sub_config.tiers)
    }

    // ============ Upgrade Function ============

    /// Function to upgrade the module
    public entry fun upgrade(
        admin: &signer,
        metadata_serialized: vector<u8>,
        code: vector<vector<u8>>
    ) acquires UpgradeCapability {
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_ADMIN));
        
        let upgrade_cap = borrow_global_mut<UpgradeCapability>(@podium);
        upgrade_cap.version = upgrade_cap.version + 1;
        
        code::publish_package_txn(admin, metadata_serialized, code);
    }

    /// Get balance of passes
    #[view]
    public fun get_balance(owner: address, target: address): u64 acquires AssetCapabilities {
        let asset_symbol = get_asset_symbol(target);
        let caps = borrow_global<AssetCapabilities>(@podium);
        
        // Check if the target's pass token exists
        if (!table::contains(&caps.metadata_objects, asset_symbol)) {
            return 0
        };
        
        let metadata = table::borrow(&caps.metadata_objects, asset_symbol);
        primary_fungible_store::balance(owner, *metadata)
    }

    /// Check if outpost is paused
    #[view]
    public fun is_paused(outpost: Object<OutpostData>): bool acquires OutpostData {
        let outpost_data = borrow_global<OutpostData>(object::object_address(&outpost));
        outpost_data.emergency_pause
    }

    /// Creates a new target asset
    public fun create_target_asset(
        creator: &signer,
        target_id: String,
        name: String,
        description: String,
        icon_uri: String,
        project_uri: String,
    ): Object<Metadata> acquires AssetCapabilities {
        let asset_symbol = get_asset_symbol_from_string(target_id);
        
        // Create metadata object using creator's signer
        let constructor_ref = object::create_named_object(
            creator,
            *string::bytes(&asset_symbol)
        );

        // Initialize the fungible asset with metadata
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(), // No maximum supply
            name,
            asset_symbol,
            DECIMALS,
            icon_uri,
            project_uri,
        );

        // Generate and store capabilities
        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constructor_ref);
        
        let metadata = object::object_from_constructor_ref<Metadata>(&constructor_ref);

        // Store the refs in the creator's account
        let caps = borrow_global_mut<AssetCapabilities>(@podium);
        table::add(&mut caps.mint_refs, asset_symbol, mint_ref);
        table::add(&mut caps.burn_refs, asset_symbol, burn_ref);
        table::add(&mut caps.transfer_refs, asset_symbol, transfer_ref);
        table::add(&mut caps.metadata_objects, asset_symbol, metadata);

        metadata
    }

    /// Creates a new pass token
    public entry fun create_pass_token(
        creator: &signer,
        target_addr: address,
        name: String,
        description: String,
        uri: String,
    ) acquires AssetCapabilities {
        let asset_symbol = get_asset_symbol(target_addr);
        
        // Create metadata object using creator's signer
        let constructor_ref = object::create_named_object(
            creator,
            *string::bytes(&asset_symbol)
        );

        // Initialize the fungible asset with metadata
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(), // No maximum supply
            name,
            asset_symbol,
            DECIMALS,
            uri,
            uri, // Use same URI for both icon and project
        );

        // Generate and store capabilities
        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constructor_ref);
        
        let metadata = object::object_from_constructor_ref<Metadata>(&constructor_ref);

        // Store the refs
        let caps = borrow_global_mut<AssetCapabilities>(@podium);
        table::add(&mut caps.mint_refs, asset_symbol, mint_ref);
        table::add(&mut caps.burn_refs, asset_symbol, burn_ref);
        table::add(&mut caps.transfer_refs, asset_symbol, transfer_ref);
        table::add(&mut caps.metadata_objects, asset_symbol, metadata);
    }

    /// Check if the protocol is initialized
    #[view]
    public fun is_initialized(): bool {
        exists<Config>(@podium)
    }

    // ============ Admin Functions ============

    /// Emit fee update event
    fun emit_fee_update_event(
        old_fee: u64,
        new_fee: u64,
        fee_type: String,
    ) acquires Config {
        event::emit_event(
            &mut borrow_global_mut<Config>(@podium).fee_update_events,
            ProtocolFeeUpdateEvent {
                old_fee,
                new_fee,
                fee_type,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    /// Emit outpost subscription config update event
    fun emit_outpost_config_event(
        outpost_addr: address,
        max_tiers: u64,
    ) acquires Config {
        event::emit_event(
            &mut borrow_global_mut<Config>(@podium).outpost_config_events,
            OutpostSubscriptionConfigEvent {
                outpost_addr,
                max_tiers,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    /// Set protocol subscription fee
    public entry fun update_protocol_subscription_fee(
        admin: &signer,
        new_fee: u64,
    ) acquires Config {
        // Verify admin
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_ADMIN));
        
        // Verify fee is valid
        assert!(new_fee <= MAX_FEE_PERCENTAGE, error::invalid_argument(EINVALID_FEE_VALUE));
        
        // Update fee
        let config = borrow_global_mut<Config>(@podium);
        let old_fee = config.protocol_subscription_fee;
        config.protocol_subscription_fee = new_fee;
        
        // Emit event
        emit_fee_update_event(old_fee, new_fee, string::utf8(b"subscription"));
    }

    /// Set protocol pass fee
    public entry fun update_protocol_pass_fee(
        admin: &signer,
        new_fee: u64,
    ) acquires Config {
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_ADMIN));
        assert!(new_fee <= MAX_FEE_PERCENTAGE, error::invalid_argument(EINVALID_FEE_VALUE));
        
        let config = borrow_global_mut<Config>(@podium);
        let old_fee = config.protocol_pass_fee;
        config.protocol_pass_fee = new_fee;

        // Emit event
        emit_fee_update_event(old_fee, new_fee, string::utf8(b"pass"));
    }

    /// Set referrer fee
    public entry fun update_referrer_fee(
        admin: &signer,
        new_fee: u64,
    ) acquires Config {
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_ADMIN));
        assert!(new_fee <= MAX_FEE_PERCENTAGE, error::invalid_argument(EINVALID_FEE_VALUE));
        
        let config = borrow_global_mut<Config>(@podium);
        let old_fee = config.referrer_fee;
        config.referrer_fee = new_fee;

        // Emit event
        emit_fee_update_event(old_fee, new_fee, string::utf8(b"referrer"));
    }

    /// Get protocol subscription fee
    #[view]
    public fun get_protocol_subscription_fee(): u64 acquires Config {
        borrow_global<Config>(@podium).protocol_subscription_fee
    }

    /// Get protocol pass fee
    #[view]
    public fun get_protocol_pass_fee(): u64 acquires Config {
        borrow_global<Config>(@podium).protocol_pass_fee
    }

    /// Get referrer fee
    #[view]
    public fun get_referrer_fee(): u64 acquires Config {
        borrow_global<Config>(@podium).referrer_fee
    }

    // Getter functions for constants
    #[view]
    public fun get_initial_price(): u64 { INITIAL_PRICE }
    
    #[view]
    public fun get_price_scale(): u64 { INPUT_SCALE }
    
    #[view]
    public fun get_weight_b(): u64 { DEFAULT_WEIGHT_B }
    
    #[view]
    public fun get_weight_c(): u64 { DEFAULT_WEIGHT_C }
}