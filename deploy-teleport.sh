#!/usr/bin/env bash
set -e

forge script script/DeployTeleportExistingDss.s.sol:DeployTeleportExistingDss --use solc:0.8.15 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast -vvvv
