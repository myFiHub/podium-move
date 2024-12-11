module podium::PodiumPassCoin {
    use std::string::String;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::event;
    use aptos_framework::account;
    use aptos_framework::signer;
    
    friend podium::PodiumPass;  // Allow PodiumPass to mint/burn

    /// Errors
    const ENOT_AUTHORIZED: u64 = 1;
    const EINVALID_AMOUNT: u64 = 2;
    const EINVALID_TIER: u64 = 4;
    const EINSUFFICIENT_BALANCE: u64 = 5;
    const PAUSED: u64 = 6;

    /// Constants
    const TIER_BASIC: u8 = 1;
    const TIER_PREMIUM: u8 = 2;
    const TIER_EXCLUSIVE: u8 = 3;

    /// Pass attributes - simplified for lifetime passes only
    struct PassAttributes has store, drop {
        tier: u8,
        target_address: address,
    }

    /// Generic coin type for passes
    struct PassCoin<phantom TargetAddress> has key { }

    /// Capability to manage passes for a specific target
    struct PassMintCapability<phantom TargetAddress> has key {
        mint_cap: MintCapability<PassCoin<TargetAddress>>,
        burn_cap: BurnCapability<PassCoin<TargetAddress>>,
        freeze_cap: FreezeCapability<PassCoin<TargetAddress>>,
    }

    /// Registry to track pass metadata
    struct PassRegistry has key {
        pass_metadata: vector<(address, PassAttributes)>,
        events: event::EventHandle<PassEvent>,
    }

    /// Event for pass operations
    struct PassEvent has drop, store {
        operation_type: String,
        target_address: address,
        user: address,
        amount: u64,
        tier: u8,
        timestamp: u64,
    }

    /// Initialize pass system for a target
    public(friend) fun initialize_target<TargetAddress>(
        admin: &signer,
        target_name: String,
    ) {
        let admin_addr = signer::address_of(admin);
        
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<PassCoin<TargetAddress>>(
            admin,
            target_name,
            target_name,
            6, // decimals
            true // monitor_supply
        );

        move_to(admin, PassMintCapability<TargetAddress> {
            mint_cap,
            burn_cap,
            freeze_cap,
        });

        if (!exists<PassRegistry>(admin_addr)) {
            move_to(admin, PassRegistry {
                pass_metadata: vector::empty(),
                events: account::new_event_handle<PassEvent>(admin),
            });
        };
    }

    /// Mint new passes for a target (only callable by PodiumPass)
    public(friend) fun mint_pass<TargetAddress>(
        admin: &signer,
        recipient: address,
        amount: u64,
        tier: u8,
    ) acquires PassMintCapability, PassRegistry {
        assert!(!PodiumPass::is_paused(), PAUSED);
        assert!(tier >= TIER_BASIC && tier <= TIER_EXCLUSIVE, EINVALID_TIER);
        
        let cap = borrow_global<PassMintCapability<TargetAddress>>(signer::address_of(admin));
        let coins = coin::mint(amount, &cap.mint_cap);

        let attributes = PassAttributes {
            tier,
            target_address: type_info::type_of<TargetAddress>().account_address,
        };

        update_pass_metadata(recipient, attributes);
        coin::deposit(recipient, coins);

        emit_pass_event(
            signer::address_of(admin),
            recipient,
            amount,
            tier,
            string::utf8(b"mint"),
        );
    }

    /// Trade passes between users
    public entry fun trade_pass<TargetAddress>(
        seller: &signer,
        buyer: address,
        amount: u64,
        price: u64
    ) acquires PassRegistry {
        let seller_addr = signer::address_of(seller);
        
        assert!(
            coin::balance<PassCoin<TargetAddress>>(seller_addr) >= amount,
            EINSUFFICIENT_BALANCE
        );

        let pass_coins = coin::withdraw<PassCoin<TargetAddress>>(seller, amount);
        coin::deposit(buyer, pass_coins);

        // Transfer payment
        coin::transfer<AptosCoin>(seller, buyer, price);

        emit_pass_event(
            seller_addr,
            buyer,
            amount,
            get_pass_tier<TargetAddress>(seller_addr),
            string::utf8(b"trade"),
        );
    }

    /// Verify if an account has valid pass access
    public fun verify_access<TargetAddress>(
        account: address,
        required_tier: u8
    ): bool acquires PassRegistry {
        let balance = coin::balance<PassCoin<TargetAddress>>(account);
        if (balance == 0) return false;

        let metadata = get_pass_metadata(account);
        let target_addr = type_info::type_of<TargetAddress>().account_address;

        metadata.tier >= required_tier && 
        metadata.target_address == target_addr
    }

    // Helper functions remain mostly the same, just simplified
    fun update_pass_metadata(
        account: address,
        attributes: PassAttributes
    ) acquires PassRegistry {
        let registry = borrow_global_mut<PassRegistry>(@admin);
        let i = 0;
        let found = false;
        
        while (i < vector::length(&registry.pass_metadata)) {
            let (addr, _) = vector::borrow_mut(&mut registry.pass_metadata, i);
            if (*addr == account) {
                vector::borrow_mut(&mut registry.pass_metadata, i).1 = attributes;
                found = true;
                break;
            };
            i = i + 1;
        };

        if (!found) {
            vector::push_back(&mut registry.pass_metadata, (account, attributes));
        };
    }

    fun get_pass_metadata(account: address): PassAttributes acquires PassRegistry {
        let registry = borrow_global<PassRegistry>(@admin);
        let i = 0;
        
        while (i < vector::length(&registry.pass_metadata)) {
            let (addr, attributes) = vector::borrow(&registry.pass_metadata, i);
            if (*addr == account) {
                return *attributes;
            };
            i = i + 1;
        };
        
        abort ENOT_AUTHORIZED
    }

    fun get_pass_tier<TargetAddress>(account: address): u8 acquires PassRegistry {
        get_pass_metadata(account).tier
    }

    fun emit_pass_event(
        from: address,
        to: address,
        amount: u64,
        tier: u8,
        operation: String,
    ) acquires PassRegistry {
        let registry = borrow_global_mut<PassRegistry>(@admin);
        event::emit_event(
            &mut registry.events,
            PassEvent {
                operation_type: operation,
                target_address: from,
                user: to,
                amount,
                tier,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    /// Burn passes (only callable by PodiumPass)
    public(friend) fun burn_pass<TargetAddress>(
        user: &signer,
        amount: u64
    ) acquires PassMintCapability, PassRegistry {
        assert!(!PodiumPass::is_paused(), PAUSED);
        let user_addr = signer::address_of(user);
        assert!(
            coin::balance<PassCoin<TargetAddress>>(user_addr) >= amount,
            EINSUFFICIENT_BALANCE
        );

        let pass_coins = coin::withdraw<PassCoin<TargetAddress>>(user, amount);
        let cap = borrow_global<PassMintCapability<TargetAddress>>(@admin);
        coin::burn(pass_coins, &cap.burn_cap);

        emit_pass_event(
            user_addr,
            @admin,
            amount,
            get_pass_tier<TargetAddress>(user_addr),
            string::utf8(b"burn"),
        );
    }

    // Add new structs for query results
    struct PassBalance has copy, drop {
        amount: u64,
        tier: u8,
    }

    struct PassHolding has copy, drop {
        target_address: address,
        balance: PassBalance,
    }

    // Get balance for a specific target
    public fun get_pass_balance<TargetAddress>(
        holder: address
    ): PassBalance acquires PassRegistry {
        let balance = coin::balance<PassCoin<TargetAddress>>(holder);
        let tier = if (balance > 0) {
            get_pass_tier<TargetAddress>(holder)
        } else {
            0
        };

        PassBalance {
            amount: balance,
            tier
        }
    }

    // Get all pass holdings for an address
    public fun get_all_pass_holdings(
        holder: address
    ): vector<PassHolding> acquires PassRegistry {
        let registry = borrow_global<PassRegistry>(@admin);
        let holdings = vector::empty<PassHolding>();
        
        let i = 0;
        while (i < vector::length(&registry.pass_metadata)) {
            let (addr, attributes) = vector::borrow(&registry.pass_metadata, i);
            if (*addr == holder) {
                let balance = coin::balance<PassCoin<attributes.target_address>>(holder);
                if (balance > 0) {
                    vector::push_back(&mut holdings, PassHolding {
                        target_address: attributes.target_address,
                        balance: PassBalance {
                            amount: balance,
                            tier: attributes.tier
                        }
                    });
                };
            };
            i = i + 1;
        };
        
        holdings
    }

    // Check if holder has any passes for a target
    public fun has_passes<TargetAddress>(holder: address): bool {
        coin::balance<PassCoin<TargetAddress>>(holder) > 0
    }
} 