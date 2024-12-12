module podium::PodiumPass {
    use std::string::{Self, String};
    use std::signer;
    use std::vector;
    use std::option;
    use std::type_info;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use podium::PodiumPassCoin;
    use podium::PodiumOutpost;

    // Error codes
    const NOT_ADMIN: u64 = 1;
    const PAUSED: u64 = 2;
    const INVALID_AMOUNT: u64 = 3;
    const INSUFFICIENT_BALANCE: u64 = 4;
    const INVALID_DURATION: u64 = 5;
    const INVALID_TIER: u64 = 6;
    const NOT_TARGET_OWNER: u64 = 7;
    const NOT_WHOLE_NUMBER: u64 = 8;
    const SUBSCRIPTION_NOT_FOUND: u64 = 9;
    const SUBSCRIPTION_EXPIRED: u64 = 10;
    const TIER_EXCLUSIVE: u64 = 11;
    const INVALID_PAYMENT: u64 = 12;
    const SUBSCRIPTION_EXISTS: u64 = 13;

    // Fee constants
    const PROTOCOL_FEE: u64 = 100; // 1%
    const SUBJECT_FEE: u64 = 900; // 9%
    const REFERRAL_FEE: u64 = 100; // 1%
    const BPS_DECIMALS: u64 = 10000;

    // Time constants
    const SECONDS_PER_DAY: u64 = 86400; // 24 * 60 * 60
    const MIN_SUBSCRIPTION_DAYS: u64 = 30;
    const MAX_SUBSCRIPTION_DAYS: u64 = 365;

    // Tier constants
    const TIER_BASIC: u64 = 1;
    const TIER_PREMIUM: u64 = 2;
    const TIER_EXCLUSIVE: u64 = 3;

    // State fields
    struct PodiumPassState has key {
        admin: address,
        paused: bool,
        subscription_events: event::EventHandle<SubscriptionEvent>,
        lifetime_events: event::EventHandle<LifetimeEvent>,
        pause_events: event::EventHandle<PauseEvent>,
        fee_events: event::EventHandle<FeeEvent>,
        subscription_registry: vector<SubscriptionRecord>,
        target_configs: vector<TargetConfig>,
        default_tier_prices: vector<u64>,
        protocol_fee: u64,
        subject_fee: u64,
        referral_fee: u64,
        treasury: address
    }

    struct SubscriptionRecord has store, drop, copy {
        target: String,
        subscriber: address,
        purchaser: address,
        start_time: u64,
        end_time: u64,
        tier: u64,
        price_paid: u64
    }

    struct TargetConfig has store, drop {
        owner: address,
        tier_prices: vector<u64>,
        min_subscription_days: u64,
        max_subscription_days: u64
    }

    struct AccountAccess has drop {
        holder: address,
        target: String,
        has_lifetime_access: bool,
        has_subscription: bool,
        tier: u64,
        subscription_end_time: u64,
        lifetime_balance: u64
    }

    struct SubscriptionEvent has store, drop {
        subscriber: address,
        purchaser: address,
        target: address,
        duration: u64,
        tier: u64,
        price: u64,
        timestamp: u64
    }

    struct LifetimeEvent has store, drop {
        recipient: address,
        purchaser: address,
        target: address,
        amount: u64,
        price: u64,
        timestamp: u64
    }

    struct PauseEvent has store, drop {
        is_paused: bool,
        timestamp: u64
    }

    struct FeeEvent has store, drop {
        target: address,
        amount: u64,
        protocol_fee: u64,
        subject_fee: u64,
        referral_fee: u64,
        timestamp: u64
    }

    public fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @admin, NOT_ADMIN);

        // Initialize PodiumPassCoin
        PodiumPassCoin::initialize_target<address>(admin, string::utf8(b"Podium Pass"));

        // Initialize PodiumOutpost
        PodiumOutpost::initialize(admin);

        // Initialize PodiumPass state
        if (!exists<PodiumPassState>(@podium)) {
            move_to(admin, PodiumPassState {
                admin: admin_addr,
                paused: false,
                subscription_events: account::new_event_handle<SubscriptionEvent>(admin),
                lifetime_events: account::new_event_handle<LifetimeEvent>(admin),
                pause_events: account::new_event_handle<PauseEvent>(admin),
                fee_events: account::new_event_handle<FeeEvent>(admin),
                subscription_registry: vector::empty(),
                target_configs: vector::empty(),
                default_tier_prices: vector::empty(),
                protocol_fee: PROTOCOL_FEE,
                subject_fee: SUBJECT_FEE,
                referral_fee: REFERRAL_FEE,
                treasury: @treasury
            });
        };
    }

    // Helper functions
    fun get_target_address<TargetAddress>(): address {
        let type_info = type_info::type_of<TargetAddress>();
        type_info::account_address(&type_info)
    }

    fun get_subscription<TargetAddress>(holder: address): option::Option<SubscriptionRecord> {
        let state = borrow_global<PodiumPassState>(@podium);
        let target = type_info::type_name<TargetAddress>();
        
        let i = 0;
        while (i < vector::length(&state.subscription_registry)) {
            let record = vector::borrow(&state.subscription_registry, i);
            if (record.subscriber == holder && record.target == target) {
                return option::some(*record)
            };
            i = i + 1;
        };
        
        option::none()
    }

    public fun verify_outpost_owner(owner: address, target: address): bool {
        owner == target  // Simple verification, can be enhanced
    }

    public fun get_pass_details(holder: address, target: address): (bool, u64, u64) {
        let pass_balance = PodiumPassCoin::get_pass_balance<address>(holder);
        (
            PodiumPassCoin::get_pass_balance_amount(&pass_balance) > 0,
            PodiumPassCoin::get_pass_balance_amount(&pass_balance),
            0  // Default tier
        )
    }

    // Public getters
    public fun get_protocol_fee(): u64 {
        PROTOCOL_FEE
    }

    public fun get_subject_fee(): u64 {
        SUBJECT_FEE  
    }

    public fun get_referral_fee(): u64 {
        REFERRAL_FEE
    }

    public fun is_paused(): bool acquires PodiumPassState {
        borrow_global<PodiumPassState>(@podium).paused
    }

    public fun get_lifetime_access_status(status: &AccountAccess): bool {
        status.has_lifetime_access
    }

    public fun get_subscription_status(status: &AccountAccess): bool {
        status.has_subscription
    }

    public fun get_subscription_end_time(status: &AccountAccess): u64 {
        status.subscription_end_time
    }

    public fun get_tier(status: &AccountAccess): u64 {
        status.tier
    }

    public fun get_lifetime_balance(status: &AccountAccess): u64 {
        status.lifetime_balance
    }

    // Fix the function signatures to use non-reference types where needed
    public fun purchase_lifetime_access<TargetAddress>(
        purchaser: &signer,
        recipient: address,
        amount: u64,
        payment: Coin<AptosCoin>
    ) acquires PodiumPassState {
        // ... existing implementation ...
    }

    public fun create_subscription<TargetAddress>(
        purchaser: &signer,
        recipient: address,
        duration_days: u64,
        tier: u64,
        payment: Coin<AptosCoin>
    ) acquires PodiumPassState {
        // ... existing implementation ...
    }

    // Add a public getter for pass balance amount that doesn't expose the field
    public fun get_pass_balance_amount(balance: &PodiumPassCoin::PassBalance): u64 {
        PodiumPassCoin::get_pass_balance_amount(balance)
    }

    // Add missing function declarations
    public fun get_account_status<TargetAddress>(holder: address): AccountAccess acquires PodiumPassState {
        let pass_balance = PodiumPassCoin::get_pass_balance<TargetAddress>(holder);
        let subscription = get_subscription<TargetAddress>(holder);
        
        AccountAccess {
            holder,
            target: type_info::type_name<TargetAddress>(),
            has_lifetime_access: PodiumPassCoin::get_pass_balance_amount(&pass_balance) > 0,
            has_subscription: option::is_some(&subscription),
            tier: if (option::is_some(&subscription)) { option::borrow(&subscription).tier } else { 0 },
            subscription_end_time: if (option::is_some(&subscription)) { option::borrow(&subscription).end_time } else { 0 },
            lifetime_balance: PodiumPassCoin::get_pass_balance_amount(&pass_balance)
        }
    }

    public fun has_subscription(status: &AccountAccess): bool {
        status.has_subscription
    }

    // ... rest of the code ...
}

