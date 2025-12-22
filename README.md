# Cross-Chain Intent Bridge

A cross-chain intent system for bridging assets between Stacks, Bitcoin, and EVM chains. Uses solver-based execution with collateral requirements and verified bridge contracts.

## Clarity 4 Features Used

| Feature | Usage |
|---------|-------|
| `to-ascii?` | Generate human-readable cross-chain messages and intent payloads |
| `contract-hash?` | Verify bridge contracts match approved versions |
| `stacks-block-time` | Manage intent expiry, timeouts, and collateral locks |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         User                                 │
│  Creates intent: "Send 100 STX, receive 0.001 BTC"          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Intent Bridge                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  create-intent() → Lock source tokens                 │   │
│  │  to-ascii?() → Generate cross-chain payload          │   │
│  │  stacks-block-time → Set expiry                      │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Solver Network                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  fill-intent() → Lock collateral, commit to fill      │   │
│  │  Execute on destination chain                         │   │
│  │  Submit proof → Release source tokens                 │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Bridge Registry                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  contract-hash?() → Verify bridge contracts           │   │
│  │  Track routes and supported chains                    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## How It Works

### Intent-Based Bridging

1. **User creates intent**: Specifies source asset, destination chain, amounts, recipient
2. **Solver fills intent**: Locks collateral, commits to execute on destination
3. **Solver executes**: Sends tokens on destination chain
4. **Proof submitted**: Oracle/relayer confirms execution
5. **Settlement**: Solver receives source tokens, collateral unlocked

### Benefits Over Traditional Bridges

- **Speed**: Solvers can pre-fund, instant execution
- **Security**: Collateral > intent value ensures solver honesty
- **Flexibility**: Any token pair, any chain combination
- **Competition**: Multiple solvers compete for best rates

## Supported Chains

| Chain | ID | Status |
|-------|-----|--------|
| Stacks | 1 | ✅ Native |
| Bitcoin | 2 | ✅ Via sBTC |
| Ethereum | 3 | 🔄 Planned |
| Polygon | 4 | 🔄 Planned |
| Arbitrum | 5 | 🔄 Planned |
| Optimism | 6 | 🔄 Planned |

## Contract Functions

### Intent Bridge

```clarity
;; Create a cross-chain intent
(create-intent
    (source-asset <ft-trait>)
    (dest-chain uint)
    (dest-asset (string-ascii 64))
    (source-amount uint)
    (dest-amount uint)
    (recipient (string-ascii 128))
    (expiry-duration uint))

;; Fill an intent (solver)
(fill-intent (intent-id uint))

;; Confirm fill completion
(confirm-fill (intent-id uint) (proof (buff 256)))

;; Cancel unfilled intent
(cancel-intent (intent-id uint) (token <ft-trait>))
```

### Solver Functions

```clarity
;; Register as solver
(register-solver (collateral uint))

;; Add collateral
(add-collateral (amount uint))

;; Withdraw excess collateral
(withdraw-collateral (amount uint))
```

### Bridge Registry

```clarity
;; Verify bridge contract
(register-bridge (bridge-contract) (name) (source-chain) (dest-chains) (fee-bps))

;; Check bridge integrity
(verify-bridge-integrity (bridge-contract))

;; Get available routes
(get-routes (source-chain) (dest-chain))
```

### Read-Only Helpers

```clarity
;; Generate human-readable payload
(generate-cross-chain-payload (intent-id) (source-chain) (dest-chain) (amount))
;; Returns: "BRIDGE:1|SRC:1|DST:2|AMT:1000000"

;; Get intent message
(generate-intent-message (intent-id))
;; Returns: "Intent #1 for 1000000 units"

;; Check fillability
(is-intent-fillable (intent-id))

;; Get required collateral
(get-required-collateral (intent-id))
```

## Intent Lifecycle

```
PENDING → FILLED → CONFIRMED
    │        │
    │        └── DISPUTED (if solver fails)
    │
    └── CANCELLED (by user)
    └── EXPIRED (timeout)
```

## Collateral System

- **Minimum ratio**: 150% of intent value
- **Lock period**: Until fill confirmed or intent expires
- **Slashing**: Collateral slashed if solver fails to execute
- **Reputation**: Successful fills improve solver score

## Installation & Testing

```bash
cd crosschain-bridge
clarinet check
```

## Deployment

### Testnet Deployment

The contracts are configured for Clarity 4 (epoch 3.3) and ready for testnet deployment.

**Deployer Address:** `ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE`

**Contracts:**
- `bridge-registry.clar` - Registry of verified bridge contracts and supported chains
- `intent-bridge.clar` - Main intent bridge contract for cross-chain transfers
- `intent-executor.clar` - Executor contract for processing intents

To deploy to testnet:

```bash
# Generate deployment plan (already generated in deployments/default.testnet-plan.yaml)
clarinet deployments generate --testnet --medium-cost

# Fund the deployer address with testnet STX
# Get testnet tokens from: https://explorer.hiro.so/sandbox/faucet?chain=testnet

# Apply the deployment
clarinet deployments apply -p deployments/default.testnet-plan.yaml
```

