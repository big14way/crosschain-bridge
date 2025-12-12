import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals, assertExists } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

const CHAIN_STACKS = 1;
const CHAIN_BITCOIN = 2;
const CHAIN_ETHEREUM = 3;

Clarinet.test({
    name: "Can register as a solver with collateral",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const solver = accounts.get('wallet_1')!;
        const collateral = 10000000; // 10 STX
        
        let block = chain.mineBlock([
            Tx.contractCall('intent-bridge', 'register-solver', [
                types.uint(collateral)
            ], solver.address)
        ]);
        
        block.receipts[0].result.expectOk().expectBool(true);
        
        // Verify solver was registered
        let solverInfo = chain.callReadOnlyFn(
            'intent-bridge',
            'get-solver',
            [types.principal(solver.address)],
            solver.address
        );
        
        const data = solverInfo.result.expectSome().expectTuple();
        assertEquals(data['collateral'], types.uint(collateral));
    }
});

Clarinet.test({
    name: "Can add more collateral",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const solver = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('intent-bridge', 'register-solver', [
                types.uint(5000000)
            ], solver.address),
            Tx.contractCall('intent-bridge', 'add-collateral', [
                types.uint(5000000)
            ], solver.address)
        ]);
        
        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectOk();
        
        let solverInfo = chain.callReadOnlyFn(
            'intent-bridge',
            'get-solver',
            [types.principal(solver.address)],
            solver.address
        );
        
        const data = solverInfo.result.expectSome().expectTuple();
        assertEquals(data['collateral'], types.uint(10000000));
    }
});

Clarinet.test({
    name: "Get current time returns stacks-block-time",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let currentTime = chain.callReadOnlyFn(
            'intent-bridge',
            'get-current-time',
            [],
            user.address
        );
        
        assertExists(currentTime.result);
    }
});

Clarinet.test({
    name: "Can generate cross-chain payload message",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let payload = chain.callReadOnlyFn(
            'intent-bridge',
            'generate-cross-chain-payload',
            [
                types.uint(1),
                types.uint(CHAIN_STACKS),
                types.uint(CHAIN_BITCOIN),
                types.uint(1000000)
            ],
            user.address
        );
        
        // Should return formatted string
        assertExists(payload.result);
    }
});

Clarinet.test({
    name: "Protocol stats are tracked",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let stats = chain.callReadOnlyFn(
            'intent-bridge',
            'get-protocol-stats',
            [],
            user.address
        );
        
        const data = stats.result.expectTuple();
        assertEquals(data['total-intents'], types.uint(0));
        assertEquals(data['total-volume'], types.uint(0));
        assertEquals(data['fee-bps'], types.uint(30));
    }
});

Clarinet.test({
    name: "Only admin can update protocol fee",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('intent-bridge', 'set-protocol-fee', [
                types.uint(50)
            ], user.address),
            Tx.contractCall('intent-bridge', 'set-protocol-fee', [
                types.uint(50)
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(9001); // ERR_NOT_AUTHORIZED
        block.receipts[1].result.expectOk();
    }
});

Clarinet.test({
    name: "Protocol fee cannot exceed 1%",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('intent-bridge', 'set-protocol-fee', [
                types.uint(150) // 1.5% - too high
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(9005); // ERR_INVALID_AMOUNT
    }
});

// Bridge Registry Tests

Clarinet.test({
    name: "Can initialize chain names",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('bridge-registry', 'initialize-chains', [], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk();
        
        let chainName = chain.callReadOnlyFn(
            'bridge-registry',
            'get-chain-name',
            [types.uint(CHAIN_STACKS)],
            deployer.address
        );
        
        chainName.result.expectAscii("Stacks");
    }
});

Clarinet.test({
    name: "Can describe route",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        // Initialize first
        chain.mineBlock([
            Tx.contractCall('bridge-registry', 'initialize-chains', [], deployer.address)
        ]);
        
        let route = chain.callReadOnlyFn(
            'bridge-registry',
            'describe-route',
            [types.uint(CHAIN_STACKS), types.uint(CHAIN_BITCOIN)],
            deployer.address
        );
        
        route.result.expectAscii("Stacks -> Bitcoin");
    }
});

// Intent Executor Tests

Clarinet.test({
    name: "Can authorize executor",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const executor = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('intent-executor', 'authorize-executor', [
                types.principal(executor.address)
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk();
        
        let isAuthorized = chain.callReadOnlyFn(
            'intent-executor',
            'is-executor-authorized',
            [types.principal(executor.address)],
            deployer.address
        );
        
        isAuthorized.result.expectBool(true);
    }
});

Clarinet.test({
    name: "Can revoke executor",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const executor = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('intent-executor', 'authorize-executor', [
                types.principal(executor.address)
            ], deployer.address),
            Tx.contractCall('intent-executor', 'revoke-executor', [
                types.principal(executor.address)
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectOk();
        
        let isAuthorized = chain.callReadOnlyFn(
            'intent-executor',
            'is-executor-authorized',
            [types.principal(executor.address)],
            deployer.address
        );
        
        isAuthorized.result.expectBool(false);
    }
});

Clarinet.test({
    name: "Only admin can authorize executors",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        const executor = accounts.get('wallet_2')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('intent-executor', 'authorize-executor', [
                types.principal(executor.address)
            ], user.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(11001); // ERR_NOT_AUTHORIZED
    }
});
