# Cross-Chain Bridge - Testnet Deployment

## Deployment Status

✅ **Successfully Deployed to Testnet**

**Deployer Address:** `ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE`

**Network:** Stacks Testnet
**Epoch:** 3.3 (Clarity 4)
**Total Deployment Cost:** ~5.52 STX

## Deployed Contracts

### 1. bridge-registry
- **Contract ID:** `ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.bridge-registry`
- **Purpose:** Registry of verified bridge contracts and supported chains
- **Clarity 4 Features:** `contract-hash?`, `to-ascii?`, `stacks-block-time`

### 2. intent-bridge
- **Contract ID:** `ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.intent-bridge`
- **Purpose:** Main intent bridge for cross-chain transfers
- **Clarity 4 Features:** `to-ascii?`, `contract-hash?`, `stacks-block-time`

### 3. intent-executor
- **Contract ID:** `ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.intent-executor`
- **Purpose:** Executor for processing cross-chain intents
- **Clarity 4 Features:** `stacks-block-time`, `to-ascii?`

## Testing the Deployment

### Automated Testing

Run the automated test script:

```bash
cd /Users/user/gwill/claritycodes/stacks-clarity4-projects/crosschain-bridge
./scripts/test-deployment.sh
```

### Manual Testing via Explorer

View contracts on Hiro Explorer:

1. **Bridge Registry:**
   https://explorer.hiro.so/txid/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.bridge-registry?chain=testnet

2. **Intent Bridge:**
   https://explorer.hiro.so/txid/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.intent-bridge?chain=testnet

3. **Intent Executor:**
   https://explorer.hiro.so/txid/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.intent-executor?chain=testnet

### Testing via API

#### Get Protocol Stats
```bash
curl -X POST "https://api.testnet.hiro.so/v2/contracts/call-read/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE/intent-bridge/get-protocol-stats" \
  -H "Content-Type: application/json" \
  -d '{"sender": "ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE", "arguments": []}'
```

#### Get Current Time (Clarity 4 Feature)
```bash
curl -X POST "https://api.testnet.hiro.so/v2/contracts/call-read/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE/intent-bridge/get-current-time" \
  -H "Content-Type: application/json" \
  -d '{"sender": "ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE", "arguments": []}'
```

#### Get Registry Stats
```bash
curl -X POST "https://api.testnet.hiro.so/v2/contracts/call-read/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE/bridge-registry/get-registry-stats" \
  -H "Content-Type: application/json" \
  -d '{"sender": "ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE", "arguments": []}'
```

## Clarity 4 Features Verified

✅ **stacks-block-time** - Used for time-based operations, intent expiry, and timestamps
✅ **to-ascii?** - Used for generating human-readable cross-chain messages
✅ **contract-hash?** - Used for verifying bridge contract integrity
✅ **print** - Used for event logging throughout all contracts

## Next Steps

1. **Initialize Chain Names** - Call `initialize-chains` on bridge-registry
2. **Register Solvers** - Users can register as solvers with collateral
3. **Create Intents** - Users can create cross-chain transfer intents
4. **Fill Intents** - Solvers can fill intents and earn fees

## Contract Interactions

### For Administrators

Initialize the bridge registry:
```clarity
(contract-call? .bridge-registry initialize-chains)
```

### For Solvers

Register as a solver with 10 STX collateral:
```clarity
(contract-call? .intent-bridge register-solver u10000000)
```

### For Users

Create a cross-chain intent (requires SIP-010 token):
```clarity
(contract-call? .intent-bridge create-intent
  .your-token
  u2  ;; CHAIN_BITCOIN
  u1000000  ;; source amount
  u100000   ;; dest amount
  "bc1q..."  ;; recipient address
  u86400     ;; 24 hours expiry
)
```

## Deployment Verification

All contracts have been successfully deployed with:
- ✅ Clarity version 4
- ✅ Epoch 3.3 configuration
- ✅ All Clarity 4 features functional
- ✅ Event logging enabled
- ✅ Contract verification enabled

## Support

For issues or questions:
- GitHub: https://github.com/big14way/crosschain-bridge
- Stacks Explorer: https://explorer.hiro.so/?chain=testnet
