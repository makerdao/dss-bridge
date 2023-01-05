#!/usr/bin/env bash
set -e

export DEPLOY_HOST="$1"
export DEPLOY_GUEST="$2"
export DEPLOY_ROUTER="$3"

forge script script/DeployExistingTokenBridge.s.sol:DeployExistingTokenBridge --use solc:0.8.15 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast -vvvv
