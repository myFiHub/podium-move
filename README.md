# Podium Protocol & CheerOrBoo

A decentralized protocol suite built on Movement, including subscription management, pass trading, and social tipping features.

## Overview

### Podium
Podium's foundation enables content creators and audiences to actively shape and own their conversations. The protocol implements:
1. Pass trading with bonding curve pricing
2. Flexible subscription management
3. Outpost creation and management
4. Fee distribution with referral incentives

### CheerOrBoo
A social tipping system that allows audience participation through positive (Cheer) or negative (Boo) feedback, with automatic reward distribution.

## Smart Contract Architecture

### 1. PodiumPass
Core business logic handling pass trading and subscriptions.

**Key Features:**
- Bonding curve-based pass pricing
- Multi-tier subscription management
- Automated fee distribution
- Vault system for pass redemption
- Referral system integration

**Test Coverage:**
1. **Pass Operations**
   - `test_buy_pass`: Pass purchase and minting
   - `test_pass_sell`: Pass redemption mechanics
   - `test_pass_trading`: Trading between users
   - `test_account_pass_operations`: Account-specific pass handling
   - `test_outpost_pass_operations`: Outpost-specific pass operations

2. **Subscription Management**
   - `test_subscription`: Basic subscription creation/verification
   - `test_subscription_flow`: Complete subscription lifecycle
   - `test_subscription_expiration`: Time-based expiration
   - `test_duplicate_subscription`: Duplicate prevention
   - `test_subscription_with_referral`: Referral system
   - `test_subscribe_nonexistent_tier`: Error handling

3. **Administrative Controls**
   - `test_admin_price_control`: Price management
   - `test_outpost_price_permissions`: Access control
   - `test_outpost_creation_flow`: Outpost initialization

### 2. PodiumOutpost
Handles outpost (creator space) management.

**Key Features:**
- Deterministic addressing
- Collection management
- Metadata handling
- Emergency controls

**Test Coverage:**
- Outpost creation and initialization
- Price updates and permissions
- Metadata management
- Emergency pause functionality

### 3. PodiumPassCoin
Fungible asset implementation for passes.

**Key Features:**
- Custom token implementation
- Balance tracking
- Transfer management
- Mint/burn capabilities

### 4. CheerOrBoo
A social tipping system that enables real-time audience feedback through financial incentives.

**Key Features:**
- Dual action system (Cheer/Boo)
- Configurable fee distribution
- Multi-participant reward splitting
- Event emission for tracking

**Implementation Details:**
```move
cheer_or_boo(
    sender: &signer,
    target: address,
    participants: vector<address>,
    is_cheer: bool,
    amount: u64,
    target_allocation: u64,
    unique_identifier: vector<u8>
)
```

**Core Functionality:**
- Flexible reward distribution between target and participants
- Protocol fee handling (5% default)
- Automatic account registration and coin store initialization
- Event emission for analytics

**Test Coverage:**
1. **Basic Operations (`test_cheer`, `test_boo`)**
   - Verifies correct fee calculations (5%)
   - Validates reward distribution
   - Checks balance updates for all parties
   - Tests both positive and negative interactions

2. **Economic Security (`test_insufficient_balance`)**
   - Validates balance checks
   - Tests failure conditions
   - Verifies error handling

3. **Distribution Logic**
   - Tests multi-participant splitting
   - Verifies target allocation percentages
   - Validates rounding behavior

4. **Event Emission**
   - CheerEvent and BooEvent verification
   - Unique identifier tracking
   - Participant list handling

## Subscription Model

Podium implements a streamlined subscription system using a simple yet effective resource model.

### Design Philosophy
Subscriptions are implemented as pure data resources rather than transferable assets, reflecting their true nature as time-bound permissions.

#### Key Characteristics
- **Direct Resource Ownership**: Subscriptions stored as data resources
- **Simple Data Mapping**: Straightforward subscriber → subscription details relationship
- **Non-Transferable**: Subscriptions bound to specific subscribers
- **Permission-Based**: Access control through outpost ownership verification

## Development Setup

### Prerequisites
- Movement CLI
- Node.js (v16+)
- TypeScript
- Yarn or npm

### Installation
npm install

### Deployment

The deployment script supports selective deployment of components and a dry-run mode for testing:

```bash
# Deploy CheerOrBoo only
npm run deploy cheerorboo

# Deploy Podium Protocol only (PodiumOutpost, PodiumPassCoin, PodiumPass)
npm run deploy podium

# Deploy everything
npm run deploy all

# Test deployment without making transactions (dry-run)
npm run deploy podium --dry-run
npm run deploy cheerorboo --dry-run
npm run deploy all --dry-run
```

### Deployment Order
When deploying Podium Protocol, modules are deployed and initialized in this order:
1. PodiumOutpost - Handles outpost (creator space) management
2. PodiumPassCoin - Fungible asset implementation for passes
3. PodiumPass - Core business logic for pass trading and subscriptions

### Initial Configuration
During deployment, the system is initialized with:
- PodiumOutpost collection creation
- Initial outpost price set to 1000 APT
- PodiumPassCoin module initialization
- PodiumPass module initialization with default parameters

## Testing Framework

### PodiumPass Test Coverage

#### Core Pass Operations
1. **Pass Creation & Purchase (`test_buy_pass`)**
   - Validates pass minting process
   - Verifies token creation and ownership
   - Checks correct balance updates
   - Tests deterministic address derivation

2. **Subscription Management**
   - `test_subscription`: Basic subscription creation and verification
   - `test_subscription_flow`: Complete subscription lifecycle
   - `test_subscription_expiration`: Time-based expiration mechanics
   - `test_duplicate_subscription`: Duplicate prevention

3. **Pass Trading System**
   - `test_pass_trading`: Pass transfers between users
   - `test_unauthorized_mint`: Security checks
   - `test_mint_and_transfer`: Complete trading flow

4. **Referral System**
   - `test_subscription_with_referral`: Referral fee distribution
   - Validates correct fee calculations
   - Verifies payment distributions

5. **Administrative Controls**
   - `test_outpost_creation_flow`: Outpost initialization
   - `test_admin_price_control`: Price management
   - `test_outpost_price_permissions`: Access control
   - `test_outpost_purchase_flow`: Purchase process validation

### Test Setup

#### Prerequisites

### Key Test Files
- `PodiumPass_test.move`: Core protocol tests
- `PodiumOutpost_test.move`: Outpost management tests
- `PodiumPassCoin_test.move`: Token implementation tests
- `CheerOrBoo_test.move`: Tipping system tests

## Security Features

1. **Access Control**
   - Role-based permissions
   - Owner-only operations
   - Admin controls

2. **Economic Security**
   - Fee limits
   - Price controls
   - Vault system for redemptions

3. **Emergency Controls**
   - Pause functionality
   - Admin override capabilities
   - Error handling

## Events and Monitoring

The protocol emits events for:
- Pass purchases and sales
- Subscription changes
- Outpost updates
- Cheer/Boo interactions
- Administrative actions

## Integration Points

1. **Frontend Integration**
   - Pass trading interface
   - Subscription management
   - Tipping functionality

2. **Analytics Integration**
   - Event monitoring
   - Price tracking
   - User activity analysis


deploy
movement move publish --profile podium