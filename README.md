# Podium Protocol & CheerOrBoo

A decentralized protocol suite built on Movement, including subscription management and social tipping features.

## Overview

### Podium
Podium's foundation is simple yet transformative: content creators and audiences should actively shape and own the conversations they engage in. Our "Showtime at Apollo"-style moderation system allows listeners to influence speaker time by paying to adjust it in real-time, creating an organic attention economy where creators and participants are rewarded for their contributions.

This breaks the traditional passive consumption model, empowering users to become part of the content itself. In the future, social media will shift from passive listening to active participation. Platforms like Podium will allow users to influence conversations, while Web3 technology enables decentralized ownership of engagement.

**Key Assumptions:**
- Users want more control over conversations
- Creators need better monetization tools
- Web3 adoption will continue to grow

## Smart Contracts

## Protocol Architecture

### Component Hierarchy

1. **PodiumOutpost (Base Layer)**
   - Collection and outpost management
   - Deterministic addressing
   - Access control foundation

2. **PodiumPassCoin (Token Layer)**
   - Fungible asset implementation
   - Pass token management
   - Balance and transfer logic

3. **PodiumPass (Business Logic Layer)**
   - Subscription management
   - Pass trading mechanics
   - Fee distribution
   - Access verification

### Key Features

- **Deterministic Addressing**: Predictable outpost addresses based on creator and name
- **Flexible Subscriptions**: Support for both temporary and lifetime access
- **Dynamic Pricing**: Bonding curve for pass prices
- **Referral System**: Built-in referral rewards
- **Emergency Controls**: Pause functionality for security
- **Fee Distribution**: Automated fee splitting between protocol, creators, and referrers

### CheerOrBooV2
Social tipping and reward distribution system.

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
