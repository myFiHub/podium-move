module podium::CheerOrBooPodium {
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use std::vector;
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_framework::account;

    const FEE_PERCENTAGE: u64 = 5;
    const FEE_ADDRESS: address = @fihub;
    const INSUFFICIENT_BALANCE: u64 = 102;
    const ADMIN_ADDRESS: address = @podium;

    // Error constants
    const EINVALID_TARGET_ALLOCATION: u64 = 100;
    const EINVALID_AMOUNT: u64 = 101;
    const EINSUFFICIENT_BALANCE: u64 = 102;
    const EEMPTY_PARTICIPANTS: u64 = 103;
    const EMAX_PARTICIPANTS_EXCEEDED: u64 = 104;
    const EINVALID_FEE_CONFIG: u64 = 105;
    const ENOT_ADMIN: u64 = 106;
    const EINVALID_PERCENTAGE: u64 = 107;
    const ENOT_CORE_ADMIN: u64 = 108;
    const ENOT_PARAM_ADMIN: u64 = 109;
    
    // Add max participants limit
    const MAX_PARTICIPANTS: u64 = 10000;

    /// Configuration for cheer/boo distribution
    struct Config has key {
        /// Percentage of funds that go to target when booed (in basis points, 100 = 1%)
        boo_target_percentage: u64,
        /// List of addresses that can update parameters
        param_admins: vector<address>,
        /// Core admin address that can manage all permissions
        core_admin: address,
        /// Event handle for config events
        config_events: event::EventHandle<ConfigUpdateEvent>,
        /// Event handle for admin events
        admin_events: event::EventHandle<AdminUpdateEvent>,
    }

    #[event]
    struct ConfigUpdateEvent has drop, store {
        boo_target_percentage: u64,
        timestamp: u64,
        updated_by: address,
    }

    #[event]
    struct AdminUpdateEvent has drop, store {
        admin_address: address,
        is_add: bool,
        is_param_admin: bool,
        timestamp: u64,
    }

    #[event]
    struct CheerEvent has drop, store, copy {
        target: address,
        participants: vector<address>,
        amount: u64,
        target_allocation: u64,
        unique_identifier: vector<u8>,
        is_self_cheer: bool,
    }

    #[event]
    struct BooEvent has drop, store, copy {
        target: address,
        participants: vector<address>,
        amount: u64,
        target_allocation: u64,
        unique_identifier: vector<u8>,
    }

    /// Initialize the configuration
    public entry fun initialize(account: &signer) {
        assert!(signer::address_of(account) == ADMIN_ADDRESS, ENOT_ADMIN);
        
        move_to(account, Config {
            boo_target_percentage: 5000, // 50% default
            param_admins: vector::empty(),
            core_admin: ADMIN_ADDRESS,
            config_events: account::new_event_handle<ConfigUpdateEvent>(account),
            admin_events: account::new_event_handle<AdminUpdateEvent>(account),
        });
    }

    /// Update the configuration (callable by param admins)
    public entry fun update_config(
        account: &signer,
        new_boo_target_percentage: u64
    ) acquires Config {
        let sender_addr = signer::address_of(account);
        let config = borrow_global_mut<Config>(@podium);
        
        // Check if sender is a param admin or core admin
        let is_param_admin = false;
        let i = 0;
        let len = vector::length(&config.param_admins);
        while (i < len) {
            if (*vector::borrow(&config.param_admins, i) == sender_addr) {
                is_param_admin = true;
                break
            };
            i = i + 1;
        };
        assert!(is_param_admin || sender_addr == config.core_admin, ENOT_PARAM_ADMIN);
        
        // Validate percentage
        assert!(new_boo_target_percentage <= 10000, EINVALID_PERCENTAGE);
        
        // Update config
        config.boo_target_percentage = new_boo_target_percentage;
        
        // Emit event
        event::emit_event(
            &mut config.config_events,
            ConfigUpdateEvent {
                boo_target_percentage: new_boo_target_percentage,
                timestamp: timestamp::now_seconds(),
                updated_by: sender_addr,
            }
        );
    }

    /// Add a new param admin (only core admin)
    public entry fun add_param_admin(account: &signer, new_admin: address) acquires Config {
        let sender_addr = signer::address_of(account);
        let config = borrow_global_mut<Config>(@podium);
        assert!(sender_addr == config.core_admin, ENOT_CORE_ADMIN);
        
        vector::push_back(&mut config.param_admins, new_admin);
        
        event::emit_event(
            &mut config.admin_events,
            AdminUpdateEvent {
                admin_address: new_admin,
                is_add: true,
                is_param_admin: true,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Remove a param admin (only core admin)
    public entry fun remove_param_admin(account: &signer, admin_to_remove: address) acquires Config {
        let sender_addr = signer::address_of(account);
        let config = borrow_global_mut<Config>(@podium);
        assert!(sender_addr == config.core_admin, ENOT_CORE_ADMIN);
        
        let i = 0;
        let len = vector::length(&config.param_admins);
        while (i < len) {
            if (*vector::borrow(&config.param_admins, i) == admin_to_remove) {
                vector::remove(&mut config.param_admins, i);
                break
            };
            i = i + 1;
        };
        
        event::emit_event(
            &mut config.admin_events,
            AdminUpdateEvent {
                admin_address: admin_to_remove,
                is_add: false,
                is_param_admin: true,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Update core admin (only current core admin)
    public entry fun update_core_admin(account: &signer, new_core_admin: address) acquires Config {
        let sender_addr = signer::address_of(account);
        let config = borrow_global_mut<Config>(@podium);
        assert!(sender_addr == config.core_admin, ENOT_CORE_ADMIN);
        
        config.core_admin = new_core_admin;
        
        event::emit_event(
            &mut config.admin_events,
            AdminUpdateEvent {
                admin_address: new_core_admin,
                is_add: true,
                is_param_admin: false,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    public entry fun cheer_or_boo(
        sender: &signer,
        target: address,
        participants: vector<address>,
        is_cheer: bool,
        is_self_cheer: bool,
        amount: u64,
        target_allocation: u64,
        unique_identifier: vector<u8>
    ) acquires Config {
        // Validate inputs with proper error codes
        assert!(target_allocation <= 100, EINVALID_TARGET_ALLOCATION);
        assert!(amount > 0, EINVALID_AMOUNT);
        assert!(vector::length(&participants) <= MAX_PARTICIPANTS, EMAX_PARTICIPANTS_EXCEEDED);
        assert!(FEE_PERCENTAGE < 100, EINVALID_FEE_CONFIG);
        assert!(
            target_allocation == 100 || !vector::is_empty(&participants),
            EEMPTY_PARTICIPANTS
        );

        let fee = (amount * FEE_PERCENTAGE) / 100;
        let net_amount = amount - fee;

        // Transfer fee
        transfer_with_check(sender, FEE_ADDRESS, fee);

        let remaining_amount = net_amount;

        if (is_cheer) {
            // For cheers, if it's a self-cheer, target gets nothing
            if (!is_self_cheer) {
                let target_amount = (net_amount * target_allocation) / 100;
                if (target_amount > 0) {
                    transfer_with_check(sender, target, target_amount);
                    remaining_amount = remaining_amount - target_amount;
                };
            };
        } else {
            // For boos, target gets the configured percentage
            let config = borrow_global<Config>(@podium);
            let target_amount = (net_amount * config.boo_target_percentage) / 10000;
            if (target_amount > 0) {
                transfer_with_check(sender, target, target_amount);
                remaining_amount = remaining_amount - target_amount;
            };
        };

        // Distribute remaining amount to participants
        let num_participants = vector::length(&participants);
        if (num_participants > 0) {
            let per_participant_amount = remaining_amount / num_participants;
            distribute_remaining(sender, participants, per_participant_amount);
        };

        // Emit appropriate event
        if (is_cheer) {
            emit_cheer_event(target, participants, amount, target_allocation, unique_identifier, is_self_cheer);
        } else {
            emit_boo_event(target, participants, amount, target_allocation, unique_identifier);
        };
    }

    fun distribute_remaining(sender: &signer, participants: vector<address>, amount_per_participant: u64) {
        assert!(!vector::is_empty(&participants), EEMPTY_PARTICIPANTS);
        let length = vector::length(&participants);
        let mut_index = 0;
        while (mut_index < length) {
            let participant = *vector::borrow(&participants, mut_index);
            transfer_with_check(sender, participant, amount_per_participant);
            mut_index = mut_index + 1;
        }
    }

    fun transfer_with_check(sender: &signer, recipient: address, amount: u64) {
        // Step 1: Check if the sender has sufficient balance
        let sender_addr = signer::address_of(sender);
        
        // Check if sender has CoinStore
        if (coin::is_account_registered<AptosCoin>(sender_addr)) {
            assert!(
                coin::balance<AptosCoin>(sender_addr) >= amount,
                INSUFFICIENT_BALANCE
            );
            
            // Check recipient and transfer
            if (coin::is_account_registered<AptosCoin>(recipient)) {
                coin::transfer<AptosCoin>(sender, recipient, amount);
            } else {
                aptos_account::transfer(sender, recipient, amount);
            };
        } else {
            // Fallback for sender without CoinStore
            aptos_account::transfer(sender, recipient, amount);
        };
    }

    fun emit_cheer_event(
        target: address,
        participants: vector<address>,
        amount: u64,
        target_allocation: u64,
        unique_identifier: vector<u8>,
        is_self_cheer: bool
    ) {
        let event = CheerEvent {
            target,
            participants,
            amount,
            target_allocation,
            unique_identifier,
            is_self_cheer,
        };
        event::emit(event);
    }

    fun emit_boo_event(
        target: address,
        participants: vector<address>,
        amount: u64,
        target_allocation: u64,
        unique_identifier: vector<u8>
    ) {
        let event = BooEvent {
            target,
            participants,
            amount,
            target_allocation,
            unique_identifier,
        };
        event::emit(event);
    }

    #[view]
    public fun get_config(): (u64, vector<address>, address) acquires Config {
        let config = borrow_global<Config>(@podium);
        (config.boo_target_percentage, config.param_admins, config.core_admin)
    }

    #[view]
    public fun is_param_admin(addr: address): bool acquires Config {
        let config = borrow_global<Config>(@podium);
        let i = 0;
        let len = vector::length(&config.param_admins);
        while (i < len) {
            if (*vector::borrow(&config.param_admins, i) == addr) {
                return true
            };
            i = i + 1;
        };
        false
    }

    #[view]
    public fun is_core_admin(addr: address): bool acquires Config {
        let config = borrow_global<Config>(@podium);
        addr == config.core_admin
    }

    #[view]
    public fun get_max_participants(): u64 {
        MAX_PARTICIPANTS
    }
}
