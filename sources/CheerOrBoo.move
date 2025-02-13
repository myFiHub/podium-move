module podium::CheerOrBoo {
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use std::vector;
    use std::signer;

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
    
    // Add max participants limit
    const MAX_PARTICIPANTS: u64 = 10000;

    #[event]
    struct CheerEvent has drop, store, copy {
        target: address,
        participants: vector<address>,
        amount: u64,
        target_allocation: u64,
        unique_identifier: vector<u8>,
    }

    #[event]
    struct BooEvent has drop, store, copy {
        target: address,
        participants: vector<address>,
        amount: u64,
        target_allocation: u64,
        unique_identifier: vector<u8>,
    }

    public entry fun cheer_or_boo(
        sender: &signer,
        target: address,
        participants: vector<address>,
        is_cheer: bool,
        amount: u64,
        target_allocation: u64,
        unique_identifier: vector<u8>
    ) {
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

        // Transfer to target
        let target_amount = (net_amount * target_allocation) / 100;
        if (target_amount > 0) {
            transfer_with_check(sender, target, target_amount);
        };

        let remaining_amount = net_amount - target_amount;

        // Distribute remaining amount to participants
        let num_participants = vector::length(&participants);
        if (num_participants > 0) {
            let per_participant_amount = remaining_amount / num_participants;
            distribute_remaining(sender, participants, per_participant_amount);
        };

        // Emit appropriate event
        if (is_cheer) {
            emit_cheer_event(target, participants, amount, target_allocation, unique_identifier);
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
        unique_identifier: vector<u8>
    ) {
        let event = CheerEvent {
            target,
            participants,
            amount,
            target_allocation,
            unique_identifier,
        };
        0x1::event::emit(event);
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
        0x1::event::emit(event);
    }

    #[view]
    public fun get_max_participants(): u64 {
        MAX_PARTICIPANTS
    }
}
