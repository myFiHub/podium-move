module podium::PodiumPass {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    use aptos_framework::debug;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::table::{Self, Table};
    use aptos_framework::primary_fungible_store;
    use podium::PodiumPassCoin;
    use podium::PodiumOutpost::{Self, OutpostData};
    use aptos_framework::aptos_account;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};

    /// Error codes
    const ENOT_AUTHORIZED: u64 = 1;
    const EINVALID_AMOUNT: u64 = 2;
    const EINVALID_FEE: u64 = 3;
    const EINVALID_DURATION: u64 = 4;
    const EINVALID_TIER: u64 = 5;
    const ESUBSCRIPTION_NOT_FOUND: u64 = 6;
    const ESUBSCRIPTION_EXPIRED: u64 = 7;
    const ETIER_EXISTS: u64 = 8;
    const ETIER_NOT_FOUND: u64 = 9;
    const EINVALID_PRICE: u64 = 10;
    const EINSUFFICIENT_BALANCE: u64 = 11;
    const EPASS_NOT_FOUND: u64 = 12;
    const EINSUFFICIENT_PASS_BALANCE: u64 = 13;
    const INSUFFICIENT_BALANCE: u64 = 14;
    const ENOT_OWNER: u64 = 15;
    const ESUBSCRIPTION_ALREADY_EXISTS: u64 = 16;
    const EINVALID_SUBSCRIPTION_DURATION: u64 = 17;
    const EINVALID_SUBSCRIPTION_TIER: u64 = 18;
    const ENOT_ADMIN: u64 = 19;
    const EINVALID_PASSCOIN_AUTHORITY: u64 = 12;

    /// Fee constants
    const MAX_REFERRAL_FEE_PERCENT: u64 = 2; // 2%
    const MAX_PROTOCOL_FEE_PERCENT: u64 = 4; // 4%
    const MAX_SUBJECT_FEE_PERCENT: u64 = 8; // 8%
    const SELL_DISCOUNT_PERCENT: u64 = 5; // 5% discount on sells
    
    /// Bonding curve constants
    const DEFAULT_WEIGHT_A: u64 = 80; // 80%
    const DEFAULT_WEIGHT_B: u64 = 50; // 50%
    const DEFAULT_WEIGHT_C: u64 = 2;  // Adjustment factor
    const INITIAL_PRICE: u64 = 1; // Initial price in $MOVE

    /// Time constants
    const SECONDS_PER_WEEK: u64 = 7 * 24 * 60 * 60;
    const SECONDS_PER_MONTH: u64 = 30 * 24 * 60 * 60;
    const SECONDS_PER_YEAR: u64 = 365 * 24 * 60 * 60;

    /// Subscription durations
    const DURATION_WEEK: u64 = 1;
    const DURATION_MONTH: u64 = 2;
    const DURATION_YEAR: u64 = 3;

    /// Events
    struct PassPurchaseEvent has drop, store {
        buyer: address,
        target_or_outpost: address,
        amount: u64,
        price: u64,
        referrer: Option<address>,
    }

    struct PassSellEvent has drop, store {
        seller: address,
        target_or_outpost: address,
        amount: u64,
        price: u64,
    }

    struct SubscriptionEvent has drop, store {
        subscriber: address,
        target_or_outpost: address,
        tier: String,
        duration: u64,
        price: u64,
        referrer: Option<address>,
    }

    /// Event emitted when a new subscription is created
    struct SubscriptionCreatedEvent has drop, store {
        outpost_addr: address,
        subscriber: address,
        tier_id: u64,
        timestamp: u64
    }

    /// Event emitted when a subscription is cancelled
    struct SubscriptionCancelledEvent has drop, store {
        outpost_addr: address,
        subscriber: address,
        tier_id: u64,
        timestamp: u64
    }

    /// Event emitted when a subscription tier is updated
    struct TierUpdatedEvent has drop, store {
        outpost_addr: address,
        tier_id: u64,
        price: u64,
        duration: u64,
        timestamp: u64
    }

    /// Event emitted when subscription configuration changes
    struct ConfigUpdatedEvent has drop, store {
        outpost_addr: address,
        max_tiers: u64,
        timestamp: u64
    }

    /// Global configuration
    struct Config has key {
        /// Fee percentages
        protocol_fee_percent: u64,
        subject_fee_percent: u64,
        referral_fee_percent: u64,
        /// Treasury address for protocol fees
        treasury: address,
        /// Bonding curve parameters
        weight_a: u64,
        weight_b: u64,
        weight_c: u64,
        /// Event handles
        pass_purchase_events: EventHandle<PassPurchaseEvent>,
        pass_sell_events: EventHandle<PassSellEvent>,
        subscription_events: EventHandle<SubscriptionEvent>,
        subscription_configs: Table<address, SubscriptionConfig>, // outpost_addr -> config
        subscription_created_events: EventHandle<SubscriptionCreatedEvent>,
        subscription_cancelled_events: EventHandle<SubscriptionCancelledEvent>,
        tier_updated_events: EventHandle<TierUpdatedEvent>,
        config_updated_events: EventHandle<ConfigUpdatedEvent>
    }

    /// Subscription tier configuration
    struct SubscriptionTier has store, copy, drop {
        name: String,
        price: u64,
        duration: u64,
    }

    /// Tracks active subscriptions
    struct Subscription has store, copy, drop {
        tier_id: u64,
        start_time: u64,
        end_time: u64,
    }

    /// Stores subscription data for a target/outpost
    struct SubscriptionConfig has key, store {
        tiers: vector<SubscriptionTier>,
        subscriptions: Table<address, Subscription>, // subscriber -> subscription
        max_tiers: u64,
    }

    /// Tracks pass supply and pricing for targets/outposts
    struct PassStats has key {
        total_supply: u64,
        last_price: u64
    }

    /// Stores fee distribution configuration for a target/outpost
    struct FeeConfig has key {
        subject_address: address,
        referrer_address: Option<address>,
    }

    /// Helper function to get duration value
    public fun get_duration_week(): u64 { DURATION_WEEK }
    public fun get_duration_month(): u64 { DURATION_MONTH }
    public fun get_duration_year(): u64 { DURATION_YEAR }

    #[test_only]
    public fun init_module_for_test(admin: &signer) {
        initialize(admin);
    }

    /// Initialize module with default configuration
    public fun initialize(admin: &signer) {
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_AUTHORIZED));
        
        if (!exists<Config>(@podium)) {
            move_to(admin, Config {
                protocol_fee_percent: MAX_PROTOCOL_FEE_PERCENT,
                subject_fee_percent: MAX_SUBJECT_FEE_PERCENT,
                referral_fee_percent: MAX_REFERRAL_FEE_PERCENT,
                treasury: @podium,
                weight_a: DEFAULT_WEIGHT_A,
                weight_b: DEFAULT_WEIGHT_B,
                weight_c: DEFAULT_WEIGHT_C,
                pass_purchase_events: account::new_event_handle<PassPurchaseEvent>(admin),
                pass_sell_events: account::new_event_handle<PassSellEvent>(admin),
                subscription_events: account::new_event_handle<SubscriptionEvent>(admin),
                subscription_configs: table::new(),
                subscription_created_events: account::new_event_handle<SubscriptionCreatedEvent>(admin),
                subscription_cancelled_events: account::new_event_handle<SubscriptionCancelledEvent>(admin),
                tier_updated_events: account::new_event_handle<TierUpdatedEvent>(admin),
                config_updated_events: account::new_event_handle<ConfigUpdatedEvent>(admin)
            });
        }
    }

    /// Initialize subscription configuration for a target/outpost
    public fun init_subscription_config(creator: &signer, target_or_outpost: Object<OutpostData>) acquires Config {
        let target_addr = object::object_address(&target_or_outpost);
        
        // Verify ownership
        assert!(PodiumOutpost::verify_ownership(target_or_outpost, signer::address_of(creator)), 
            error::permission_denied(ENOT_OWNER));
        
        // Initialize stats if needed
        if (!exists<PassStats>(target_addr)) {
            move_to(creator, PassStats {
                total_supply: 0,
                last_price: INITIAL_PRICE
            });
        };
        
        // Initialize subscription config
        let config = borrow_global_mut<Config>(@podium);
        if (!table::contains(&config.subscription_configs, target_addr)) {
            table::add(&mut config.subscription_configs, target_addr, SubscriptionConfig {
                tiers: vector::empty(),
                subscriptions: table::new(),
                max_tiers: 0,
            });
        };
    }

    /// Calculate price based on bonding curve
    /// price = initial_price * (1 + weight_a * supply^weight_c / weight_b)
    fun calculate_price(supply: u64, is_sell: bool): u64 acquires Config {
        let config = borrow_global<Config>(@podium);
        
        let base_price = INITIAL_PRICE;
        if (supply == 0) {
            base_price
        } else {
            let supply_factor = power(supply, config.weight_c);
            let weight_factor = (config.weight_a * supply_factor) / config.weight_b;
            let price = base_price * (100 + weight_factor) / 100;

            if (is_sell) {
                price * (100 - SELL_DISCOUNT_PERCENT) / 100
            } else {
                price
            }
        }
    }

    /// Helper function for exponentiation
    fun power(base: u64, exp: u64): u64 {
        let result = 1;
        let i = 0;
        while (i < exp) {
            result = result * base;
            i = i + 1;
        };
        result
    }

    /// Create subscription tiers for a target/outpost
    public fun create_subscription_tier(
        creator: &signer,
        target_or_outpost: Object<OutpostData>,
        tier_name: String,
        price: u64,
        duration: u64,
    ) acquires Config {
        let target_addr = object::object_address(&target_or_outpost);
        debug::print(&string::utf8(b"[create_subscription_tier] Target address:"));
        debug::print(&target_addr);
        debug::print(&string::utf8(b"[create_subscription_tier] Creator address:"));
        debug::print(&signer::address_of(creator));
        
        assert!(PodiumOutpost::verify_ownership(target_or_outpost, signer::address_of(creator)), error::permission_denied(ENOT_OWNER));
        debug::print(&string::utf8(b"[create_subscription_tier] Ownership verified"));
        
        let config = borrow_global_mut<Config>(@podium);
        debug::print(&string::utf8(b"[create_subscription_tier] Checking if config exists..."));
        assert!(table::contains(&config.subscription_configs, target_addr), error::not_found(ETIER_NOT_FOUND));
        debug::print(&string::utf8(b"[create_subscription_tier] Config exists"));

        let sub_config = table::borrow_mut(&mut config.subscription_configs, target_addr);
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
        debug::print(&string::utf8(b"[create_subscription_tier] Tier added successfully"));
    }

    /// Verify if a subscription is valid
    public fun verify_subscription(
        subscriber: address,
        target_or_outpost: Object<OutpostData>,
        tier_id: u64
    ): bool acquires Config {
        let target_addr = object::object_address(&target_or_outpost);
        let config = borrow_global<Config>(@podium);
        let sub_config = table::borrow(&config.subscription_configs, target_addr);
        
        if (!table::contains(&sub_config.subscriptions, subscriber)) {
            return false
        };
        
        let subscription = table::borrow(&sub_config.subscriptions, subscriber);
        subscription.tier_id == tier_id && subscription.end_time > timestamp::now_seconds()
    }

    /// Verify pass ownership
    public fun verify_pass_ownership(
        holder: address,
        target_or_outpost: Object<OutpostData>
    ): bool {
        let target_addr = object::object_address(&target_or_outpost);
        let asset_symbol = get_asset_symbol(target_addr);
        PodiumPassCoin::balance(holder, asset_symbol) > 0
    }

    /// Helper function to get asset type and verify ownership
    fun get_asset_type_and_verify(
        target_or_outpost: address,
        owner: address
    ): String {
        if (PodiumOutpost::has_outpost_data(object::address_to_object<OutpostData>(target_or_outpost))) {
            let outpost = PodiumOutpost::get_outpost_from_token_address(target_or_outpost);
            assert!(PodiumOutpost::verify_ownership(outpost, owner), error::permission_denied(ENOT_AUTHORIZED));
            string::utf8(b"outpost")
        } else {
            assert!(target_or_outpost == owner, error::permission_denied(ENOT_AUTHORIZED));
            string::utf8(b"target")
        }
    }

    /// Helper function to get asset symbol
    public fun get_asset_symbol(_target_addr: address): String {
        debug::print(&string::utf8(b"[get_asset_symbol] Creating symbol"));
        let symbol = string::utf8(b"T1");
        debug::print(&string::utf8(b"Generated symbol:"));
        debug::print(&symbol);
        symbol
    }

    /// Safely transfers $MOVE coins with recipient account verification
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

    /// Buy passes for a target/outpost
    public entry fun buy_pass(
        buyer: &signer,
        target_addr: address,
        amount: u64,
        duration: u64,
        referrer: Option<address>
    ) acquires Config, PassStats {
        // Get and verify outpost price (must be valid for outpost to be active)
        let outpost = PodiumOutpost::get_outpost_from_token_address(target_addr);
        let outpost_price = PodiumOutpost::get_price(outpost);
        assert!(outpost_price > 0, error::invalid_argument(EINVALID_PRICE));

        // Calculate price using bonding curve
        let price = calculate_price(get_total_supply(target_addr), false);
        let total_cost = price * duration;

        // Handle payments and fees
        handle_payments(buyer, target_addr, total_cost, referrer);

        // Mint pass directly using PodiumPassCoin
        let asset_symbol = get_asset_symbol(target_addr);
        debug::print(&string::utf8(b"Generated asset symbol:"));
        debug::print(&asset_symbol);

        // Create the asset type if it doesn't exist yet
        if (!PodiumPassCoin::asset_exists(asset_symbol)) {
            PodiumPassCoin::create_target_asset(
                buyer,
                asset_symbol,
                string::utf8(b"Podium Pass"),
                string::utf8(b"https://podium.fi/icon.png"),
                string::utf8(b"https://podium.fi"),
            );
        };

        debug::print(&string::utf8(b"Creating pass with PodiumPassCoin"));

        let fa = PodiumPassCoin::mint(buyer, asset_symbol, duration);
        debug::print(&string::utf8(b"Pass minted successfully"));

        // Transfer to buyer
        let buyer_addr = signer::address_of(buyer);
        debug::print(&string::utf8(b"Transferring to buyer address:"));
        debug::print(&buyer_addr);
        primary_fungible_store::deposit(buyer_addr, fa);
        debug::print(&string::utf8(b"Transfer complete"));

        // Update stats (create if doesn't exist)
        update_stats(target_addr, duration, price);

        // Emit event
        emit_purchase_event(buyer_addr, target_addr, duration, price, referrer);
    }

    // Helper function to get total supply (creates stats if needed)
    fun get_total_supply(target_addr: address): u64 acquires PassStats {
        if (!exists<PassStats>(target_addr)) {
            return 0
        };
        borrow_global<PassStats>(target_addr).total_supply
    }

    // Helper to update stats
    fun update_stats(target_addr: address, amount: u64, price: u64) acquires PassStats {
        if (!exists<PassStats>(target_addr)) {
            // Stats should be initialized during subscription config initialization
            return
        };
        let stats = borrow_global_mut<PassStats>(target_addr);
        stats.total_supply = stats.total_supply + amount;
        stats.last_price = price;
    }

    /// Subscribe to a tier
    public fun subscribe(
        subscriber: &signer,
        target_or_outpost: Object<OutpostData>,
        tier_id: u64,
        referrer: Option<address>
    ) acquires Config {
        let target_addr = object::object_address(&target_or_outpost);
        debug::print(&string::utf8(b"[subscribe] Target address:"));
        debug::print(&target_addr);
        debug::print(&string::utf8(b"[subscribe] Subscriber address:"));
        debug::print(&signer::address_of(subscriber));
        
        let config = borrow_global_mut<Config>(@podium);
        debug::print(&string::utf8(b"[subscribe] Checking if config exists..."));
        assert!(table::contains(&config.subscription_configs, target_addr), error::not_found(ETIER_NOT_FOUND));
        debug::print(&string::utf8(b"[subscribe] Config exists"));
        
        let sub_config = table::borrow_mut(&mut config.subscription_configs, target_addr);
        let subscriber_addr = signer::address_of(subscriber);

        // Get tier and price
        assert!(tier_id < vector::length(&sub_config.tiers), error::invalid_argument(EINVALID_SUBSCRIPTION_TIER));
        let tier = vector::borrow(&sub_config.tiers, tier_id);
        let price = tier.price;
        let duration = tier.duration;
        let tier_name = tier.name;

        assert!(!table::contains(&sub_config.subscriptions, subscriber_addr), error::already_exists(ESUBSCRIPTION_ALREADY_EXISTS));

        // Handle fee distribution
        let protocol_fee = (price * config.protocol_fee_percent) / 100;
        let subject_fee = (price * config.subject_fee_percent) / 100;
        let referral_fee = if (option::is_some(&referrer)) {
            (price * config.referral_fee_percent) / 100
        } else {
            0
        };

        // Transfer fees
        transfer_with_check(subscriber, config.treasury, protocol_fee);
        transfer_with_check(subscriber, target_addr, subject_fee);
        if (option::is_some(&referrer)) {
            transfer_with_check(subscriber, option::extract(&mut referrer), referral_fee);
        };

        // Create subscription
        let now = timestamp::now_seconds();
        table::add(&mut sub_config.subscriptions, subscriber_addr, Subscription {
            tier_id,
            start_time: now,
            end_time: now + duration,
        });

        // Emit events
        event::emit_event(
            &mut config.subscription_events,
            SubscriptionEvent {
                subscriber: subscriber_addr,
                target_or_outpost: target_addr,
                tier: tier_name,
                duration,
                price,
                referrer,
            },
        );

        event::emit_event(
            &mut config.subscription_created_events,
            SubscriptionCreatedEvent {
                outpost_addr: target_addr,
                subscriber: subscriber_addr,
                tier_id,
                timestamp: now,
            }
        );
    }

    /// Sell passes back to the protocol
    public fun sell_pass(
        seller: &signer,
        target_or_outpost: Object<OutpostData>,
        amount: u64
    ) acquires Config, PassStats {
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        
        let target_addr = object::object_address(&target_or_outpost);
        assert!(exists<PassStats>(target_addr), error::not_found(EPASS_NOT_FOUND));

        let pass_config = borrow_global_mut<PassStats>(target_addr);
        assert!(pass_config.total_supply >= amount, error::invalid_argument(EINSUFFICIENT_PASS_BALANCE));

        // Calculate sell price with discount
        let base_price = calculate_price(pass_config.total_supply - amount, true);
        let base_payment = base_price * amount;

        // Calculate fees to be deducted from payment
        let config = borrow_global<Config>(@podium);
        let protocol_fee = (base_payment * config.protocol_fee_percent) / 100;
        let subject_fee = (base_payment * config.subject_fee_percent) / 100;
        
        // No referral fee on sells
        let seller_payment = base_payment - protocol_fee - subject_fee;

        // Burn passes first
        let asset_symbol = get_asset_symbol(target_addr);
        let seller_addr = signer::address_of(seller);
        let fa = PodiumPassCoin::mint(seller, asset_symbol, amount);
        PodiumPassCoin::burn(seller, asset_symbol, fa);

        // Distribute payments from contract's bonding curve funds
        transfer_with_check(seller, config.treasury, protocol_fee);
        transfer_with_check(seller, target_addr, subject_fee);
        transfer_with_check(seller, seller_addr, seller_payment);

        // Update supply and price
        pass_config.total_supply = pass_config.total_supply - amount;
        pass_config.last_price = base_price;

        // Emit event
        event::emit_event(
            &mut borrow_global_mut<Config>(@podium).pass_sell_events,
            PassSellEvent {
                seller: seller_addr,
                target_or_outpost: target_addr,
                amount,
                price: base_price,
            },
        );
    }

    #[test_only]
    public fun assert_pass_balance(
        holder: address,
        target_or_outpost: Object<OutpostData>,
        expected_balance: u64,
    ) {
        let target_addr = object::object_address(&target_or_outpost);
        let asset_symbol = get_asset_symbol(target_addr);
        assert!(PodiumPassCoin::balance(holder, asset_symbol) == expected_balance, 4);
    }

    #[test_only]
    public fun assert_subscription_test(
        subscriber: address,
        target_or_outpost: Object<OutpostData>,
        tier_id: u64,
        expected_duration: u64,
    ) acquires Config {
        let target_addr = object::object_address(&target_or_outpost);
        assert!(exists<SubscriptionConfig>(target_addr), 0);
        
        let config = borrow_global<Config>(@podium);
        let sub_config = table::borrow(&config.subscription_configs, target_addr);
        assert!(table::contains(&sub_config.subscriptions, subscriber), 1);
        
        let subscription = table::borrow(&sub_config.subscriptions, subscriber);
        assert!(subscription.tier_id == tier_id, 2);
        
        let duration = subscription.end_time - subscription.start_time;
        let expected_seconds = if (expected_duration == DURATION_WEEK) {
            SECONDS_PER_WEEK
        } else if (expected_duration == DURATION_MONTH) {
            SECONDS_PER_MONTH
        } else {
            SECONDS_PER_YEAR
        };
        assert!(duration == expected_seconds, 3);
    }

    /// Verify subscription exists
    public fun assert_subscription_exists(target_addr: address) acquires Config {
        let config = borrow_global<Config>(@podium);
        assert!(table::contains(&config.subscription_configs, target_addr), error::not_found(ESUBSCRIPTION_NOT_FOUND));
    }

    /// Update subscription configuration
    public entry fun update_subscription_config(
        admin: &signer,
        outpost_addr: address,
        max_tiers: u64
    ) acquires Config {
        // Verify admin
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_ADMIN));
        
        // Verify subscription exists
        assert_subscription_exists(outpost_addr);
        
        let config = borrow_global_mut<Config>(@podium);
        let subscription_config = table::borrow_mut(&mut config.subscription_configs, outpost_addr);
        
        // Update config
        subscription_config.max_tiers = max_tiers;

        // Emit config updated event
        event::emit_event(
            &mut config.config_updated_events,
            ConfigUpdatedEvent {
                outpost_addr,
                max_tiers,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    public entry fun cancel_subscription(
        subscriber: &signer,
        outpost_addr: address
    ) acquires Config {
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

    /// Add public getter functions
    public fun get_supply(target_addr: address): u64 acquires PassStats {
        borrow_global<PassStats>(target_addr).total_supply
    }

    public fun get_last_price(target_addr: address): u64 acquires PassStats {
        borrow_global<PassStats>(target_addr).last_price
    }

    public fun is_paused(_target_addr: address): bool {
        false
    }

    fun handle_payments(
        buyer: &signer,
        target_addr: address,
        total_cost: u64,
        referrer: Option<address>
    ) acquires Config {
        let config = borrow_global<Config>(@podium);
        
        // Calculate fees
        let protocol_fee = (total_cost * config.protocol_fee_percent) / 100;
        let subject_fee = (total_cost * config.subject_fee_percent) / 100;
        let referral_fee = if (option::is_some(&referrer)) {
            (total_cost * config.referral_fee_percent) / 100
        } else {
            0
        };

        // Transfer protocol fee
        transfer_with_check(buyer, config.treasury, protocol_fee);
        
        // Transfer subject fee
        transfer_with_check(buyer, target_addr, subject_fee);
        
        // Transfer referral fee if applicable
        if (option::is_some(&referrer)) {
            transfer_with_check(buyer, option::extract(&mut referrer), referral_fee);
        };
    }

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

    #[test_only]
    public fun create_asset_for_test(
        creator: &signer,
        target_id: String,
        name: String,
        icon_uri: String,
        project_uri: String,
    ) {
        PodiumPassCoin::create_target_asset(
            creator,
            target_id,
            name,
            icon_uri,
            project_uri,
        )
    }
}
   