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
movement move test --filter PodiumProtocol
movement move test --filter upgrade
movement move test --filter CheerOrBoo
```

### Deployment
```bash
movement move publish --profile podium
movement move run \
  --profile podium \
  --function-id 'podium::PodiumProtocol::initialize'
```
### Upgrade
```bash
movement move publish   --profile podium   --included-artifacts sparse   --assume-yes   --named-addresses podium=0x......af47,fihub=0x9.........b

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

## Fee Structure

### Protocol Fees
The protocol implements separate fee structures for different operations:

1. **Subscription Fees**
   - Protocol Fee: 5% (500 basis points)
   - Referrer Fee: 10% (1000 basis points)
   - Subject Fee: Remaining amount (85% without referrer, 75% with referrer)

2. **Pass Trading Fees**
   - Buy:
     * Protocol Fee: Up to 4% (configurable)
     * Subject Fee: Up to 8% (configurable)
     * Referral Fee: Up to 2% (configurable) if applicable
   - Sell:
     * Protocol Fee: Up to 4% (configurable)
     * Subject Fee: Up to 8% (configurable)
     * 5% sell discount applied to base price

### Fee Management
Fees can be updated by protocol admin through the following functions:
```move
// Update subscription protocol fee (in basis points)
update_protocol_subscription_fee(admin: &signer, new_fee: u64)

// Update pass trading protocol fee (in basis points)
update_protocol_pass_fee(admin: &signer, new_fee: u64)

// Update referrer fee (in basis points)
update_referrer_fee(admin: &signer, new_fee: u64)
```

View functions to check current fees:
```move
get_protocol_subscription_fee(): u64
get_protocol_pass_fee(): u64
get_referrer_fee(): u64
```

### Fee Constraints
- All fees are specified in basis points (1/100th of a percent)
- Maximum fee: 10000 basis points (100%)
- Fees can only be updated by protocol admin
- Fee updates require validation checks

### Trading Mechanics
The protocol implements a bonding curve mechanism for pass trading with the following mechanics:

### Bonding Curve
- Uses a polynomial bonding curve formula to calculate prices
- Price increases as supply increases and decreases as supply decreases
- Key parameters:
  * Weight A: 80% - Controls curve steepness
  * Weight B: 50% - Controls price scaling
  * Weight C: 2 - Supply adjustment factor
  * Initial price: 1 APT

### Buy Mechanics
1. Price is calculated based on current supply and amount being purchased
2. Total cost includes:
   - Base price from bonding curve
   - Protocol fee (up to 4%)
   - Subject fee (up to 8%) 
   - Referral fee if applicable (up to 2%)
3. Base price is added to redemption vault
4. Fees are distributed to respective recipients
5. Pass tokens are minted to buyer

### Sell Mechanics
1. Price is calculated with 5% discount from bonding curve
2. Seller receives:
   - Base discounted price minus fees
   - Protocol fee deducted (up to 4%)
   - Subject fee deducted (up to 8%)
3. Redemption coins withdrawn from vault
4. Pass tokens are burned
5. Fees distributed to protocol and subject

### Key Features
- Automatic price discovery through bonding curve
- Guaranteed liquidity through redemption vault
- Fee sharing between protocol, subjects and referrers
- Built-in sell discount to encourage trading
- Emergency pause functionality for outposts

### Stats Tracking
- Total supply tracked per target/outpost
- Last trade price recorded
- Events emitted for buys and sells

## Testing

## Test Coverage

### Protocol Core Tests

1. **Initialization Tests**
- `test_initialization`: Verifies protocol setup, treasury configuration, and initial parameters
- `test_admin_functions`: Tests admin-only functions and access control
- `test_emergency_pause`: Validates emergency pause functionality and state changes

2. **Outpost Management Tests**
- `test_outpost_creation_flow`: Validates outpost creation, pricing, and ownership
- `test_outpost_price_management`: Tests outpost creation costs and treasury payments
- `test_outpost_metadata`: Verifies proper metadata handling and uniqueness constraints
- `test_outpost_ownership`: Checks ownership transfers and permissions

3. **Pass Trading Tests**
- `test_bonding_curve_sequence`: Tests bonding curve pricing through buy/sell sequence
- `test_pass_trading`: Validates pass purchases, sales, and balance updates
- `test_fee_distribution`: Verifies correct fee splits between protocol, creator, and referrer
- `test_vault_redemption`: Tests vault system for pass redemptions

4. **Subscription System Tests**
- `test_subscription_tier_creation`: Validates tier creation and constraints
- `test_subscription_management`: Tests subscription purchases and renewals
- `test_subscription_cancellation`: Verifies subscription cancellation logic
- `test_subscription_validation`: Checks subscription status and access control

5. **Fee Management Tests**
- `test_protocol_fees`: Validates fee calculations and distributions
- `test_referral_fees`: Tests referral system and bonus distributions
- `test_fee_updates`: Verifies admin fee update functionality

6. **Balance and Fund Safety Tests**
- `test_insufficient_balance`: Validates proper handling of insufficient funds
- `test_transfer_safety`: Tests safe transfer patterns and balance checks
- `test_vault_management`: Verifies vault balance tracking and withdrawals

