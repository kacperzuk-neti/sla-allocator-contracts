#!/bin/bash

set -euo pipefail

ADMIN=$(cast wallet address "$PRIVATE_KEY")
nonce=$(cast nonce --rpc-url "$RPC_URL" "$ADMIN")

function _deploy() {
  forge create --nonce "$nonce" --broadcast --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" "$@" | grep 'Deployed to' | awk '{ print $NF; }'
}

function deployOracle() {
  local impl calldata
  impl=$(_deploy SLIOracle)
  ((nonce += 1))
  calldata=$(cast calldata 'initialize(address,address)' "$ADMIN" "$ADMIN")
  _deploy ERC1967Proxy --constructor-args "$impl" "$calldata"
}

function deploySLAAllocator() {
  local impl calldata
  impl=$(_deploy SLAAllocator)
  ((nonce += 1))
  calldata=$(cast calldata 'initialize(address,address)' "$ADMIN" "$ADMIN")
  _deploy ERC1967Proxy --constructor-args "$impl" "$calldata"
}

function deployBeneficiaryFactory() {
  local impl calldata beneficiaryImpl
  if [ -z "$1" ]; then
    echo "deployBeneficiaryFactory needs slaAllocator address" >&2
    exit 1
  fi

  if [ -z "$2" ]; then
    echo "deployBeneficiaryFactory needs burn address" >&2
    exit 1
  fi

  beneficiaryImpl=$(_deploy Beneficiary)
  ((nonce += 1))
  impl=$(_deploy BeneficiaryFactory)
  ((nonce += 1))
  calldata=$(cast calldata 'initialize(address,address,address,address)' "$ADMIN" "$beneficiaryImpl" "$1" "$2")
  _deploy ERC1967Proxy --constructor-args "$impl" "$calldata"
}

function deployClient() {
  local impl calldata
  if [ -z "$1" ]; then
    echo "deployClient needs slaAllocator address" >&2
    exit 1
  fi
  
  if [ -z "$2" ]; then
    echo "deployClient needs beneficiaryFactory address" >&2
    exit 1
  fi
  impl=$(_deploy Client)
  ((nonce += 1))
  calldata=$(cast calldata 'initialize(address,address,address)' "$ADMIN" "$1" "$2")
  _deploy ERC1967Proxy --constructor-args "$impl" "$calldata"
}

function deploySLARegistry() {
  local impl calldata
  if [ -z "$1" ]; then
    echo "deploySLARegistry needs sliOracle address" >&2
    exit 1
  fi

  impl=$(_deploy SLARegistry)
  ((nonce += 1))
  calldata=$(cast calldata 'initialize(address,address)' "$ADMIN" "$1")
  _deploy ERC1967Proxy --constructor-args "$impl" "$calldata"
}

echo -n "Deploying to chain: "
cast chain-id --rpc-url "$RPC_URL"
echo "Deployer: $ADMIN"

slaAllocator=$(deploySLAAllocator)
((nonce += 2))

client=$(deployClient "$slaAllocator")
((nonce += 2))

beneficiaryFactory=$(deployBeneficiaryFactory "$slaAllocator" "$BURN_ADDRESS")
((nonce += 3))

client=$(deployClient "$slaAllocator" "$beneficiaryFactory")
((nonce += 2))

sliOracle=$(deployOracle)
((nonce += 2))

slaRegistry=$(deploySLARegistry "$sliOracle")
((nonce += 2))

cast send --nonce "$nonce" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" "$slaAllocator" 'initialize2(address,address)' "$client" "$beneficiaryFactory" >/dev/null
((nonce += 1))

echo "BeneficiaryFactory: $beneficiaryFactory"
echo "SLAAllocator: $slaAllocator"
echo "SLARegistry: $slaRegistry"
echo "SLIOracle: $sliOracle"
echo "ClientSC: $client"
echo
echo "Deployed by: $ADMIN"
