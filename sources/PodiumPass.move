module podium::PodiumPass {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
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
    }

    /// Subscription tier configuration
    struct SubscriptionTier has store, copy, drop {
        name: String,
        week_price: u64,
        month_price: u64,
        year_price: u64,
    }

    /// Tracks active subscriptions
    struct Subscription has store, copy, drop {
        tier: String,
        start_time: u64,
        end_time: u64,
    }

    /// Stores subscription data for a target/outpost
    struct SubscriptionConfig has key {
        tiers: vector<SubscriptionTier>,
        subscriptions: Table<address, Subscription>, // subscriber -> subscription
    }

    /// Tracks pass supply and pricing for targets/outposts
    struct PassConfig has key {
        supply: u64,
        last_price: u64,
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
        init_module(admin)
    }

    /// Initialize module
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @podium, error::permission_denied(ENOT_AUTHORIZED));
        
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
        });
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
        week_price: u64,
        month_price: u64,
        year_price: u64,
    ) acquires SubscriptionConfig {
        let target_addr = object::object_address(&target_or_outpost);
        assert!(PodiumOutpost::verify_ownership(target_or_outpost, signer::address_of(creator)), ENOT_OWNER);

        if (!exists<SubscriptionConfig>(target_addr)) {
            move_to(creator, SubscriptionConfig {
                tiers: vector::empty(),
                subscriptions: table::new(),
            });
        };

        let config = borrow_global_mut<SubscriptionConfig>(target_addr);
        
        // Verify tier doesn't already exist
        let i = 0;
        let len = vector::length(&config.tiers);
        while (i < len) {
            let tier = vector::borrow(&config.tiers, i);
            assert!(tier.name != tier_name, error::already_exists(ETIER_EXISTS));
            i = i + 1;
        };

        // Add new tier
        vector::push_back(&mut config.tiers, SubscriptionTier {
            name: tier_name,
            week_price,
            month_price,
            year_price,
        });
    }

    /// Update an existing subscription tier
    public fun update_subscription_tier(
        admin: &signer,
        target_or_outpost: Object<OutpostData>,
        tier_name: String,
        new_week_price: u64,
        new_month_price: u64,
        new_year_price: u64,
    ) acquires SubscriptionConfig {
        let target_addr = object::object_address(&target_or_outpost);
        assert!(PodiumOutpost::verify_ownership(target_or_outpost, signer::address_of(admin)), ENOT_OWNER);
        assert!(exists<SubscriptionConfig>(target_addr), error::not_found(ETIER_NOT_FOUND));

        let config = borrow_global_mut<SubscriptionConfig>(target_addr);
        let found = false;
        let i = 0;
        let len = vector::length(&config.tiers);
        
        while (i < len) {
            let tier = vector::borrow_mut(&mut config.tiers, i);
            if (tier.name == tier_name) {
                tier.week_price = new_week_price;
                tier.month_price = new_month_price;
                tier.year_price = new_year_price;
                found = true;
                break
            };
            i = i + 1;
        };

        assert!(found, error::not_found(ETIER_NOT_FOUND));
    }

    /// Cancel an active subscription
    public fun cancel_subscription(
        subscriber: &signer,
        target_or_outpost: Object<OutpostData>,
    ) acquires SubscriptionConfig {
        let target_addr = object::object_address(&target_or_outpost);
        let subscriber_addr = signer::address_of(subscriber);
        
        assert!(exists<SubscriptionConfig>(target_addr), error::not_found(ESUBSCRIPTION_NOT_FOUND));
        let config = borrow_global_mut<SubscriptionConfig>(target_addr);
        
        assert!(table::contains(&config.subscriptions, subscriber_addr), error::not_found(ESUBSCRIPTION_NOT_FOUND));
        table::remove(&mut config.subscriptions, subscriber_addr);
    }

    /// Verify if a subscription is valid
    public fun verify_subscription(
        subscriber: address,
        target_or_outpost: Object<OutpostData>,
        tier: String
    ): bool acquires SubscriptionConfig {
        let target_addr = object::object_address(&target_or_outpost);
        if (!exists<SubscriptionConfig>(target_addr)) {
            return false
        };
        
        let config = borrow_global<SubscriptionConfig>(target_addr);
        if (!table::contains(&config.subscriptions, subscriber)) {
            return false
        };
        
        let subscription = table::borrow(&config.subscriptions, subscriber);
        subscription.tier == tier && subscription.end_time > timestamp::now_seconds()
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
    fun get_asset_symbol(target_or_outpost: address): String {
        if (PodiumOutpost::has_outpost_data(object::address_to_object<OutpostData>(target_or_outpost))) {
            string::utf8(b"OUTPOST")
        } else {
            string::utf8(b"TARGET")
        }
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

    /// Buy a pass for a target/outpost
    public fun buy_pass(
        buyer: &signer,
        target_or_outpost: Object<OutpostData>,
        amount: u64,
        referrer: Option<address>
    ) acquires Config, PassConfig {
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        
        let target_addr = object::object_address(&target_or_outpost);
        if (!exists<PassConfig>(target_addr)) {
            move_to(buyer, PassConfig {
                supply: 0,
                last_price: INITIAL_PRICE,
            });
        };

        let pass_config = borrow_global_mut<PassConfig>(target_addr);
        let base_price = calculate_price(pass_config.supply, false);
        let base_cost = base_price * amount;

        // Calculate fees on top of base price
        let config = borrow_global<Config>(@podium);
        let protocol_fee = (base_cost * config.protocol_fee_percent) / 100;
        let subject_fee = (base_cost * config.subject_fee_percent) / 100;
        let referral_fee = if (option::is_some(&referrer)) {
            (base_cost * config.referral_fee_percent) / 100
        } else {
            0
        };

        // Transfer base cost to contract (for bonding curve)
        transfer_with_check(buyer, @podium, base_cost);

        // Transfer fees to respective parties
        transfer_with_check(buyer, config.treasury, protocol_fee);
        transfer_with_check(buyer, target_addr, subject_fee);
        if (option::is_some(&referrer)) {
            transfer_with_check(buyer, option::extract(&mut referrer), referral_fee);
        };

        // Mint pass tokens
        let asset_symbol = get_asset_symbol(target_addr);
        let fa = PodiumPassCoin::mint(buyer, asset_symbol, amount);
        primary_fungible_store::deposit(signer::address_of(buyer), fa);

        // Update supply and price
        pass_config.supply = pass_config.supply + amount;
        pass_config.last_price = base_price;

        // Emit event
        event::emit_event(
            &mut borrow_global_mut<Config>(@podium).pass_purchase_events,
            PassPurchaseEvent {
                buyer: signer::address_of(buyer),
                target_or_outpost: target_addr,
                amount,
                price: base_price,
                referrer,
            },
        );
    }

    /// Subscribe to a tier
    public fun subscribe(
        subscriber: &signer,
        target_or_outpost: Object<OutpostData>,
        tier_name: String,
        duration: u64,
        referrer: Option<address>
    ) acquires Config, SubscriptionConfig {
        let target_addr = object::object_address(&target_or_outpost);
        assert!(exists<SubscriptionConfig>(target_addr), error::not_found(ETIER_NOT_FOUND));
        
        let config = borrow_global_mut<SubscriptionConfig>(target_addr);
        let subscriber_addr = signer::address_of(subscriber);

        // Find tier and price
        let tier_found = false;
        let price = 0u64;
        let i = 0;
        let len = vector::length(&config.tiers);
        
        while (i < len) {
            let tier = vector::borrow(&config.tiers, i);
            if (tier.name == tier_name) {
                price = if (duration == DURATION_WEEK) {
                    tier.week_price
                } else if (duration == DURATION_MONTH) {
                    tier.month_price
                } else if (duration == DURATION_YEAR) {
                    tier.year_price
                } else {
                    abort error::invalid_argument(EINVALID_SUBSCRIPTION_DURATION)
                };
                tier_found = true;
                break
            };
            i = i + 1;
        };

        assert!(tier_found, error::not_found(EINVALID_SUBSCRIPTION_TIER));
        assert!(!table::contains(&config.subscriptions, subscriber_addr), error::already_exists(ESUBSCRIPTION_ALREADY_EXISTS));

        // Handle fee distribution
        let global_config = borrow_global<Config>(@podium);
        let protocol_fee = (price * global_config.protocol_fee_percent) / 100;
        let subject_fee = (price * global_config.subject_fee_percent) / 100;
        let referral_fee = if (option::is_some(&referrer)) {
            (price * global_config.referral_fee_percent) / 100
        } else {
            0
        };

        // Transfer fees
        transfer_with_check(subscriber, global_config.treasury, protocol_fee);
        transfer_with_check(subscriber, target_addr, subject_fee);
        if (option::is_some(&referrer)) {
            transfer_with_check(subscriber, option::extract(&mut referrer), referral_fee);
        };

        // Calculate subscription duration
        let duration_seconds = if (duration == DURATION_WEEK) {
            SECONDS_PER_WEEK
        } else if (duration == DURATION_MONTH) {
            SECONDS_PER_MONTH
        } else {
            SECONDS_PER_YEAR
        };

        // Create subscription
        let now = timestamp::now_seconds();
        table::add(&mut config.subscriptions, subscriber_addr, Subscription {
            tier: tier_name,
            start_time: now,
            end_time: now + duration_seconds,
        });

        // Emit event
        event::emit_event(
            &mut borrow_global_mut<Config>(@podium).subscription_events,
            SubscriptionEvent {
                subscriber: subscriber_addr,
                target_or_outpost: target_addr,
                tier: tier_name,
                duration,
                price,
                referrer,
            },
        );
    }

    /// Sell passes back to the protocol
    public fun sell_pass(
        seller: &signer,
        target_or_outpost: Object<OutpostData>,
        amount: u64
    ) acquires Config, PassConfig {
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        
        let target_addr = object::object_address(&target_or_outpost);
        assert!(exists<PassConfig>(target_addr), error::not_found(EPASS_NOT_FOUND));

        let pass_config = borrow_global_mut<PassConfig>(target_addr);
        assert!(pass_config.supply >= amount, error::invalid_argument(EINSUFFICIENT_PASS_BALANCE));

        // Calculate sell price with discount
        let base_price = calculate_price(pass_config.supply - amount, true);
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
        pass_config.supply = pass_config.supply - amount;
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
    public fun assert_subscription_exists(
        subscriber: address,
        target_or_outpost: Object<OutpostData>,
        expected_tier: String,
        expected_duration: u64,
    ) acquires SubscriptionConfig {
        let target_addr = object::object_address(&target_or_outpost);
        assert!(exists<SubscriptionConfig>(target_addr), 0);
        
        let config = borrow_global<SubscriptionConfig>(target_addr);
        assert!(table::contains(&config.subscriptions, subscriber), 1);
        
        let subscription = table::borrow(&config.subscriptions, subscriber);
        assert!(subscription.tier == expected_tier, 2);
        
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
}
   