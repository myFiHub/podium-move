module 0xYourAddress::PodiumPass {
    use std::string::String;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_framework::account;
    use aptos_framework::signer;
    use 0xYourAddress::PodiumPassCoin;
    use 0xYourAddress::PodiumOutpost;

    // Fee constants
    const MAX_REFERRAL_FEE_PERCENT: u64 = 2; // 2%
    const MAX_PROTOCOL_FEE_PERCENT: u64 = 4; // 4%
    const MAX_SUBJECT_FEE_PERCENT: u64 = 8; // 8%
    const SELL_DISCOUNT_PERCENT: u64 = 5; // 5% discount on sells to prevent arbitrage
    
    // Bonding curve constants
    const DEFAULT_WEIGHT_A: u64 = 80; // 80% in integer form
    const DEFAULT_WEIGHT_B: u64 = 50; // 50% in integer form
    const DEFAULT_WEIGHT_C: u64 = 2;  // Adjustment factor
    const INITIAL_PRICE: u64 = 1; // Initial price per share

    // Time constants
    const SUBSCRIPTION_DURATION: u64 = 30 * 24 * 60 * 60; // 30 days

    // Error codes
    const INSUFFICIENT_BALANCE: u64 = 1;
    const INVALID_VERSION: u64 = 2;
    const NOT_ADMIN: u64 = 3;
    const INVALID_FEE: u64 = 4;
    const NOT_AUTHORIZED: u64 = 5;
    const PAUSED: u64 = 6;

    struct PodiumPassState has key {
        version: u64,
        protocol_fee_percent: u64,
        subject_fee_percent: u64,
        referral_fee_percent: u64,
        protocol_fee_destination: address,
        subscription_registry: vector<SubscriptionRecord>,
        subscription_events: event::EventHandle<SubscriptionEvent>,
        mint_events: event::EventHandle<MintEvent>,
        paused: bool,
        pause_events: event::EventHandle<PauseEvent>,
    }

    struct SubscriptionRecord has store {
        subscriber: address,
        target: address,
        expiration: u64,
        tier: u8,
    }

    struct SubscriptionEvent has drop, store {
        subscriber: address,
        target: address,
        duration: u64,
        price: u64,
        timestamp: u64,
    }

    struct MintEvent has drop, store {
        recipient: address,
        target: address,
        amount: u64,
        tier: u8,
        timestamp: u64,
    }

    // Add new structs for account status
    struct AccountAccess has copy, drop {
        has_lifetime_pass: bool,
        has_subscription: bool,
        subscription_expiry: u64,
        pass_balance: PodiumPassCoin::PassBalance,
        tier: u8,
    }

    // Add new structs for subscription queries
    struct SubscriptionInfo has copy, drop {
        target_address: address,
        tier: u8,
        expiration: u64,
        is_active: bool,
    }

    // Add pause event
    struct PauseEvent has drop, store {
        is_paused: bool,
        timestamp: u64,
    }

    // Initialize the module
    public fun initialize(
        admin: &signer,
        protocol_fee_destination: address,
        protocol_fee_percent: u64,
        subject_fee_percent: u64,
        referral_fee_percent: u64
    ) {
        assert!(protocol_fee_percent <= MAX_PROTOCOL_FEE_PERCENT, INVALID_FEE);
        assert!(subject_fee_percent <= MAX_SUBJECT_FEE_PERCENT, INVALID_FEE);
        assert!(referral_fee_percent <= MAX_REFERRAL_FEE_PERCENT, INVALID_FEE);

        move_to(admin, PodiumPassState {
            version: 1,
            protocol_fee_percent,
            subject_fee_percent,
            referral_fee_percent,
            protocol_fee_destination,
            subscription_registry: vector::empty(),
            subscription_events: account::new_event_handle<SubscriptionEvent>(admin),
            mint_events: account::new_event_handle<MintEvent>(admin),
            paused: false,
            pause_events: account::new_event_handle<PauseEvent>(admin),
        });
    }

    // Add helper to determine if address is an outpost
    fun is_outpost_target(target_addr: address): bool {
        // Try to get outpost owner, if it fails (aborts), it's not an outpost
        option::is_some(&option::try_borrow(&PodiumOutpost::try_get_outpost_owner(target_addr)))
    }

    // Helper to get fee recipient
    fun get_fee_recipient(target_addr: address): address {
        if (is_outpost_target(target_addr)) {
            PodiumOutpost::get_outpost_owner(target_addr)
        } else {
            target_addr // If not an outpost, fees go directly to target
        }
    }

    // Mint lifetime access (creates PodiumPassCoin)
    public entry fun mint_lifetime_access<TargetAddress>(
        admin: &signer,
        recipient: address,
        amount: u64,
        tier: u8
    ) acquires PodiumPassState {
        assert_not_paused();
        let state = borrow_global_mut<PodiumPassState>(@admin);
        
        let base_price = calculate_mint_price(amount);
        let protocol_fee = base_price * state.protocol_fee_percent / 100;
        let subject_fee = base_price * state.subject_fee_percent / 100;
        
        // Transfer protocol fee
        coin::transfer<AptosCoin>(admin, state.protocol_fee_destination, protocol_fee);
        
        // Get target address and determine fee recipient
        let target_addr = type_info::type_of<TargetAddress>().account_address;
        let fee_recipient = get_fee_recipient(target_addr);
        coin::transfer<AptosCoin>(admin, fee_recipient, subject_fee);

        // Mint the pass coins
        PodiumPassCoin::mint_pass<TargetAddress>(admin, recipient, amount, tier);

        // Emit event
        event::emit_event(
            &mut state.mint_events,
            MintEvent {
                recipient,
                target: type_info::type_of<TargetAddress>().account_address,
                amount,
                tier,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    // Create subscription
    public entry fun create_subscription(
        subscriber: &signer,
        target_address: address,
        duration: u64,
        tier: u8
    ) acquires PodiumPassState {
        assert_not_paused();
        let state = borrow_global_mut<PodiumPassState>(@admin);
        let subscriber_addr = signer::address_of(subscriber);

        let price = calculate_subscription_price(duration, tier);
        let protocol_fee = price * state.protocol_fee_percent / 100;
        let subject_fee = price * state.subject_fee_percent / 100;
        
        // Transfer protocol fee
        coin::transfer<AptosCoin>(subscriber, state.protocol_fee_destination, protocol_fee);
        
        // Transfer to appropriate recipient
        let fee_recipient = get_fee_recipient(target_address);
        coin::transfer<AptosCoin>(subscriber, fee_recipient, subject_fee);

        // Create subscription record
        let subscription = SubscriptionRecord {
            subscriber: subscriber_addr,
            target: target_address,
            expiration: timestamp::now_seconds() + duration,
            tier,
        };

        vector::push_back(&mut state.subscription_registry, subscription);

        // Emit event
        event::emit_event(
            &mut state.subscription_events,
            SubscriptionEvent {
                subscriber: subscriber_addr,
                target: target_address,
                duration,
                price,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    // Calculate mint price using bonding curve
    fun calculate_mint_price(amount: u64): u64 {
        let adjusted_supply = amount + DEFAULT_WEIGHT_C;
        
        if (adjusted_supply == 0) {
            return INITIAL_PRICE
        };

        let sum1 = (adjusted_supply - 1) * adjusted_supply * (2 * (adjusted_supply - 1) + 1) / 6;
        let sum2 = (adjusted_supply - 1 + amount) * (adjusted_supply + amount) * (2 * (adjusted_supply - 1 + amount) + 1) / 6;

        let summation = DEFAULT_WEIGHT_A * (sum2 - sum1);
        let price = DEFAULT_WEIGHT_B * summation * INITIAL_PRICE / 100 / 100;

        if (price < INITIAL_PRICE) {
            INITIAL_PRICE
        } else {
            price
        }
    }

    // Calculate subscription price
    fun calculate_subscription_price(duration: u64, tier: u8): u64 {
        let base_price = switch (tier) {
            case 1 => 100,
            case 2 => 200,
            case 3 => 500,
            _ => abort NOT_AUTHORIZED
        };
        
        base_price * (duration / SUBSCRIPTION_DURATION)
    }

    // Verify access (central verification point)
    public fun verify_access(
        user: address,
        target_address: address,
        required_tier: u8
    ): bool acquires PodiumPassState {
        // Check lifetime access
        if (PodiumPassCoin::verify_access<target_address>(user, required_tier)) {
            return true
        };

        // Check subscription
        let state = borrow_global<PodiumPassState>(@admin);
        let i = 0;
        while (i < vector::length(&state.subscription_registry)) {
            let record = vector::borrow(&state.subscription_registry, i);
            if (record.subscriber == user && 
                record.target == target_address &&
                record.tier >= required_tier &&
                record.expiration > timestamp::now_seconds()) {
                return true
            };
            i = i + 1;
        };
        false
    }

    // Add sell price calculation
    fun calculate_sell_price(amount: u64): u64 {
        let adjusted_supply = amount + DEFAULT_WEIGHT_C;
        
        if (adjusted_supply == 0) {
            return INITIAL_PRICE
        };

        // Similar to mint price but calculating price for removing amount
        let sum1 = (adjusted_supply - amount - 1) * (adjusted_supply - amount) * 
                   (2 * (adjusted_supply - amount - 1) + 1) / 6;
        let sum2 = (adjusted_supply - 1) * adjusted_supply * (2 * (adjusted_supply - 1) + 1) / 6;

        let summation = DEFAULT_WEIGHT_A * (sum2 - sum1);
        let price = DEFAULT_WEIGHT_B * summation * INITIAL_PRICE / 100 / 100;

        // Apply sell discount to prevent arbitrage
        price - (price * SELL_DISCOUNT_PERCENT / 100)
    }

    // Add function to sell passes back to the protocol
    public entry fun sell_lifetime_access<TargetAddress>(
        seller: &signer,
        amount: u64
    ) acquires PodiumPassState {
        assert_not_paused();
        let state = borrow_global_mut<PodiumPassState>(@admin);
        let seller_addr = signer::address_of(seller);
        
        let sell_price = calculate_sell_price(amount);
        let protocol_fee = sell_price * state.protocol_fee_percent / 100;
        let subject_fee = sell_price * state.subject_fee_percent / 100;
        let net_price = sell_price - protocol_fee - subject_fee;

        // Burn the pass coins
        PodiumPassCoin::burn_pass<TargetAddress>(seller, amount);

        // Transfer payment to seller
        coin::transfer<AptosCoin>(@treasury, seller_addr, net_price);
        
        // Transfer protocol fee
        coin::transfer<AptosCoin>(@treasury, state.protocol_fee_destination, protocol_fee);
        
        // Transfer subject fee to appropriate recipient
        let target_addr = type_info::type_of<TargetAddress>().account_address;
        let fee_recipient = get_fee_recipient(target_addr);
        coin::transfer<AptosCoin>(@treasury, fee_recipient, subject_fee);

        // Emit sell event
        event::emit_event(
            &mut state.mint_events,
            MintEvent {
                recipient: seller_addr,
                target: type_info::type_of<TargetAddress>().account_address,
                amount,
                tier: PodiumPassCoin::get_pass_tier<TargetAddress>(seller_addr),
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    // Get complete access status for an account
    public fun get_account_status<TargetAddress>(
        account: address
    ): AccountAccess acquires PodiumPassState {
        let pass_balance = PodiumPassCoin::get_pass_balance<TargetAddress>(account);
        let has_lifetime = pass_balance.amount > 0;
        
        let state = borrow_global<PodiumPassState>(@admin);
        let has_subscription = false;
        let subscription_expiry = 0;
        let subscription_tier = 0;

        let i = 0;
        while (i < vector::length(&state.subscription_registry)) {
            let record = vector::borrow(&state.subscription_registry, i);
            if (record.subscriber == account && 
                record.target == type_info::type_of<TargetAddress>().account_address) {
                has_subscription = record.expiration > timestamp::now_seconds();
                subscription_expiry = record.expiration;
                subscription_tier = record.tier;
                break
            };
            i = i + 1;
        };

        AccountAccess {
            has_lifetime_pass: has_lifetime,
            has_subscription,
            subscription_expiry,
            pass_balance,
            tier: if (has_lifetime) {
                pass_balance.tier
            } else if (has_subscription) {
                subscription_tier
            } else {
                0
            },
        }
    }

    // Get all passes and subscriptions for an account
    public fun get_all_access(account: address): vector<AccountAccess> acquires PodiumPassState {
        let holdings = PodiumPassCoin::get_all_pass_holdings(account);
        let accesses = vector::empty<AccountAccess>();

        let i = 0;
        while (i < vector::length(&holdings)) {
            let holding = vector::borrow(&holdings, i);
            vector::push_back(&mut accesses, get_account_status<holding.target_address>(account));
            i = i + 1;
        };

        accesses
    }

    // Get all active subscriptions for an account
    public fun get_account_subscriptions(
        account: address
    ): vector<SubscriptionInfo> acquires PodiumPassState {
        let state = borrow_global<PodiumPassState>(@admin);
        let subscriptions = vector::empty<SubscriptionInfo>();
        let current_time = timestamp::now_seconds();
        
        let i = 0;
        while (i < vector::length(&state.subscription_registry)) {
            let record = vector::borrow(&state.subscription_registry, i);
            if (record.subscriber == account) {
                let is_active = record.expiration > current_time;
                vector::push_back(&mut subscriptions, SubscriptionInfo {
                    target_address: record.target,
                    tier: record.tier,
                    expiration: record.expiration,
                    is_active,
                });
            };
            i = i + 1;
        };
        
        subscriptions
    }

    // Get subscription info for specific target
    public fun get_target_subscription(
        account: address,
        target_address: address
    ): Option<SubscriptionInfo> acquires PodiumPassState {
        let state = borrow_global<PodiumPassState>(@admin);
        let current_time = timestamp::now_seconds();
        
        let i = 0;
        while (i < vector::length(&state.subscription_registry)) {
            let record = vector::borrow(&state.subscription_registry, i);
            if (record.subscriber == account && record.target == target_address) {
                return option::some(SubscriptionInfo {
                    target_address: record.target,
                    tier: record.tier,
                    expiration: record.expiration,
                    is_active: record.expiration > current_time,
                });
            };
            i = i + 1;
        };
        
        option::none()
    }

    // Get all subscribers for a target
    public fun get_target_subscribers(
        target_address: address
    ): vector<address> acquires PodiumPassState {
        let state = borrow_global<PodiumPassState>(@admin);
        let subscribers = vector::empty<address>();
        let current_time = timestamp::now_seconds();
        
        let i = 0;
        while (i < vector::length(&state.subscription_registry)) {
            let record = vector::borrow(&state.subscription_registry, i);
            if (record.target == target_address && record.expiration > current_time) {
                vector::push_back(&mut subscribers, record.subscriber);
            };
            i = i + 1;
        };
        
        subscribers
    }

    // Get complete account status (both passes and subscriptions)
    public fun get_complete_account_status(
        account: address
    ): (vector<PassHolding>, vector<SubscriptionInfo>) acquires PodiumPassState {
        let pass_holdings = PodiumPassCoin::get_all_pass_holdings(account);
        let subscriptions = get_account_subscriptions(account);
        (pass_holdings, subscriptions)
    }

    // Add pause control functions
    public entry fun pause(admin: &signer) acquires PodiumPassState {
        assert!(signer::address_of(admin) == @admin, NOT_ADMIN);
        let state = borrow_global_mut<PodiumPassState>(@admin);
        state.paused = true;
        event::emit_event(&mut state.pause_events, PauseEvent {
            is_paused: true,
            timestamp: timestamp::now_seconds(),
        });
    }

    public entry fun unpause(admin: &signer) acquires PodiumPassState {
        assert!(signer::address_of(admin) == @admin, NOT_ADMIN);
        let state = borrow_global_mut<PodiumPassState>(@admin);
        state.paused = false;
        event::emit_event(&mut state.pause_events, PauseEvent {
            is_paused: false,
            timestamp: timestamp::now_seconds(),
        });
    }

    // Add pause check helper
    fun assert_not_paused() acquires PodiumPassState {
        let state = borrow_global<PodiumPassState>(@admin);
        assert!(!state.paused, PAUSED);
    }
}

