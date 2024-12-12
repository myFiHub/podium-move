module podium::PodiumPass {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::table::{Self, Table};
    use podium::PodiumPassCoin;
    use podium::PodiumOutpost;
    use aptos_framework::aptos_account;

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

    /// Fee constants
    const MAX_REFERRAL_FEE_PERCENT: u64 = 2; // 2%
    const MAX_PROTOCOL_FEE_PERCENT: u64 = 4; // 4%
    const MAX_SUBJECT_FEE_PERCENT: u64 = 8; // 8%
    const SELL_DISCOUNT_PERCENT: u64 = 5; // 5% discount on sells
    
    /// Bonding curve constants
    const DEFAULT_WEIGHT_A: u64 = 80; // 80%
    const DEFAULT_WEIGHT_B: u64 = 50; // 50%
    const DEFAULT_WEIGHT_C: u64 = 2;  // Adjustment factor
    const INITIAL_PRICE: u64 = 1; // Initial price in APT

    /// Time constants
    const SECONDS_PER_WEEK: u64 = 7 * 24 * 60 * 60;
    const SECONDS_PER_MONTH: u64 = 30 * 24 * 60 * 60;
    const SECONDS_PER_YEAR: u64 = 365 * 24 * 60 * 60;

    /// Subscription durations
    const DURATION_WEEK: u64 = 1;
    const DURATION_MONTH: u64 = 2;
    const DURATION_YEAR: u64 = 3;

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
    }

    /// Subscription tier configuration
    struct SubscriptionTier has store {
        name: String,
        week_price: u64,
        month_price: u64,
        year_price: u64,
    }

    /// Tracks active subscriptions
    struct Subscription has store {
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
        });
    }

    /// Calculate price based on bonding curve
    /// price = initial_price * (1 + weight_a * supply^weight_c / weight_b)
    fun calculate_price(supply: u64, is_sell: bool): u64 {
        let config = borrow_global<Config>(@podium);
        
        let base_price = INITIAL_PRICE;
        if (supply == 0) {
            return base_price
        };

        let supply_factor = power(supply, config.weight_c);
        let weight_factor = (config.weight_a * supply_factor) / config.weight_b;
        let price = base_price * (100 + weight_factor) / 100;

        if (is_sell) {
            price = price * (100 - SELL_DISCOUNT_PERCENT) / 100;
        };

        price
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
        owner: &signer,
        target_or_outpost: address,
        tier_name: String,
        week_price: u64,
        month_price: u64,
        year_price: u64
    ) acquires SubscriptionConfig {
        // Verify owner is either target account or outpost owner
        assert!(
            signer::address_of(owner) == target_or_outpost || 
            PodiumOutpost::is_outpost_owner(signer::address_of(owner), string::utf8(b"")), // TODO: Get outpost name
            error::permission_denied(ENOT_AUTHORIZED)
        );

        if (!exists<SubscriptionConfig>(target_or_outpost)) {
            move_to(owner, SubscriptionConfig {
                tiers: vector::empty(),
                subscriptions: table::new(),
            });
        };

        let config = borrow_global_mut<SubscriptionConfig>(target_or_outpost);
        
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

    /// Safely transfers APT coins with recipient account verification
    /// Handles both registered and unregistered recipient accounts
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

    /// Buy passes for a target/outpost
    public entry fun buy_pass(
        buyer: &signer,
        target_or_outpost: address,
        amount: u64,
        referrer: Option<address>
    ) acquires Config, PassConfig, FeeConfig {
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));

        // Initialize PassConfig if it doesn't exist
        if (!exists<PassConfig>(target_or_outpost)) {
            move_to(buyer, PassConfig {
                supply: 0,
                last_price: INITIAL_PRICE,
            });
        };

        // Initialize FeeConfig if it doesn't exist
        if (!exists<FeeConfig>(target_or_outpost)) {
            move_to(buyer, FeeConfig {
                subject_address: target_or_outpost,
                referrer_address: referrer,
            });
        };

        let pass_config = borrow_global_mut<PassConfig>(target_or_outpost);
        let config = borrow_global<Config>(@podium);
        let fee_config = borrow_global<FeeConfig>(target_or_outpost);

        // Calculate total price
        let price = calculate_price(pass_config.supply, false);
        let total_cost = price * amount;

        // Verify buyer has enough balance
        let buyer_addr = signer::address_of(buyer);
        assert!(
            coin::balance<AptosCoin>(buyer_addr) >= total_cost,
            error::invalid_argument(INSUFFICIENT_BALANCE)
        );

        // Use distribute_fees which now uses transfer_with_check
        distribute_fees(buyer, total_cost, target_or_outpost, referrer);

        // Mint passes
        let asset_symbol = if (exists<PodiumOutpost::OutpostData>(target_or_outpost)) {
            // It's an outpost
            generate_outpost_symbol(target_or_outpost)
        } else {
            // It's a target account
            generate_target_symbol(target_or_outpost)
        };

        let fa = PodiumPassCoin::mint(buyer, asset_symbol, amount);
        primary_fungible_store::deposit(buyer_addr, fa);

        // Update supply and price
        pass_config.supply = pass_config.supply + amount;
        pass_config.last_price = price;
    }

    /// Sell passes back to the protocol
    public entry fun sell_pass(
        seller: &signer,
        target_or_outpost: address,
        amount: u64
    ) acquires Config, PassConfig {
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        assert!(exists<PassConfig>(target_or_outpost), error::not_found(EPASS_NOT_FOUND));

        let pass_config = borrow_global_mut<PassConfig>(target_or_outpost);
        
        // Calculate sell price with discount
        let price = calculate_price(pass_config.supply - amount, true);
        let total_payment = price * amount;

        // Verify seller has enough passes
        let seller_addr = signer::address_of(seller);
        let asset_symbol = if (exists<PodiumOutpost::OutpostData>(target_or_outpost)) {
            generate_outpost_symbol(target_or_outpost)
        } else {
            generate_target_symbol(target_or_outpost)
        };

        assert!(
            PodiumPassCoin::balance(seller_addr, asset_symbol) >= amount,
            error::invalid_argument(EINSUFFICIENT_PASS_BALANCE)
        );

        // Burn passes
        let fa = primary_fungible_store::withdraw(seller, asset_symbol, amount);
        PodiumPassCoin::burn(seller, asset_symbol, fa);

        // Pay seller using safe transfer
        transfer_with_check(@podium, seller_addr, total_payment);

        // Update supply and price
        pass_config.supply = pass_config.supply - amount;
        pass_config.last_price = price;
    }

    /// Distribute fees for a transaction
    fun distribute_fees(
        from: &signer,
        total_amount: u64,
        subject: address,
        referrer: Option<address>
    ) acquires Config {
        let config = borrow_global<Config>(@podium);
        
        // Calculate fee amounts
        let protocol_fee = (total_amount * config.protocol_fee_percent) / 100;
        let subject_fee = (total_amount * config.subject_fee_percent) / 100;
        let referral_fee = if (option::is_some(&referrer)) {
            (total_amount * config.referral_fee_percent) / 100
        } else {
            0
        };

        // Transfer fees using safe transfer
        transfer_with_check(from, config.treasury, protocol_fee);
        transfer_with_check(from, subject, subject_fee);
        if (option::is_some(&referrer)) {
            transfer_with_check(from, option::extract(&mut referrer), referral_fee);
        };
    }

    /// Helper function to generate target symbol
    fun generate_target_symbol(target: address): String {
        string::utf8(b"TARGET_") + string::utf8(target)
    }

    /// Helper function to generate outpost symbol
    fun generate_outpost_symbol(outpost: address): String {
        string::utf8(b"OUTPOST_") + string::utf8(outpost)
    }

    /// Subscribe to a target/outpost
    public entry fun subscribe(
        subscriber: &signer,
        target_or_outpost: address,
        tier_name: String,
        duration: u64,
        referrer: Option<address>
    ) acquires Config, SubscriptionConfig, FeeConfig {
        assert!(exists<SubscriptionConfig>(target_or_outpost), error::not_found(ESUBSCRIPTION_NOT_FOUND));
        assert!(
            duration == DURATION_WEEK || duration == DURATION_MONTH || duration == DURATION_YEAR,
            error::invalid_argument(EINVALID_DURATION)
        );

        let config = borrow_global_mut<SubscriptionConfig>(target_or_outpost);
        
        // Find tier and get price
        let tier_price = 0u64;
        let tier_found = false;
        let i = 0;
        let len = vector::length(&config.tiers);
        while (i < len) {
            let tier = vector::borrow(&config.tiers, i);
            if (tier.name == tier_name) {
                tier_price = if (duration == DURATION_WEEK) {
                    tier.week_price
                } else if (duration == DURATION_MONTH) {
                    tier.month_price
                } else {
                    tier.year_price
                };
                tier_found = true;
                break
            };
            i = i + 1;
        };
        assert!(tier_found, error::not_found(ETIER_NOT_FOUND));

        // Calculate subscription duration
        let duration_secs = if (duration == DURATION_WEEK) {
            SECONDS_PER_WEEK
        } else if (duration == DURATION_MONTH) {
            SECONDS_PER_MONTH
        } else {
            SECONDS_PER_YEAR
        };

        let start_time = timestamp::now_seconds();
        let end_time = start_time + duration_secs;

        // Process payment using distribute_fees which now uses transfer_with_check
        distribute_fees(subscriber, tier_price, target_or_outpost, referrer);

        // Create or update subscription
        let subscriber_addr = signer::address_of(subscriber);
        if (table::contains(&config.subscriptions, subscriber_addr)) {
            let sub = table::borrow_mut(&mut config.subscriptions, subscriber_addr);
            sub.tier = tier_name;
            sub.start_time = start_time;
            sub.end_time = end_time;
        } else {
            table::add(&mut config.subscriptions, subscriber_addr, Subscription {
                tier: tier_name,
                start_time,
                end_time,
            });
        };
    }

    /// Verify access rights for a user
    public fun verify_access(
        user: address,
        target_or_outpost: address
    ): (bool, Option<String>) acquires PassConfig, SubscriptionConfig {
        // Check lifetime pass ownership
        let has_lifetime_pass = if (exists<PassConfig>(target_or_outpost)) {
            let asset_symbol = if (exists<PodiumOutpost::OutpostData>(target_or_outpost)) {
                generate_outpost_symbol(target_or_outpost)
            } else {
                generate_target_symbol(target_or_outpost)
            };
            PodiumPassCoin::balance(user, asset_symbol) > 0
        } else {
            false
        };

        // If user has a lifetime pass, they have full access
        if (has_lifetime_pass) {
            return (true, option::none())
        };

        // Check subscription status
        if (exists<SubscriptionConfig>(target_or_outpost)) {
            let config = borrow_global<SubscriptionConfig>(target_or_outpost);
            if (table::contains(&config.subscriptions, user)) {
                let sub = table::borrow(&config.subscriptions, user);
                let current_time = timestamp::now_seconds();
                
                if (current_time <= sub.end_time) {
                    return (true, option::some(sub.tier))
                }
            }
        };

        (false, option::none())
    }

    /// Get subscription details for a user
    public fun get_subscription(
        user: address,
        target_or_outpost: address
    ): Option<Subscription> acquires SubscriptionConfig {
        if (!exists<SubscriptionConfig>(target_or_outpost)) {
            return option::none()
        };

        let config = borrow_global<SubscriptionConfig>(target_or_outpost);
        if (!table::contains(&config.subscriptions, user)) {
            return option::none()
        };

        let sub = table::borrow(&config.subscriptions, user);
        option::some(*sub)
    }

    /// Get subscription tier details
    public fun get_tier_details(
        target_or_outpost: address,
        tier_name: String
    ): Option<SubscriptionTier> acquires SubscriptionConfig {
        if (!exists<SubscriptionConfig>(target_or_outpost)) {
            return option::none()
        };

        let config = borrow_global<SubscriptionConfig>(target_or_outpost);
        let i = 0;
        let len = vector::length(&config.tiers);
        while (i < len) {
            let tier = vector::borrow(&config.tiers, i);
            if (tier.name == tier_name) {
                return option::some(*tier)
            };
            i = i + 1;
        };

        option::none()
    }

    /// Check if a subscription is active
    public fun is_subscription_active(
        user: address,
        target_or_outpost: address
    ): bool acquires SubscriptionConfig {
        if (!exists<SubscriptionConfig>(target_or_outpost)) {
            return false
        };

        let config = borrow_global<SubscriptionConfig>(target_or_outpost);
        if (!table::contains(&config.subscriptions, user)) {
            return false
        };

        let sub = table::borrow(&config.subscriptions, user);
        timestamp::now_seconds() <= sub.end_time
    }
}
   