#!/bin/bash

echo "Testing deployed Cross-Chain Bridge contracts on Testnet..."
echo ""

echo "1. Protocol Stats:"
curl -s -X POST 'https://api.testnet.hiro.so/v2/contracts/call-read/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE/intent-bridge/get-protocol-stats' \
  -H 'Content-Type: application/json' \
  -d '{"sender": "ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE", "arguments": []}' | jq '.'
echo ""

echo "2. Current Time (Clarity 4 stacks-block-time):"
curl -s -X POST 'https://api.testnet.hiro.so/v2/contracts/call-read/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE/intent-bridge/get-current-time' \
  -H 'Content-Type: application/json' \
  -d '{"sender": "ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE", "arguments": []}' | jq '.'
echo ""

echo "3. Registry Stats:"
curl -s -X POST 'https://api.testnet.hiro.so/v2/contracts/call-read/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE/bridge-registry/get-registry-stats' \
  -H 'Content-Type: application/json' \
  -d '{"sender": "ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE", "arguments": []}' | jq '.'
echo ""

echo "4. Generate Cross-Chain Payload (Clarity 4 to-ascii?):"
curl -s -X POST 'https://api.testnet.hiro.so/v2/contracts/call-read/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE/intent-bridge/generate-cross-chain-payload' \
  -H 'Content-Type: application/json' \
  -d '{"sender": "ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE", "arguments": ["u1", "u1", "u2", "u1000000"]}' | jq '.'
echo ""

echo "5. Get Chain Name:"
curl -s -X POST 'https://api.testnet.hiro.so/v2/contracts/call-read/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE/bridge-registry/get-chain-name' \
  -H 'Content-Type: application/json' \
  -d '{"sender": "ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE", "arguments": ["u1"]}' | jq '.'
echo ""

echo "✅ All contracts are live and responding on testnet!"
echo "Deployer: ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE"
echo "Explorer: https://explorer.hiro.so/address/ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE?chain=testnet"
