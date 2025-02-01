Podium Tokenomics: Balancing Exclusivity and Accessibility

Introduction
Podium introduces a unique tokenomics model designed to drive adoption, incentivize engagement, and provide long-term sustainability for its platform. At the core of this model is a bonding curve for lifetime passes combined with a flexible subscription system. This hybrid approach ensures early adopters gain exclusive benefits while enabling a scalable, inclusive solution for wider user adoption.

Bonding Curve Model
The bonding curve uses a summation-based formula to determine the price of passes, carefully designed to achieve three key objectives:
1. Keep early prices accessible (1-10 APT range for first adopters)
2. Scale exponentially with supply to create exclusivity
3. Enable fractionalization while maintaining utility requirements

The formula:
Price = max(INITIAL_PRICE, (DEFAULT_WEIGHT_B/BPS) × Summation × INITIAL_PRICE)

Where:
- Summation = (DEFAULT_WEIGHT_A/BPS) × ((n × (n + 1) × (2n + 1)) / 6)
- n = current_supply + DEFAULT_WEIGHT_C - 1
- INITIAL_PRICE = 100,000,000 (1 APT in OCTA units)
- DEFAULT_WEIGHT_A = 4,500 (45% in basis points)
- DEFAULT_WEIGHT_B = 3,500 (35% in basis points)
- DEFAULT_WEIGHT_C = 2 (Constant offset for supply adjustment)
- BPS = 10,000 (100% in basis points)

Price Progression:
- First 10 passes: 1-10 APT range, making it accessible for early adopters
- Supply 10-50: Gradual increase to establish value
- Supply 50-100: Accelerated growth to drive exclusivity
- Supply 100+: Exponential pricing to mirror high-end club models

Fee Structure
The protocol implements a comprehensive fee structure:

1. Protocol Fees:
   - Pass Trading: Up to 4% (400 basis points)
   - Subscription: Up to 5% (500 basis points)

2. Subject/Creator Fees:
   - Pass Trading: Up to 8% (800 basis points)
   - Subscription: Variable based on tier configuration

3. Referral Fees:
   - Pass Trading: Up to 2% (200 basis points)
   - Subscription: Up to 10% (1000 basis points)

All fees are configurable within these maximum limits and can be adjusted by protocol governance.

Pass System
1. Pass Units:
   - Minimum Unit: 1 whole pass (100,000,000 units internally)
   - Passes are fungible and can be traded
   - Each pass is specific to a target/outpost

2. Pass Trading:
   - Buy: Users pay current bonding curve price plus fees
   - Sell: Users receive current bonding curve price minus fees
   - All trades contribute to the redemption vault for liquidity

3. Fractionalization Strategy:
   - Trading: Passes can be fractionalized for improved liquidity
   - Usage: Requires whole pass units to access features
   - Benefits: Enables partial ownership while maintaining utility value
   - Target: 5-10% of audience expected to hold whole passes

Creator Economy Integration
Based on current creator platform metrics (2023-2024):

1. Audience Segmentation:
   - Core Supporters: 5-10% (prime candidates for lifetime passes)
   - Regular Subscribers: 15-25% (subscription tier targets)
   - Casual Users: 65-80% (potential future converts)

2. Platform Comparisons:
   Patreon Insights (2023-2024):
   - Average Creator Base: 10-20 active patrons
   - Revenue Model: Recurring small amounts per patron
   - Niche Variation: Significant differences across content types
   - Patreon has scaled to 8M+ monthly active supporters and paid over $8B to creators.


   Twitch Metrics:
   - Typical Range: 5-15 subscribers for small/mid-tier
   - Revenue Mix: Subscriptions + bits + donations + ads
   - Growth Pattern: Gradual build of dedicated community

3. Lifetime Value Proposition:
   - Pricing Multiple: 10-15x monthly subscription equivalent
   - Target Conversion: 5-10% of active audience
   - Limited Availability: Creates scarcity and urgency
   - Enhanced Benefits: Exclusive access and perks

Subscription System
1. Tier Structure:
   - Multiple tiers per outpost
   - Configurable prices and durations
   - Duration options: Weekly, Monthly, Yearly

2. Subscription Features:
   - Auto-renewable subscriptions
   - Referral rewards
   - Emergency pause capability
   - Flexible fee distribution

3. Hybrid Model Benefits:
   - Immediate Capital: Through lifetime passes
   - Recurring Revenue: Via subscription tiers
   - Market Testing: Limited-time lifetime offers
   - Community Building: Tiered engagement levels

Outpost System
1. Creation:
   - Fixed creation price
   - Customizable name, description, and URI
   - Built-in fee share mechanism (5% default)

2. Management:
   - Emergency pause capability
   - Price updates
   - Subscription tier management
   - Custom fee configurations

Why This Model Works
1. Sustainability:
   - Bonding curve ensures value appreciation with adoption
   - Subscription system provides recurring revenue
   - Fee structure incentivizes all participants
   - Balanced mix of lifetime and recurring revenue

2. Flexibility:
   - Multiple monetization options (passes and subscriptions)
   - Configurable tiers and pricing
   - Referral incentives for growth
   - Fractionalization options for improved liquidity

3. Scalability:
   - Automated market making through bonding curve
   - Self-adjusting pricing based on demand
   - Efficient liquidity management through redemption vault
   - Gradual transition from passes to subscriptions

4. Creator Incentives:
   - Multiple revenue streams
   - Customizable fee structures
   - Built-in growth mechanisms
   - Community-driven value appreciation

Market Validation
1. Creator Platform Trends:
   - Growing acceptance of hybrid monetization
   - Shift toward community ownership
   - Increased value of exclusive access
   - Premium pricing for dedicated supporters

2. Success Metrics:
   - Sustainable creator income
   - Community engagement
   - Platform growth
   - Value appreciation

Conclusion
The Podium tokenomics model creates a balanced, dynamic ecosystem that rewards early participation while enabling ongoing growth. By carefully calibrating the bonding curve for early accessibility and later exclusivity, combined with flexible subscriptions, the platform provides creators with powerful tools for community building and monetization. The hybrid approach of fractional trading with whole-unit utility ensures liquidity while maintaining value propositions. This comprehensive strategy, backed by current creator economy metrics and trends, positions Podium for sustainable growth and long-term success in the evolving digital content landscape.