**Deployment Costs:**
- bridge-registry: ~1.84 STX
- intent-bridge: ~1.84 STX
- intent-executor: ~1.84 STX
- **Total: ~5.52 STX**

## Example: Bridge STX to Bitcoin

```typescript
// 1. Register as solver
await registerSolver(10000000000); // 10,000 STX collateral

// 2. User creates intent
const intentId = await createIntent({
    sourceAsset: stxContract,
    destChain: CHAIN_BITCOIN,
    destAsset: "BTC",
    sourceAmount: 100000000, // 100 STX
    destAmount: 100000, // 0.001 BTC
    recipient: "bc1q...", // Bitcoin address
    expiryDuration: 86400 // 24 hours
});

// 3. Solver sees intent and fills
await fillIntent(intentId);

// 4. Solver executes on Bitcoin
const btcTxHash = await sendBitcoin(intent.recipient, intent.destAmount);

// 5. Submit proof and receive STX
await confirmFill(intentId, btcTxHash);
```

## Cross-Chain Message Format

Using `to-ascii?` for human-readable on-chain messages:

```
BRIDGE:123|SRC:1|DST:2|AMT:100000000
```

This format is:
- **Parseable**: Easy for off-chain indexers
- **Verifiable**: On-chain proof of intent parameters
- **Debuggable**: Human-readable for troubleshooting

## Security Features

1. **Contract Verification**: Bridge contracts verified via `contract-hash?`
2. **Collateral Requirements**: 150% minimum prevents under-collateralization
3. **Timeouts**: Intents expire, preventing locked funds
4. **Reputation System**: Track solver performance
5. **Dispute Resolution**: Admin can resolve contested fills

## Integration Notes

- Solvers need off-chain infrastructure to monitor intents
- Proof submission requires oracle/relayer for destination chain
- Consider running your own solver for guaranteed execution

## Hiro Chainhooks Integration

This project includes a **Hiro Chainhooks** implementation for real-time monitoring of cross-chain bridge activity, solver performance, and intent fulfillment metrics.

### Features

✅ **Real-time Intent Tracking**: Monitor intent creation, fills, confirmations, and cancellations
✅ **Solver Analytics**: Track solver registrations, collateral levels, and performance metrics
✅ **Bridge Fee Monitoring**: Monitor fees and collateral requirements across all chains
✅ **Volume Metrics**: Track cross-chain transfer volumes and route popularity
✅ **Reorg-Resistant**: Chainhook's built-in protection against blockchain reorganizations

### Tracked Events

| Event | Contract Function | Data Collected |
|-------|------------------|----------------|
| Intent Created | `create-intent` | Source asset, destination chain, amounts, expiry |
| Intent Filled | `fill-intent` | Solver, collateral locked, fill timestamp |
| Fill Confirmed | `confirm-fill` | Proof submitted, tokens released |
| Intent Cancelled | `cancel-intent` | Cancellation reason, refunded amount |
| Solver Registered | `register-solver` | Solver address, initial collateral |
| Collateral Added | `add-collateral` | Solver, amount added |
| Bridge Registered | `register-bridge` | Bridge contract, supported chains, fees |

### Analytics Output

The Chainhooks observer generates real-time analytics:

```json
{
  "uniqueUsers": 128,
  "totalIntents": 456,
  "fulfilledIntents": 398,
  "cancelledIntents": 43,
  "expiredIntents": 15,
  "totalVolume": 5000000000,
  "activeSolvers": 23,
  "totalCollateral": 150000000000,
  "averageFillTime": 180,
  "intents": [...],
  "solvers": [...],
  "timestamp": "2025-12-16T10:30:00.000Z"
}
```

### Quick Start

```bash
cd chainhooks
npm install
cp .env.example .env
# Edit .env with your configuration
npm start
```

For detailed setup and configuration, see [chainhooks/README.md](./chainhooks/README.md).

### Use Cases

- **Solver Dashboard**: Real-time monitoring of intent opportunities and solver performance
- **Bridge Analytics**: Track cross-chain volume, popular routes, and fee revenue
- **User Experience**: Monitor fill times and success rates for UX optimization
- **Compliance Monitoring**: Track all cross-chain transfers for regulatory reporting
- **Arbitrage Detection**: Identify profitable intents based on rate spreads
- **Risk Management**: Monitor collateral ratios and solver health metrics

## License

MIT License

## WalletConnect Integration

This project includes a fully-functional React dApp with WalletConnect v2 integration for seamless interaction with Stacks blockchain wallets.

### Features

- **🔗 Multi-Wallet Support**: Connect with any WalletConnect-compatible Stacks wallet
- **✍️ Transaction Signing**: Sign messages and submit transactions directly from the dApp
- **📝 Contract Interactions**: Call smart contract functions on Stacks testnet
- **🔐 Secure Connection**: End-to-end encrypted communication via WalletConnect relay
- **📱 QR Code Support**: Easy mobile wallet connection via QR code scanning

