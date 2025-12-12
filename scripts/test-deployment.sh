#!/bin/bash

# Test script for deployed cross-chain bridge contracts
# Deployer: ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE

DEPLOYER="ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE"
TESTNET_API="https://api.testnet.hiro.so"

echo "=== Cross-Chain Bridge Testnet Deployment Test ==="
echo ""

# Test 1: Check bridge-registry deployment
echo "1. Testing bridge-registry contract..."
curl -s "${TESTNET_API}/v2/contracts/interface/${DEPLOYER}/bridge-registry" | jq '.'
echo ""

# Test 2: Check intent-bridge deployment
echo "2. Testing intent-bridge contract..."
curl -s "${TESTNET_API}/v2/contracts/interface/${DEPLOYER}/intent-bridge" | jq '.'
echo ""

# Test 3: Check intent-executor deployment
echo "3. Testing intent-executor contract..."
curl -s "${TESTNET_API}/v2/contracts/interface/${DEPLOYER}/intent-executor" | jq '.'
echo ""

# Test 4: Call get-protocol-stats from intent-bridge
echo "4. Testing get-protocol-stats read-only function..."
curl -s -X POST "${TESTNET_API}/v2/contracts/call-read/${DEPLOYER}/intent-bridge/get-protocol-stats" \
  -H "Content-Type: application/json" \
  -d '{"sender": "'${DEPLOYER}'", "arguments": []}' | jq '.'
echo ""

# Test 5: Call get-registry-stats from bridge-registry
echo "5. Testing get-registry-stats read-only function..."
curl -s -X POST "${TESTNET_API}/v2/contracts/call-read/${DEPLOYER}/bridge-registry/get-registry-stats" \
  -H "Content-Type: application/json" \
  -d '{"sender": "'${DEPLOYER}'", "arguments": []}' | jq '.'
echo ""

# Test 6: Check stacks-block-time usage
echo "6. Testing get-current-time (Clarity 4 stacks-block-time)..."
curl -s -X POST "${TESTNET_API}/v2/contracts/call-read/${DEPLOYER}/intent-bridge/get-current-time" \
  -H "Content-Type: application/json" \
  -d '{"sender": "'${DEPLOYER}'", "arguments": []}' | jq '.'
echo ""

echo "=== Deployment Test Complete ==="
echo ""
echo "Contract URLs:"
echo "- Bridge Registry: https://explorer.hiro.so/txid/${DEPLOYER}.bridge-registry?chain=testnet"
echo "- Intent Bridge: https://explorer.hiro.so/txid/${DEPLOYER}.intent-bridge?chain=testnet"
echo "- Intent Executor: https://explorer.hiro.so/txid/${DEPLOYER}.intent-executor?chain=testnet"
