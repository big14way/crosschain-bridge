# Cross-chain Intent Bridge Chainhooks Integration

Real-time event tracking and analytics for the Cross-chain Intent Bridge platform. Monitors bridge intents, solver activities, collateral management, and protocol fees using Stacks Chainhooks.

## Features

### Event Tracking

This integration monitors all key Cross-chain Bridge events:

1. **Intent Operations**
   - **Intent Creation** (`create-intent`) - Users creating cross-chain bridge requests
   - **Intent Fulfillment** (`fill-intent`) - Solvers executing bridge transfers
   - **Intent Cancellation** (`cancel-intent`) - Users cancelling pending intents
   - Tracks source/destination chains (Stacks, Bitcoin, Ethereum)
   - Monitors intent volumes and amounts

2. **Solver Management**
   - **Solver Registration** (`register-solver`) - New solver onboarding
   - **Collateral Addition** (`add-collateral`) - Solvers adding security deposits
   - Tracks active solver count
   - Monitors total collateral locked in system

3. **Bridge Verification**
   - **Bridge Contract Verification** (`verify-bridge`) - Admin verifying bridge contracts
   - Tracks verified bridge partners
   - Contract hash validation using Clarity 4 features

4. **Protocol Metrics**
   - Protocol fees (0.3% on intent fills)
   - Cross-chain volume tracking
   - Intent success/failure rates
   - Solver performance metrics

### Analytics Collected

The integration tracks comprehensive metrics:

- **Users**: Unique addresses creating intents
- **Solvers**: Registered solver addresses
- **Intents**: Total bridge requests created
- **Fills**: Successfully executed intents
- **Volume**: Total value bridged across chains
- **Collateral**: Total solver collateral locked
- **Fees**: Protocol fees collected (0.3% per fill)
- **Bridge Activity**: Breakdown by chain pairs

## Setup

### Prerequisites

- Node.js 18+ and npm
- Access to a Stacks Chainhook node (Hiro Platform or self-hosted)
- The Intent Bridge contract deployed on Stacks testnet/mainnet

### Installation

1. Navigate to the chainhooks directory:
```bash
cd crosschain-bridge/chainhooks
```

2. Install dependencies:
```bash
npm install
```

3. Copy and configure environment variables:
```bash
cp .env.example .env
```

4. Edit `.env` with your configuration:
```env
# Chainhook Node Configuration
CHAINHOOK_NODE_URL=http://localhost:20456

# Server Configuration
SERVER_HOST=0.0.0.0
SERVER_PORT=3001
SERVER_AUTH_TOKEN=your-secret-token-here
EXTERNAL_BASE_URL=http://localhost:3001

# Contract Configuration
BRIDGE_CONTRACT=ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.intent-bridge
REGISTRY_CONTRACT=ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.bridge-registry

# Starting block height
START_BLOCK=0

# Network
NETWORK=testnet
```

### Running the Observer

Start the Chainhook observer:

```bash
npm start
```

For development with auto-reload:

```bash
npm run dev
```

## Contract Events

### Monitored Functions

| Function | Description | Actor | Fee |
|----------|-------------|-------|-----|
| `create-intent` | Create bridge request | User | None |
| `fill-intent` | Execute bridge transfer | Solver | 0.3% protocol fee |
| `cancel-intent` | Cancel pending intent | User | None |
| `register-solver` | Register as solver | Solver | Requires collateral |
| `add-collateral` | Add security deposit | Solver | None |
| `verify-bridge` | Verify bridge contract | Admin | None |

### Print Events Tracked

The contract emits detailed print events:

```clarity
{event: "intent-created", intent-id: uint, creator: principal, source-chain: uint, dest-chain: uint, source-amount: uint}
{event: "intent-filled", intent-id: uint, solver: principal, filled-at: uint}
{event: "intent-cancelled", intent-id: uint, canceller: principal}
{event: "solver-registered", solver: principal, collateral: uint, registered-at: uint}
{event: "collateral-added", solver: principal, amount: uint, total-collateral: uint}
{event: "bridge-verified", bridge-contract: principal, name: string-ascii, verified-by: principal}
```

### Chain IDs

- `1` = Stacks
- `2` = Bitcoin
- `3` = Ethereum (or other EVM chains)

## Analytics Output

Analytics data is saved to `analytics-data.json`:

