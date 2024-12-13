# Podium Protocol & CheerOrBoo

A decentralized protocol suite built on Movement, including subscription management and social tipping features.

##Podium
Podium's foundation is simple yet transformative: content creators and audiences should actively shape and own the conversations they engage in. Our “Showtime at Apollo”-style moderation system allows listeners to influence speaker time by paying to adjust it in real-time, creating an organic attention economy where creators and participants are rewarded for their contributions. This breaks the traditional passive consumption model, empowering users to become part of the content itself.
In the future, social media will shift from passive listening to active participation. Platforms like Podium will allow users to influence conversations, while Web3 technology enables decentralized ownership of engagement. Podium is leading this shift, turning engagement into a monetizable experience for both creators and audiences.
Our key assumptions are that users want more control over conversations, creators need better monetization tools, and Web3 adoption will grow.


## Contracts

- **PodiumPass**: Core subscription and lifetime access management
- **PodiumPassCoin**: Token implementation for lifetime passes
- **PodiumOutpost**: Outpost management and access control
- **CheerOrBooV2**: Social tipping and reward distribution system


Podium Pass
// Core functionality:
Manages lifetime passes purchases for target accounts/addresses
Manages temporary subscriptions for target accounts/addresses and outposts
Handles buying/selling of passes
Is the initiatior of Mints(buys) and redemption(sell) of lifetime passes as the owner of that functionality in PodiumPassCoin
Controls fee distribution
Verifies access rights
Bonding curve for pass pricing (buying and selling)
Subscription management
Fee distribution (protocol, subject, referral)
Access verification for both passes and subscriptions
Supports subscription different tiers that can be set by Target Accounts/Addresses or the Owner of Outposts
Lifetime passes can only be minted and redeemed in whole values through Podium Pass
tracks subscription and lifetime pass ownership

Podium Pass Coin
// Core functionality:
Creates fungible tokens for lifetime access
The underlying logic for minting, burning
Contract responsible for trading /transferability of passes
Tracks pass ownership and balances

Podium Outposts
// Core functionality
- Create named outposts with unique identifiers (can be created at time of purchase)
- Store metadata (name, description, URI)
- Track ownership and permissions
- Support custom pricing for outposts by name/unique identifier
// Access features
- Verify outpost ownership
- Verify outpost access
- Verify outpost metadata
// Event tracking
- Outpost creation events
- Ownership transfer events
- Price update events
- Metadata update events
- Fee configuration events
// Admin capabilities
- Update pricing
- Modify metadata
- Emergency controls
- Fee configuration



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


Movement Commands

Usage: movement <COMMAND>

Commands:
  account     Tool for interacting with accounts
  config      Tool for interacting with configuration of the Movement CLI tool
  genesis     Tool for setting up an Aptos chain Genesis transaction
  governance  Tool for on-chain governance
  info        Show build information about the CLI
  init        Tool to initialize current directory for the Movement tool
  key         Tool for generating, inspecting, and interacting with keys
  move        Tool for Move smart contract related operations
  multisig    Tool for interacting with multisig accounts
  node        Tool for operations related to nodes
  stake       Tool for manipulating stake and stake pools
  update      Update the CLI or other tools it depends on
  help        Print this message or the help of the given subcommand(s)

Options:
  -h, --help     Print help
  -V, --version  Print version


 movement init --help
Tool to initialize current directory for the Movement tool

Configuration will be pushed into .movement/config.yaml

Usage: movement init [OPTIONS]

Options:
      --network <NETWORK>
          Network to use for default settings

          If custom `rest_url` and `faucet_url` are wanted, use `custom`

      --rest-url <REST_URL>
          URL to a fullnode on the network

      --faucet-url <FAUCET_URL>
          URL for the Faucet endpoint

      --faucet-auth-token <FAUCET_AUTH_TOKEN>
          Auth token, if we're using the faucet. This is only used this time, we don't store it

          [env: FAUCET_AUTH_TOKEN=]

      --skip-faucet
          Whether to skip the faucet for a non-faucet endpoint

      --ledger
          Whether you want to create a profile from your ledger account

          Make sure that you have your Ledger device connected and unlocked, with the Aptos app installed and opened. You must also enable "Blind Signing" on your device to sign transactions from the CLI.

      --derivation-path <DERIVATION_PATH>
          Derivation Path of your account in hardware wallet

          e.g format - m/44\'/637\'/0\'/0\'/0\' Make sure your wallet is unlocked and have Aptos opened

      --derivation-index <DERIVATION_INDEX>
          Index of your account in hardware wallet

          This is the simpler version of derivation path e.g `format - [0]` we will translate this index into `[m/44'/637'/0'/0'/0]`

      --random-seed <RANDOM_SEED>
          The seed used for key generation, should be a 64 character hex string and only used for testing

          If a predictable random seed is used, the key that is produced will be insecure and easy to reproduce.  Please do not use this unless sufficient randomness is put into the random seed.

      --private-key-file <PRIVATE_KEY_FILE>
          Signing Ed25519 private key file path

          Encoded with type from `--encoding` Mutually exclusive with `--private-key`

      --private-key <PRIVATE_KEY>
          Signing Ed25519 private key

          Encoded with type from `--encoding` Mutually exclusive with `--private-key-file`

      --profile <PROFILE>
          Profile to use from the CLI config

          This will be used to override associated settings such as the REST URL, the Faucet URL, and the private key arguments.

          Defaults to "default"

      --assume-yes
          Assume yes for all yes/no prompts

      --assume-no
          Assume no for all yes/no prompts

      --encoding <ENCODING>
          Encoding of data as one of [base64, bcs, hex]

          [default: hex]

  -h, --help
          Print help (see a summary with '-h')

  -V, --version
          Print version


movement account --help
Tool for interacting with accounts

This tool is used to create accounts, get information about the account's resources, and transfer resources between accounts.

Usage: movement account <COMMAND>

Commands:
  create                           Create a new account on-chain
  create-resource-account          Create a resource account on-chain
  derive-resource-account-address  Derive the address for a resource account
  fund-with-faucet                 Fund an account with tokens from a faucet
  balance                          Show the account's balance of different coins
  list                             List resources, modules, or balance owned by an address
  lookup-address                   Lookup the account address through the on-chain lookup table
  rotate-key                       Rotate an account's authentication key
  transfer                         Transfer APT between accounts
  help                             Print this message or the help of the given subcommand(s)

Options:
  -h, --help
          Print help (see a summary with '-h')

  -V, --version
          Print version
