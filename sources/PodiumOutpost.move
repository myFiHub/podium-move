module podium::PodiumOutpost {
    use std::string::{Self, String};
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_token::token;

    friend podium::PodiumPass;

    // Error codes
    const NOT_ADMIN: u64 = 1;
    const PAUSED: u64 = 2;
    const INVALID_TIER: u64 = 3;
    const INSUFFICIENT_BALANCE: u64 = 4;
    const OUTPOST_EXISTS: u64 = 5;
    const OUTPOST_NOT_FOUND: u64 = 6;
    const INVALID_PAYMENT: u64 = 7;
    const RECIPIENT_NOT_REGISTERED: u64 = 8;
    const NFT_TRANSFER_FAILED: u64 = 9;

    // Fee constants
    const OUTPOST_OWNER_FEE: u64 = 800; // 8%
    const PROTOCOL_FEE: u64 = 200; // 2%
    const BASIS_POINTS: u64 = 10000;

    struct CustomField has store, drop, copy {
        name: String,
        value: String
    }

    struct OutpostMetadata has store, drop, copy {
        name: String,
        description: Option<String>,
        category: Option<String>,
        tags: Option<vector<String>>,
        social_links: Option<vector<String>>,
        custom_fields: Option<vector<CustomField>>
    }

    struct OutpostTierConfig has store, drop {
        tier_prices: vector<u64>,
        min_subscription_days: u64,
        max_subscription_days: u64,
        tier_benefits: vector<String>
    }

    struct Outpost has key, store {
        owner: address,
        metadata: OutpostMetadata,
        token_data_id: token::TokenDataId,
        price: u64,
        created_at: u64,
        total_fees_collected: u64,
        last_fee_collection: u64,
        tier_config: Option<OutpostTierConfig>
    }

    struct OutpostRegistry has key {
        outposts: vector<Outpost>,
        total_protocol_fees: u64
    }

    struct OutpostEvent has store, drop {
        owner: address,
        name: String,
        price: u64,
        timestamp: u64
    }

    struct FeeEvent has store, drop {
        outpost_owner: address,
        amount: u64,
        protocol_fee: u64,
        owner_fee: u64,
        timestamp: u64
    }

    struct PurchaseEvent has store, drop {
        buyer: address,
        outpost_owner: address,
        price: u64,
        timestamp: u64
    }

    struct OutpostState has key {
        admin: address,
        paused: bool,
        events: event::EventHandle<OutpostEvent>,
        fee_events: event::EventHandle<FeeEvent>,
        purchase_events: event::EventHandle<PurchaseEvent>
    }

    fun transfer_payment_with_check(
        payment: &mut Coin<AptosCoin>,
        recipient: address,
        amount: u64
    ) {
        assert!(coin::value(payment) >= amount, INSUFFICIENT_BALANCE);

        // Extract payment
        let payment_coin = coin::extract(payment, amount);

        // Check if recipient is registered for AptosCoin
        if (!coin::is_account_registered<AptosCoin>(recipient)) {
            if (!account::exists_at(recipient)) {
                account::create_account_for_test(recipient); // For testing only
            };
            coin::register<AptosCoin>(
                &account::create_signer_for_test(recipient) // For testing only
            );
        };

        // Deposit payment
        coin::deposit(recipient, payment_coin);
    }

    fun transfer_nft_with_check(
        from: address,
        to: address,
        token_id: token::TokenId
    ) {
        // Ensure recipient account exists
        if (!account::exists_at(to)) {
            account::create_account_for_test(to); // For testing only
        };

        // Transfer NFT
        token::transfer(
            &account::create_signer_for_test(from), // For testing only
            token_id,
            to,
            1
        );
    }

    public fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @admin, NOT_ADMIN);

        if (!exists<OutpostRegistry>(@podium)) {
            move_to(admin, OutpostRegistry {
                outposts: vector::empty(),
                total_protocol_fees: 0
            });
        };

        if (!exists<OutpostState>(@podium)) {
            move_to(admin, OutpostState {
                admin: admin_addr,
                paused: false,
                events: account::new_event_handle<OutpostEvent>(admin),
                fee_events: account::new_event_handle<FeeEvent>(admin),
                purchase_events: account::new_event_handle<PurchaseEvent>(admin)
            });
        };
    }

    public fun create_outpost(
        owner: &signer,
        name: String,
        description: Option<String>,
        category: Option<String>,
        uri: String,
        price: u64,
        tags: Option<vector<String>>,
        social_links: Option<vector<String>>,
        custom_fields: Option<vector<CustomField>>
    ) acquires OutpostState, OutpostRegistry {
        let state = borrow_global_mut<OutpostState>(@podium);
        assert!(!state.paused, PAUSED);

        let owner_addr = signer::address_of(owner);
        let token_data_id = token::create_tokendata(
            owner,
            string::utf8(b"Podium Outpost"),
            name,
            option::get_with_default(&description, string::utf8(b"")),
            1,
            uri,
            owner_addr,
            1,
            0,
            token::create_token_mutability_config(&vector[false, false, false, false, false]),
            vector::empty<String>(),
            vector::empty<vector<u8>>(),
            vector::empty<String>(),
            vector::empty<vector<u8>>(),
            vector::empty<String>()
        );

        let outpost = Outpost {
            owner: owner_addr,
            metadata: OutpostMetadata {
                name,
                description,
                category,
                tags,
                social_links,
                custom_fields
            },
            token_data_id,
            price,
            created_at: timestamp::now_seconds(),
            total_fees_collected: 0,
            last_fee_collection: timestamp::now_seconds(),
            tier_config: option::none()
        };

        let registry = borrow_global_mut<OutpostRegistry>(@podium);
        vector::push_back(&mut registry.outposts, outpost);

        event::emit_event(&mut state.events, OutpostEvent {
            owner: owner_addr,
            name,
            price,
            timestamp: timestamp::now_seconds()
        });
    }

    public fun purchase_outpost(
        buyer: &signer,
        outpost_owner: address,
        payment: Coin<AptosCoin>
    ) acquires OutpostState, OutpostRegistry {
        let state = borrow_global_mut<OutpostState>(@podium);
        assert!(!state.paused, PAUSED);

        let registry = borrow_global_mut<OutpostRegistry>(@podium);
        let buyer_addr = signer::address_of(buyer);
        let payment_amount = coin::value(&payment);

        // Find outpost and verify price
        let i = 0;
        let outpost_found = false;
        while (i < vector::length(&registry.outposts)) {
            let outpost = vector::borrow(&registry.outposts, i);
            if (outpost.owner == outpost_owner) {
                assert!(payment_amount >= outpost.price, INVALID_PAYMENT);
                outpost_found = true;
                break
            };
            i = i + 1;
        };
        assert!(outpost_found, OUTPOST_NOT_FOUND);

        // Calculate fee splits
        let protocol_fee = (payment_amount * PROTOCOL_FEE) / BASIS_POINTS;
        let owner_fee = (payment_amount * OUTPOST_OWNER_FEE) / BASIS_POINTS;

        // Distribute fees safely
        let payment_mut = payment;
        transfer_payment_with_check(&mut payment_mut, @podium, protocol_fee);
        transfer_payment_with_check(&mut payment_mut, outpost_owner, owner_fee);

        // Handle remaining payment
        if (coin::value(&payment_mut) > 0) {
            transfer_payment_with_check(&mut payment_mut, outpost_owner, coin::value(&payment_mut));
        };
        coin::destroy_zero(payment_mut);

        // Get outpost and transfer NFT
        let outpost = vector::borrow_mut(&mut registry.outposts, i);
        
        // Create token ID for transfer
        let token_id = token::create_token_id_raw(
            outpost.token_data_id.creator,
            outpost.token_data_id.collection,
            outpost.token_data_id.name,
            outpost.token_data_id.property_version,
        );

        // Transfer NFT safely
        transfer_nft_with_check(outpost_owner, buyer_addr, token_id);

        // Update ownership in registry
        outpost.owner = buyer_addr;

        // Emit purchase event
        event::emit_event(&mut state.purchase_events, PurchaseEvent {
            buyer: buyer_addr,
            outpost_owner,
            price: payment_amount,
            timestamp: timestamp::now_seconds()
        });
    }

    public fun set_tier_config(
        owner: &signer,
        tier_prices: vector<u64>,
        min_days: u64,
        max_days: u64,
        tier_benefits: vector<String>
    ) acquires OutpostState, OutpostRegistry {
        let state = borrow_global<OutpostState>(@podium);
        assert!(!state.paused, PAUSED);

        let owner_addr = signer::address_of(owner);
        let registry = borrow_global_mut<OutpostRegistry>(@podium);

        let i = 0;
        while (i < vector::length(&mut registry.outposts)) {
            let outpost = vector::borrow_mut(&mut registry.outposts, i);
            if (outpost.owner == owner_addr) {
                outpost.tier_config = option::some(OutpostTierConfig {
                    tier_prices,
                    min_subscription_days: min_days,
                    max_subscription_days: max_days,
                    tier_benefits
                });
                break
            };
            i = i + 1;
        };
    }

    public fun get_tier_config(outpost_owner: address): Option<OutpostTierConfig> acquires OutpostRegistry {
        let registry = borrow_global<OutpostRegistry>(@podium);
        let i = 0;
        while (i < vector::length(&registry.outposts)) {
            let outpost = vector::borrow(&registry.outposts, i);
            if (outpost.owner == outpost_owner) {
                return *&outpost.tier_config
            };
            i = i + 1;
        };
        option::none()
    }

    public fun collect_fees<CoinType>(
        amount: u64,
        outpost_owner: address
    ) acquires OutpostState, OutpostRegistry {
        let state = borrow_global_mut<OutpostState>(@podium);
        assert!(!state.paused, PAUSED);

        let registry = borrow_global_mut<OutpostRegistry>(@podium);
        
        // Calculate fee splits
        let protocol_fee = (amount * PROTOCOL_FEE) / BASIS_POINTS;
        let owner_fee = (amount * OUTPOST_OWNER_FEE) / BASIS_POINTS;

        // Update protocol fees
        registry.total_protocol_fees = registry.total_protocol_fees + protocol_fee;

        // Update outpost fees
        let i = 0;
        while (i < vector::length(&mut registry.outposts)) {
            let outpost = vector::borrow_mut(&mut registry.outposts, i);
            if (outpost.owner == outpost_owner) {
                outpost.total_fees_collected = outpost.total_fees_collected + owner_fee;
                outpost.last_fee_collection = timestamp::now_seconds();
                break
            };
            i = i + 1;
        };

        // Emit fee event
        event::emit_event(&mut state.fee_events, FeeEvent {
            outpost_owner,
            amount,
            protocol_fee,
            owner_fee,
            timestamp: timestamp::now_seconds()
        });
    }

    public fun get_fee_info(outpost_owner: address): (u64, u64, u64) acquires OutpostRegistry {
        let registry = borrow_global<OutpostRegistry>(@podium);
        let i = 0;
        while (i < vector::length(&registry.outposts)) {
            let outpost = vector::borrow(&registry.outposts, i);
            if (outpost.owner == outpost_owner) {
                return (
                    outpost.total_fees_collected,
                    outpost.last_fee_collection,
                    registry.total_protocol_fees
                )
            };
            i = i + 1;
        };
        (0, 0, registry.total_protocol_fees)
    }

    public fun is_outpost_owner(owner: address, outpost_owner: address): bool {
        owner == outpost_owner
    }

    public fun get_outpost_price(outpost_owner: address): u64 acquires OutpostRegistry {
        let registry = borrow_global<OutpostRegistry>(@podium);
        let i = 0;
        while (i < vector::length(&registry.outposts)) {
            let outpost = vector::borrow(&registry.outposts, i);
            if (outpost.owner == outpost_owner) {
                return outpost.price
            };
            i = i + 1;
        };
        0
    }

    public fun get_outpost_metadata(outpost_owner: address): Option<OutpostMetadata> acquires OutpostRegistry {
        let registry = borrow_global<OutpostRegistry>(@podium);
        let i = 0;
        while (i < vector::length(&registry.outposts)) {
            let outpost = vector::borrow(&registry.outposts, i);
            if (outpost.owner == outpost_owner) {
                return option::some(*&outpost.metadata)
            };
            i = i + 1;
        };
        option::none()
    }

    public fun update_outpost_price(
        owner: &signer,
        new_price: u64
    ) acquires OutpostState, OutpostRegistry {
        let state = borrow_global<OutpostState>(@podium);
        assert!(!state.paused, PAUSED);

        let owner_addr = signer::address_of(owner);
        let registry = borrow_global_mut<OutpostRegistry>(@podium);
        let i = 0;
        while (i < vector::length(&registry.outposts)) {
            let outpost = vector::borrow_mut(&mut registry.outposts, i);
            if (outpost.owner == owner_addr) {
                outpost.price = new_price;
                break
            };
            i = i + 1;
        };
    }

    public fun pause(admin: &signer) acquires OutpostState {
        let state = borrow_global_mut<OutpostState>(@podium);
        assert!(signer::address_of(admin) == state.admin, NOT_ADMIN);
        state.paused = true;
    }

    public fun unpause(admin: &signer) acquires OutpostState {
        let state = borrow_global_mut<OutpostState>(@podium);
        assert!(signer::address_of(admin) == state.admin, NOT_ADMIN);
        state.paused = false;
    }

    public fun is_paused(): bool acquires OutpostState {
        borrow_global<OutpostState>(@podium).paused
    }

    public fun get_token_data_id_fields(token_data_id: &token::TokenDataId): (address, String, String, u64) {
        (
            token::get_tokendata_creator(token_data_id),
            token::get_tokendata_collection(token_data_id),
            token::get_tokendata_name(token_data_id),
            token::get_tokendata_property_version(token_data_id)
        )
    }

    public fun get_outpost_token_data(outpost: &Outpost): (address, String, String, u64) {
        get_token_data_id_fields(&outpost.token_data_id)
    }
} 