```json
{
  "users": ["ST1...", "ST2..."],
  "solvers": ["ST3...", "ST4..."],
  "uniqueUsers": 42,
  "uniqueSolvers": 8,
  "totalIntents": 156,
  "filledIntents": 142,
  "cancelledIntents": 14,
  "totalVolume": 5000000000,
  "protocolFeesCollected": 15000000,
  "totalCollateralLocked": 100000000,
  "bridgesByChain": {
    "stacks": 75,
    "bitcoin": 68,
    "ethereum": 13
  },
  "intents": [
    {
      "creator": "ST...",
      "timestamp": "2024-01-15T10:30:00.000Z",
      "txid": "0x..."
    }
  ],
  "fills": [...],
  "solverRegistrations": [...],
  "verifiedBridges": [...],
  "timestamp": "2024-01-15T12:00:00.000Z"
}
```

## Key Metrics

### Fee Structure

- **Protocol Fee**: 0.3% on each intent fill
- **No User Fees**: Intent creation and cancellation are free
- **Collateral Requirements**: Solvers must maintain 150% collateral ratio

### Volume Tracking

- **Total Volume**: Aggregate value bridged across all chains
- **Chain Distribution**: Volume breakdown by source/destination
- **Intent Success Rate**: Percentage of filled vs cancelled intents

### Solver Metrics

- **Active Solvers**: Count of registered solvers
- **Collateral Locked**: Total security deposits
- **Fill Success**: Solver performance and reputation

## Use Cases

### Bridge Analytics
- Track cross-chain volume and trends
- Monitor most popular chain pairs
- Analyze bridge success rates

### Solver Performance
- Identify top-performing solvers
- Track collateral levels
- Monitor fill times and success rates

### Protocol Revenue
- Calculate fees collected
- Project future revenue
- Analyze fee efficiency

### Risk Management
- Monitor collateral adequacy
- Track intent expiration rates
- Identify potential vulnerabilities

## Architecture

The integration uses the Hiro Chainhook Event Observer to:

1. Register predicates for bridge contract functions
2. Listen for on-chain events in real-time
3. Parse transaction data and print events
4. Aggregate analytics by chain and solver
5. Persist data with graceful shutdown

## Troubleshooting

### Observer won't start
- Verify Chainhook node URL is accessible
- Check contract addresses match deployment
- Ensure START_BLOCK is valid

### Missing intent events
- Confirm contract is deployed and active
- Verify network setting matches deployment
- Check Chainhook node sync status

### Collateral tracking issues
- Ensure all solver transactions are captured
- Verify collateral calculations
- Check for reorg handling

## Production Considerations

For production deployments:

1. **Database Integration**: Use PostgreSQL for persistent storage
2. **Solver Monitoring**: Track solver reputation and performance
3. **Alerting**: Set up alerts for low collateral, expired intents
4. **Analytics Dashboard**: Build real-time monitoring UI
5. **API Layer**: Expose metrics via REST/GraphQL API
6. **Cross-chain Verification**: Validate intent execution on destination chains

## Intent-based Bridge Model

This bridge uses an intent-based architecture:

1. **User creates intent**: Specifies source/dest chains and amounts
2. **Solver fills intent**: Executes transfer on destination chain first
3. **Proof verification**: Contract validates execution proof
4. **Asset release**: Source assets released to solver
5. **Collateral protection**: Solver collateral slashed if fraud detected

Benefits:
- Fast bridging (no consensus delays)
- Decentralized solver network
- Economic security via collateral
- Support for any destination chain

## Security Features

- **Contract Hash Verification**: Uses Clarity 4 `contract-hash?` to verify bridge contracts
- **Collateral Requirements**: 150% minimum collateral ratio for solvers
- **Time Locks**: Intents expire after defined period
- **Replay Protection**: Nonce-based intent uniqueness
- **Emergency Shutdown**: Admin can pause in emergency

## Contract Information

- **Bridge Contract**: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.intent-bridge`
- **Registry Contract**: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.bridge-registry`
- **Network**: Stacks Testnet
- **Clarity Version**: 4 (Epoch 3.3)

## Resources

- [Stacks Chainhooks Documentation](https://docs.hiro.so/chainhooks)
- [Intent Bridge Contract](../contracts/intent-bridge.clar)
- [Bridge Registry Contract](../contracts/bridge-registry.clar)
- [Hiro Platform](https://platform.hiro.so/)

## License

MIT
