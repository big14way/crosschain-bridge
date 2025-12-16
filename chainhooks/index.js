import { ChainhookEventObserver } from '@hirosystems/chainhook-client';
import { randomUUID } from 'crypto';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';

dotenv.config();

// Analytics storage (in production, use a database)
const analytics = {
  users: new Set(),
  solvers: new Set(),
  totalIntents: 0,
  filledIntents: 0,
  cancelledIntents: 0,
  totalVolume: 0,
  protocolFeesCollected: 0,
  totalCollateralLocked: 0,
  bridgesByChain: {
    stacks: 0,
    bitcoin: 0,
    ethereum: 0
  },
  intents: [],
  fills: [],
  solverRegistrations: [],
  verifiedBridges: []
};

// Save analytics to JSON file
function saveAnalytics() {
  const data = {
    ...analytics,
    users: Array.from(analytics.users),
    solvers: Array.from(analytics.solvers),
    timestamp: new Date().toISOString(),
    uniqueUsers: analytics.users.size,
    uniqueSolvers: analytics.solvers.size
  };

  fs.writeFileSync(
    path.join(process.cwd(), 'analytics-data.json'),
    JSON.stringify(data, null, 2)
  );

  console.log(`📊 Analytics saved - Users: ${data.uniqueUsers}, Intents: ${data.totalIntents}, Fills: ${data.filledIntents}, Solvers: ${data.uniqueSolvers}`);
}

// Create predicates for bridge events
function createBridgePredicates() {
  const contractId = process.env.BRIDGE_CONTRACT;
  const startBlock = parseInt(process.env.START_BLOCK) || 0;
  const network = process.env.NETWORK || 'testnet';

  return [
    {
      uuid: randomUUID(),
      name: 'intent-created-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'create-intent'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/intent-created`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'intent-filled-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'fill-intent'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/intent-filled`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'intent-cancelled-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'cancel-intent'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/intent-cancelled`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'solver-registration-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'register-solver'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/solver-registered`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'collateral-added-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'add-collateral'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/collateral-added`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'bridge-verification-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'verify-bridge'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/bridge-verified`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'bridge-print-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'print_event',
            contract_identifier: contractId,
            contains: 'event'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/print-event`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    }
  ];
}

// Parse print event data
function parsePrintEvent(eventValue) {
  try {
    if (typeof eventValue === 'string') {
      return JSON.parse(eventValue);
    }
    return eventValue;
  } catch (error) {
    console.error('Error parsing print event:', error);
    return null;
  }
}

// Get chain name from chain ID
function getChainName(chainId) {
  const chains = { 1: 'stacks', 2: 'bitcoin', 3: 'ethereum' };
  return chains[chainId] || 'unknown';
}

// Event handler
async function handleChainhookEvent(uuid, payload) {
  console.log(`\n🔔 Event received: ${uuid}`);

  try {
    // Process transactions in the payload
    if (payload.apply && payload.apply.length > 0) {
      for (const block of payload.apply) {
        console.log(`📦 Block ${block.block_identifier.index}`);

        for (const tx of block.transactions) {
          const sender = tx.metadata.sender;
          analytics.users.add(sender);

          // Process contract calls
          if (tx.metadata.kind?.data?.contract_call) {
            const contractCall = tx.metadata.kind.data.contract_call;
            const method = contractCall.function_name;

            console.log(`  → ${sender} called ${method}`);

            switch (method) {
              case 'create-intent':
                analytics.totalIntents++;
                analytics.intents.push({
                  creator: sender,
                  timestamp: new Date().toISOString(),
                  txid: tx.transaction_identifier.hash
                });
                console.log(`  🌉 Intent created`);
                break;

              case 'fill-intent':
                analytics.filledIntents++;
                analytics.solvers.add(sender);
                analytics.fills.push({
                  solver: sender,
                  timestamp: new Date().toISOString(),
                  txid: tx.transaction_identifier.hash
                });
                console.log(`  ✅ Intent filled by solver`);
                break;

              case 'cancel-intent':
                analytics.cancelledIntents++;
                console.log(`  ❌ Intent cancelled`);
                break;

              case 'register-solver':
                analytics.solvers.add(sender);
                analytics.solverRegistrations.push({
                  solver: sender,
                  timestamp: new Date().toISOString(),
                  txid: tx.transaction_identifier.hash
                });
                console.log(`  🤖 Solver registered`);
                break;

              case 'add-collateral':
                console.log(`  💰 Collateral added by solver`);
                break;

              case 'verify-bridge':
                analytics.verifiedBridges.push({
                  verifier: sender,
                  timestamp: new Date().toISOString(),
                  txid: tx.transaction_identifier.hash
                });
                console.log(`  ✓ Bridge contract verified`);
                break;
            }
          }

          // Process print events for detailed tracking
          if (tx.metadata.receipt?.events) {
            for (const event of tx.metadata.receipt.events) {
              if (event.type === 'SmartContractEvent') {
                const eventData = parsePrintEvent(event.data.value);

                if (eventData) {
                  // Track specific events from print statements
                  if (eventData.event === 'intent-created') {
                    const sourceChain = getChainName(eventData['source-chain']);
                    const destChain = getChainName(eventData['dest-chain']);
                    const amount = eventData['source-amount'] || 0;

                    analytics.totalVolume += amount;
                    analytics.bridgesByChain[sourceChain] = (analytics.bridgesByChain[sourceChain] || 0) + 1;

                    console.log(`  ℹ️  Intent #${eventData['intent-id']}: ${sourceChain} → ${destChain} (${amount / 1000000} tokens)`);
                  } else if (eventData.event === 'intent-filled') {
                    const feePaid = (eventData['source-amount'] || 0) * 0.003; // 0.3% protocol fee
                    analytics.protocolFeesCollected += feePaid;

                    console.log(`  ℹ️  Intent #${eventData['intent-id']} filled (Fee: ${feePaid / 1000000} tokens)`);
                  } else if (eventData.event === 'solver-registered') {
                    const collateral = eventData.collateral || 0;
                    analytics.totalCollateralLocked += collateral;

                    console.log(`  ℹ️  Solver registered with ${collateral / 1000000} STX collateral`);
                  } else if (eventData.event === 'collateral-added') {
                    const amount = eventData.amount || 0;
                    analytics.totalCollateralLocked += amount;

                    console.log(`  ℹ️  Collateral added: ${amount / 1000000} STX`);
                  } else if (eventData.event === 'bridge-verified') {
                    console.log(`  ℹ️  Bridge verified: ${eventData['bridge-contract']}`);
                  }
                }
              }
            }
          }
        }
      }

      // Save analytics after processing
      saveAnalytics();
    }

  } catch (error) {
    console.error('Error processing event:', error);
  }
}

