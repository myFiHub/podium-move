# Podium Protocol & CheerOrBoo

A decentralized protocol suite built on Movement, including subscription management and social tipping features.

## Contracts

- **PodiumPass**: Core subscription and lifetime access management
- **PodiumPassCoin**: Token implementation for lifetime passes
- **PodiumOutpost**: Outpost management and access control
- **CheerOrBooV2**: Social tipping and reward distribution system

## Prerequisites

- Movement CLI
- Node.js (v16+)
- TypeScript
- Yarn or npm

## Getting Started

### 1. Configuration

Create your config file:
bash
cp .movement/config.yaml.example .movement/config.yaml

2. Update the config with your deployment keys:
yaml
profiles:
deployer:
network: Custom
private_key: "YOUR_PRIVATE_KEY"
account: YOUR_ACCOUNT_ADDRESS
rest_url: "https://aptos.testnet.porto.movementlabs.xyz/v1"
faucet_url: "https://fund.testnet.porto.movementlabs.xyz/"

## Installation
npm install

## Deployment
Deploy specific modules:

bash
Deploy CheerOrBoo
npm run deploy cheerorboo
Deploy Podium system
npm run deploy podium
Deploy all modules
npm run deploy all
bash
movement move test
bash
Test CheerOrBoo functionality
npm run test
Check deployment status
npm run check

## Contract Addresses

- CheerOrBooV2: `0xb20104c986e1a6f6d270f82dc6694d0002401a9c4c0c7e0574845dcc59b05cb2`
- FiHub Fee Address: `0xc898a3b0a7c3ddc9ff813eeca34981b6a42b0918057a7c18ecb9f4a6ae82eefb`

## Development

### Project Structure
├── sources/ # Move smart contracts
├── scripts/ # Deployment and test scripts
├── .movement/ # Movement configuration
└── tests/ # Test files


### Key Commands
- `npm run deploy`: Deploy contracts
- `npm run test`: Run integration tests
- `npm run check`: Verify deployments

## License

MIT