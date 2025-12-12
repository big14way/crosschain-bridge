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

## License

MIT License