### CheerOrBoo Tests

The test suite verifies the core functionality and edge cases of the CheerOrBoo system:

#### Core Functionality Tests
1. `test_cheer`
   - Verifies basic cheering mechanism
   - Tests 50/50 split between target and participants
   - Confirms correct fee deduction (5%)
   - Validates even distribution among participants

2. `test_boo`
   - Tests negative feedback mechanism
   - Verifies 30/70 target/participant split
   - Ensures proper fee handling
   - Checks single participant distribution

#### Distribution Scale Tests
1. `test_small_participants_distribution`
   - Tests distribution for small groups (10, 25, 50 participants)
   - Verifies consistent distribution across multiple iterations
   - Ensures proper cleanup between tests

2. `test_medium_participants_distribution`
   - Validates medium-scale distribution (100, 250, 500 participants)
   - Tests system stability with larger groups
   - Verifies consistent per-participant amounts

3. `test_large_participants_distribution`
   - Stress tests with 1000 participants
   - Validates system performance at scale
   - Ensures fair distribution even with large numbers

#### Edge Cases and Limits
1. `test_max_participants_limit`
   - Verifies enforcement of maximum participant limit
   - Tests system's boundary conditions
   - Ensures graceful failure when limit exceeded

2. `test_empty_participants`
   - Validates handling of empty participant lists
   - Tests system's input validation
   - Ensures proper error handling

3. `test_insufficient_balance`
   - Verifies balance checking
   - Tests insufficient funds scenarios
   - Ensures proper error handling

4. `test_rounding_behavior`
   - Tests distribution with indivisible amounts
   - Verifies remainder handling
   - Ensures no funds are lost in rounding

5. `test_full_target_allocation`
   - Tests 100% allocation to target
   - Verifies fee handling without participants
   - Validates extreme allocation scenarios

#### Distribution Verification
- Each test verifies correct fee deduction (5%)
- Validates even distribution among participants
- Checks remainder handling
- Ensures no funds are lost in the process



## Initialization Flow

### Dependency Management
```bash
# Recommended for faster builds - use local framework clone
git clone --depth 1 --branch mainnet https://github.com/movement-network/move /tmp/movement-framework

# Update Move.toml dependencies:
[dependencies]
AptosFramework = { local = "/tmp/movement-framework/aptos-framework" }
AptosStdlib = { local = "/tmp/movement-framework/aptos-stdlib" }
MoveStdlib = { local = "/tmp/movement-framework/move-stdlib" }
```

### Core Initialization Sequence
1. **Protocol Initialization** (First-time setup)
```bash
movement move run \
  --profile mainnet \
  --function-id 'podium::PodiumProtocol::initialize'
```

2. **Outpost Creation** (Per-content creator)
```move
public entry fun create_outpost(
    creator: &signer,
    name: String,
    description: String,
    uri: String
) {
    // Requires protocol initialization
    // Automatically handles:
    // - Object initialization
    // - Token creation
    // - Royalty setup
}
```

3. **Subscription Tier Setup** (Per-outpost)
```move
public entry fun create_subscription_tier(
    owner: &signer,
    outpost: Object<OutpostData>, 
    tier_name: String,
    price: u64,
    duration: u64
) {
    // Validates:
    // - Outpost ownership
    // - Tier name uniqueness
    // - Duration validity
}
```

## Testing Guidelines

### Key Test Patterns
```move
#[test(aptos_framework = @0x1, admin = @podium)]
fun test_outpost_lifecycle() {
    // 1. Protocol initialization
    // 2. Outpost creation
    // 3. Subscription tier setup
    // 4. Pass trading
    // 5. Emergency pause
}
```

### Test Initialization Sequence
1. Framework setup
2. Account creation
3. Protocol initialization
4. Outpost creation
5. Subscription tier creation

### Optimized Testing
```bash
# Parallel test execution
movement move test --num-threads 8

# Filter tests by module
movement move test --filter outpost

# Generate coverage report
movement move test --coverage
```

## Deployment Process

### Optimized Deployment
```bash
movement move publish \
  --profile mainnet \
  --assume-yes \
  --skip-fetch-latest-git-deps \
  --included-artifacts sparse \
  --named-addresses "podium=0xd2f0d0cf38a4c64620f8e9fcba104e0dd88f8d82963bef4ad57686c3ee9ed7aa"
```

### Post-Deployment Verification
```move
#[view]
public fun verify_initialization(): bool {
    exists<Config>(@podium) &&
    table::length(&borrow_global<Config>(@podium).outposts) > 0
}
```

## Common Error Reference

Code | Meaning | Resolution
-----|---------|------------
0x60002 | Missing ObjectCore | Ensure object initialization before token operations
0x10001 | Dependency Resolution | Use `--skip-fetch-latest-git-deps`
0x3000A | Insufficient Balance | Verify test account funding
0x4000C | Invalid Royalty | Check numerator/denominator values
0x5001F | Protocol Not Initialized | Call `initialize()` first
