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

### PodiumPass
Core subscription and lifetime access management system.
- Manages lifetime passes and temporary subscriptions
- Handles buying/selling of passes
- Controls fee distribution
- Implements bonding curve for pass pricing
- Verifies access rights

### PodiumPassCoin
Token implementation for lifetime passes.
- Creates fungible tokens for lifetime access
- Handles minting and burning logic
- Manages trading/transferability of passes
- Tracks pass ownership and balances

### PodiumOutpost
Outpost management and access control system.
- Creates and manages named outposts
- Stores metadata (name, description, URI)
- Tracks ownership and permissions
- Handles access verification
- Supports custom pricing
- Provides administrative controls

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