// Start the observer
async function start() {
  console.log('🚀 Starting Cross-chain Intent Bridge Chainhook Observer\n');

  const serverOptions = {
    hostname: process.env.SERVER_HOST,
    port: parseInt(process.env.SERVER_PORT),
    auth_token: process.env.SERVER_AUTH_TOKEN,
    external_base_url: process.env.EXTERNAL_BASE_URL
  };

  const chainhookOptions = {
    base_url: process.env.CHAINHOOK_NODE_URL
  };

  const predicates = createBridgePredicates();

  console.log(`📡 Server: ${serverOptions.external_base_url}`);
  console.log(`🔗 Chainhook Node: ${chainhookOptions.base_url}`);
  console.log(`📋 Monitoring ${predicates.length} event types\n`);
  console.log(`📝 Contract: ${process.env.BRIDGE_CONTRACT}\n`);

  const observer = new ChainhookEventObserver(serverOptions, chainhookOptions);

  try {
    await observer.start(predicates, handleChainhookEvent);
    console.log('✅ Observer started successfully!\n');
    console.log('Tracking:');
    console.log('  - Intent creation (cross-chain bridge requests)');
    console.log('  - Intent fulfillment (solver executions)');
    console.log('  - Solver registrations and collateral');
    console.log('  - Bridge contract verifications');
    console.log('  - Protocol fees (0.3% on fills)\n');
    console.log('Waiting for events...\n');
  } catch (error) {
    console.error('❌ Failed to start observer:', error.message);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n\n👋 Shutting down gracefully...');
  saveAnalytics();
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('\n\n👋 Shutting down gracefully...');
  saveAnalytics();
  process.exit(0);
});

// Start the observer
start().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