### Quick Start

#### Prerequisites

- Node.js (v16.x or higher)
- npm or yarn package manager
- A Stacks wallet (Xverse, Leather, or any WalletConnect-compatible wallet)

#### Installation

```bash
cd dapp
npm install
```

#### Running the dApp

```bash
npm start
```

The dApp will open in your browser at `http://localhost:3000`

#### Building for Production

```bash
npm run build
```

### WalletConnect Configuration

The dApp is pre-configured with:

- **Project ID**: 1eebe528ca0ce94a99ceaa2e915058d7
- **Network**: Stacks Testnet (Chain ID: `stacks:2147483648`)
- **Relay**: wss://relay.walletconnect.com
- **Supported Methods**:
  - `stacks_signMessage` - Sign arbitrary messages
  - `stacks_stxTransfer` - Transfer STX tokens
  - `stacks_contractCall` - Call smart contract functions
  - `stacks_contractDeploy` - Deploy new smart contracts

### Project Structure

```
dapp/
├── public/
│   └── index.html
├── src/
│   ├── components/
│   │   ├── WalletConnectButton.js      # Wallet connection UI
│   │   └── ContractInteraction.js       # Contract call interface
│   ├── contexts/
│   │   └── WalletConnectContext.js     # WalletConnect state management
│   ├── hooks/                            # Custom React hooks
│   ├── utils/                            # Utility functions
│   ├── config/
│   │   └── stacksConfig.js             # Network and contract configuration
│   ├── styles/                          # CSS styling
│   ├── App.js                           # Main application component
│   └── index.js                         # Application entry point
└── package.json
```

### Usage Guide

#### 1. Connect Your Wallet

Click the "Connect Wallet" button in the header. A QR code will appear - scan it with your mobile Stacks wallet or use the desktop wallet extension.

#### 2. Interact with Contracts

Once connected, you can:

- View your connected address
- Call read-only contract functions
- Submit contract call transactions
- Sign messages for authentication

#### 3. Disconnect

Click the "Disconnect" button to end the WalletConnect session.

### Customization

#### Updating Contract Configuration

Edit `src/config/stacksConfig.js` to point to your deployed contracts:

```javascript
export const CONTRACT_CONFIG = {
  contractName: 'your-contract-name',
  contractAddress: 'YOUR_CONTRACT_ADDRESS',
  network: 'testnet' // or 'mainnet'
};
```

#### Adding Custom Contract Functions

Modify `src/components/ContractInteraction.js` to add your contract-specific functions:

```javascript
const myCustomFunction = async () => {
  const result = await callContract(
    CONTRACT_CONFIG.contractAddress,
    CONTRACT_CONFIG.contractName,
    'your-function-name',
    [functionArgs]
  );
};
```

### Technical Details

#### WalletConnect v2 Implementation

The dApp uses the official WalletConnect v2 Sign Client with:

- **@walletconnect/sign-client**: Core WalletConnect functionality
- **@walletconnect/utils**: Helper utilities for encoding/decoding
- **@walletconnect/qrcode-modal**: QR code display for mobile connection
- **@stacks/connect**: Stacks-specific wallet integration
- **@stacks/transactions**: Transaction building and signing
- **@stacks/network**: Network configuration for testnet/mainnet

#### BigInt Serialization

The dApp includes BigInt serialization support for handling large numbers in Clarity contracts:

```javascript
BigInt.prototype.toJSON = function() { return this.toString(); };
```

### Supported Wallets

Any wallet supporting WalletConnect v2 and Stacks blockchain, including:

- **Xverse Wallet** (Recommended)
- **Leather Wallet** (formerly Hiro Wallet)
- **Boom Wallet**
- Any other WalletConnect-compatible Stacks wallet

### Troubleshooting

**Connection Issues:**
- Ensure your wallet app supports WalletConnect v2
- Check that you're on the correct network (testnet vs mainnet)
- Try refreshing the QR code or restarting the dApp

**Transaction Failures:**
- Verify you have sufficient STX for gas fees
- Confirm the contract address and function names are correct
- Check that post-conditions are properly configured

**Build Errors:**
- Clear node_modules and reinstall: `rm -rf node_modules && npm install`
- Ensure Node.js version is 16.x or higher
- Check for dependency conflicts in package.json

### Resources

- [WalletConnect Documentation](https://docs.walletconnect.com/)
- [Stacks.js Documentation](https://docs.stacks.co/build-apps/stacks.js)
- [Xverse WalletConnect Guide](https://docs.xverse.app/wallet-connect)
- [Stacks Blockchain Documentation](https://docs.stacks.co/)

### Security Considerations

- Never commit your private keys or seed phrases
- Always verify transaction details before signing
- Use testnet for development and testing
- Audit smart contracts before mainnet deployment
- Keep dependencies updated for security patches

### License

This dApp implementation is provided as-is for integration with the Stacks smart contracts in this repository.

