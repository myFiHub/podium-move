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

### Dependencies

- Aptos Token Objects: Collection and token management
- Aptos Framework: Core functionality (events, coins, objects)
- Aptos Fungible Asset: Token implementation