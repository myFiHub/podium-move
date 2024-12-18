# Podium Protocol & CheerOrBoo

A decentralized protocol suite built on movement, including subscription management, pass trading, and social tipping features.

## Overview

### Podium Protocol
The protocol enables content creators and audiences to actively participate in digital communities through:
1. Pass trading with bonding curve pricing
2. Flexible subscription management
3. Outpost creation and management
4. Fee distribution with referral incentives

### CheerOrBoo
A social tipping system allowing audience participation through positive (Cheer) or negative (Boo) feedback, with automatic reward distribution.

## Smart Contract Architecture

### 1. PodiumProtocol
Core protocol handling pass trading, subscriptions, and outpost management.

**Key Features:**
- Bonding curve-based pass pricing (80/50/2 weight configuration)
- Multi-tier subscription management
- Automated fee distribution (4% protocol, 8% subject, 2% referral)
- Vault system for pass redemption
- Emergency pause functionality
- Upgradeable architecture

**Security Features:**
- Role-based access control
- Emergency pause mechanism
- Balance validation
- Secure fee distribution
- Event emission for tracking

**Limitations:**
- Fixed asset symbol generation ("T1")
- No slippage protection in trading
- Fixed bonding curve parameters
- No maximum tier limit enforcement

### 2. CheerOrBoo
Social tipping implementation with dual action system.

**Key Features:**
- 5% fixed protocol fee
- Configurable reward distribution
- Multi-participant splitting
- Automatic account registration

**Security Features:**
- Balance checks
- Safe transfer handling
- Event tracking

**Limitations:**
- Fixed fee percentage
- Hardcoded fee recipient
- No upgradability mechanism

## Implementation Details

### Pass Trading System
```move
calculate_buy_price_with_fees(target_addr: address, amount: u64, referrer: Option<address>)
calculate_sell_price_with_fees(target_addr: address, amount: u64)
```

### Subscription System

The protocol implements a flexible subscription system with the following features:

#### Subscription Tiers
- Multiple tier support per outpost
- Configurable pricing and duration
- Three duration options:
  - Weekly (7 days): `DURATION_WEEK = 1`
  - Monthly (30 days): `DURATION_MONTH = 2`
  - Yearly (365 days): `DURATION_YEAR = 3`

#### Subscription Data Structure
```move
struct Subscription {
    tier_id: u64,
    start_time: u64,
    end_time: u64,
}

struct SubscriptionTier {
    name: String,
    price: u64,
    duration: u64,
}
```

#### Key Functions
```move
// Create a new subscription tier
create_subscription_tier(
    creator: &signer,
    outpost: Object<OutpostData>,
    tier_name: String,
    price: u64,
    duration: u64,
)

// Subscribe to a tier
subscribe(
    subscriber: &signer,
    outpost: Object<OutpostData>,
    tier_id: u64,
    referrer: Option<address>
)

// Cancel subscription
cancel_subscription(
    subscriber: &signer,
    outpost: Object<OutpostData>
)

// Verify subscription status
verify_subscription(
    subscriber: address,
    outpost: Object<OutpostData>,
    tier_id: u64
): bool

// Get subscription details
get_subscription(
    subscriber: address,
    outpost: Object<OutpostData>
): (u64, u64, u64) // Returns (tier_id, start_time, end_time)
```

#### Fee Distribution
When a user subscribes:
- Protocol fee: 4% to treasury
- Subject fee: 8% to outpost owner
- Referral fee: 2% to referrer (if provided)

#### Subscription Management
1. **Creation**:
   - Outpost owners can create multiple tiers
   - Each tier has unique name, price, and duration
   - Tiers cannot share names within an outpost

2. **Subscription Process**:
   - Users select tier and optional referrer
   - Fees are automatically distributed
   - Subscription period starts immediately
   - End time calculated based on duration

3. **Validation**:
   - Active subscriptions checked by tier_id and end_time
   - Prevents duplicate subscriptions
   - Validates tier existence and ownership

4. **Cancellation**:
   - Subscribers can cancel at any time
   - No partial refunds implemented
   - Emits cancellation event

#### Events
```move
struct SubscriptionEvent {
    subscriber: address,
    target_or_outpost: address,
    tier: String,
    duration: u64,
    price: u64,
    referrer: Option<address>,
}

struct SubscriptionCreatedEvent {
    outpost_addr: address,
    subscriber: address,
    tier_id: u64,
    timestamp: u64
}

struct SubscriptionCancelledEvent {
    outpost_addr: address,
    subscriber: address,
    tier_id: u64,
    timestamp: u64
}
```

### Outpost Management
```move
create_outpost(creator: &signer, name: String, description: String, uri: String)
toggle_emergency_pause(owner: &signer, outpost: Object<OutpostData>)
```

### CheerOrBoo Actions
```move
cheer_or_boo(sender: &signer, target: address, participants: vector<address>, is_cheer: bool, amount: u64, target_allocation: u64, unique_identifier: vector<u8>)
```

## Development Setup

### Prerequisites
- movement CLI
- Move compiler
- Node.js (v16+)

### Installation
```bash
npm install
```

### Testing
```bash
movement move test
```

### Deployment
```bash
movement move publish --profile podium
movement move run \
  --profile podium \
  --function-id 'podium::PodiumProtocol::initialize'
```

## Security Considerations

1. **Access Control**
   - Admin-only functions protected
   - Owner verification for outpost operations
   - Balance checks for all transfers

2. **Economic Security**
   - Fee limits enforced
   - Bonding curve parameters fixed
   - Vault system for redemptions

3. **Emergency Controls**
   - Pause functionality per outpost
   - Admin override capabilities
   - Error handling with custom codes

## Events and Monitoring

The protocol emits events for all major operations:
- Pass purchases and sales
- Subscription changes
- Outpost updates
- Cheer/Boo interactions
- Administrative actions

## Known Limitations

1. **Trading**
   - No slippage protection
   - Fixed bonding curve parameters
   - Single asset symbol ("T1")

2. **Subscriptions**
   - No maximum tier limit
   - Fixed duration options
   - No partial refunds

3. **CheerOrBoo**
   - Fixed fee percentage
   - Hardcoded fee recipient
   - No upgradability

## Future Improvements

1. **Trading Enhancements**
   - Unique asset symbols per target

2. **Subscription Updates**
   - Configurable tier limits
   - Flexible duration options
   - Partial refund mechanism

3. **CheerOrBoo Upgrades**
   - Configurable fees
   - Dynamic fee recipient
   - Upgradeable architecture