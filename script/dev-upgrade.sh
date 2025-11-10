#!/bin/bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: env RPC_URL= PRIVATE_KEY= $0 contract-name proxy-address calldata" >&2
  exit 1
fi

ADMIN=$(cast wallet address "$PRIVATE_KEY")
nonce=$(cast nonce --rpc-url "$RPC_URL" "$ADMIN")

function _deploy() {
  forge create --nonce "$nonce" --broadcast --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" "$@" | grep 'Deployed to' | awk '{ print $NF; }'
}

impl=$(_deploy "$1")
((nonce += 1))

cast send --nonce="$nonce" --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" "$2" 'upgradeToAndCall(address,bytes)' "$impl" "$3"
