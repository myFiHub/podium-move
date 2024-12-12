module podium::PodiumPassCoin {
    use std::string::{Self, String};
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability};
    use aptos_std::type_info;

    friend podium::PodiumPass;

    // Error codes
    const NOT_ADMIN: u64 = 1;
    const INSUFFICIENT_BALANCE: u64 = 2;
    const RECIPIENT_NOT_REGISTERED: u64 = 3;

    struct PassCoin<phantom TargetAddress> has key {}

    struct PassBalance has store {
        amount: u64
    }

    struct PassCoinCapability<phantom TargetAddress> has key {
        burn_cap: BurnCapability<PassCoin<TargetAddress>>,
        mint_cap: MintCapability<PassCoin<TargetAddress>>
    }

    struct PassCoinInfo<phantom TargetAddress> has key {
        name: String,
        total_supply: u64,
        mint_events: event::EventHandle<MintEvent>,
        burn_events: event::EventHandle<BurnEvent>,
        transfer_events: event::EventHandle<TransferEvent>
    }

    struct PassCoinRegistry has key {
        targets: vector<String>
    }

    struct MintEvent has store, drop {
        recipient: address,
        amount: u64,
        timestamp: u64
    }

    struct BurnEvent has store, drop {
        holder: address,
        amount: u64,
        timestamp: u64
    }

    struct TransferEvent has store, drop {
        from: address,
        to: address,
        amount: u64,
        timestamp: u64
    }

    public fun initialize_target<TargetAddress>(
        admin: &signer,
        name: String
    ) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @admin, NOT_ADMIN);

        if (!exists<PassCoinRegistry>(@podium)) {
            move_to(admin, PassCoinRegistry {
                targets: vector::empty()
            });
        };

        let registry = borrow_global_mut<PassCoinRegistry>(@podium);
        vector::push_back(&mut registry.targets, name);

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<PassCoin<TargetAddress>>(
            admin,
            name,
            string::utf8(b"PASS"),
            6,
            true
        );

        move_to(admin, PassCoinCapability<TargetAddress> {
            burn_cap,
            mint_cap
        });

        move_to(admin, PassCoinInfo<TargetAddress> {
            name,
            total_supply: 0,
            mint_events: account::new_event_handle<MintEvent>(admin),
            burn_events: account::new_event_handle<BurnEvent>(admin),
            transfer_events: account::new_event_handle<TransferEvent>(admin)
        });

        coin::destroy_freeze_cap(freeze_cap);
    }

    public fun mint_pass<TargetAddress>(
        admin: &signer,
        recipient: address,
        amount: u64
    ) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @admin, NOT_ADMIN);

        let cap = borrow_global<PassCoinCapability<TargetAddress>>(@podium);
        let info = borrow_global_mut<PassCoinInfo<TargetAddress>>(@podium);

        let coins = coin::mint(amount, &cap.mint_cap);
        if (!account::exists_at(recipient)) {
            account::create_account_for_test(recipient);
        };
        coin::deposit(recipient, coins);

        // Update supply
        info.total_supply = info.total_supply + amount;

        // Emit event
        event::emit_event(&mut info.mint_events, MintEvent {
            recipient,
            amount,
            timestamp: timestamp::now_seconds()
        });
    }

    public fun burn_pass<TargetAddress>(
        holder: &signer,
        amount: u64
    ) {
        let holder_addr = signer::address_of(holder);
        let balance = get_pass_balance<TargetAddress>(holder_addr);
        assert!(balance.amount >= amount, INSUFFICIENT_BALANCE);

        let cap = borrow_global<PassCoinCapability<TargetAddress>>(@podium);
        let info = borrow_global_mut<PassCoinInfo<TargetAddress>>(@podium);

        let coins = coin::withdraw<PassCoin<TargetAddress>>(holder, amount);
        coin::burn(coins, &cap.burn_cap);

        // Update supply
        info.total_supply = info.total_supply - amount;

        // Emit event
        event::emit_event(&mut info.burn_events, BurnEvent {
            holder: holder_addr,
            amount,
            timestamp: timestamp::now_seconds()
        });
    }

    public fun transfer_pass<TargetAddress>(
        from: &signer,
        to: address,
        amount: u64
    ) acquires PassCoinInfo {
        let from_addr = signer::address_of(from);
        
        // Check sender's balance
        assert!(
            coin::balance<PassCoin<TargetAddress>>(from_addr) >= amount,
            INSUFFICIENT_BALANCE
        );

        // Check if recipient is registered
        if (!coin::is_account_registered<PassCoin<TargetAddress>>(to)) {
            // Create account and register coin store if needed
            if (!account::exists_at(to)) {
                account::create_account_for_test(to); // For testing only
            };
            coin::register<PassCoin<TargetAddress>>(
                &account::create_signer_for_test(to) // For testing only
            );
        };

        // Perform transfer
        let coins = coin::withdraw<PassCoin<TargetAddress>>(from, amount);
        coin::deposit(to, coins);

        // Emit transfer event
        let info = borrow_global_mut<PassCoinInfo<TargetAddress>>(@podium);
        event::emit_event(&mut info.transfer_events, TransferEvent {
            from: from_addr,
            to,
            amount,
            timestamp: timestamp::now_seconds()
        });
    }

    public fun get_pass_balance<TargetAddress>(holder: address): PassBalance {
        let target = type_info::type_name<TargetAddress>();
        let amount = if (coin::is_account_registered<PassCoin<TargetAddress>>(holder)) {
            coin::balance<PassCoin<TargetAddress>>(holder)
        } else {
            0
        };

        PassBalance { amount }
    }

    public fun get_all_holdings(holder: address): vector<PassBalance> {
        let registry = borrow_global<PassCoinRegistry>(@podium);
        let holdings = vector::empty<PassBalance>();
        let i = 0;

        while (i < vector::length(&registry.targets)) {
            let target = vector::borrow(&registry.targets, i);
            let balance = get_pass_balance<String>(holder);
            if (balance.amount > 0) {
                vector::push_back(&mut holdings, balance);
            };
            i = i + 1;
        };

        holdings
    }

    public fun get_total_supply<TargetAddress>(): u64 acquires PassCoinInfo {
        borrow_global<PassCoinInfo<TargetAddress>>(@podium).total_supply
    }

    /// Get the amount of a pass balance
    public fun get_pass_balance_amount(balance: &PassBalance): u64 {
        balance.amount
    }

    /// Check if a pass balance has any amount
    public fun has_pass_balance(balance: &PassBalance): bool {
        balance.amount > 0
    }
} 