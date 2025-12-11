#!/bin/bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: env RPC_URL= PRIVATE_KEY= $0 deployment-file wallet-address" >&2
  exit 1
fi

deployment_file="$1"
BENEFICIARY_FACTORY="$(jq -r .beneficiaryFactory <$deployment_file)"
SLA_ALLOCATOR="$(jq -r .slaAllocator <$deployment_file)"
SLA_REGISTRY="$(jq -r .slaRegistry <$deployment_file)"
SLI_ORACLE="$(jq -r .sliOracle <$deployment_file)"
CLIENT_SC="$(jq -r .clientSC <$deployment_file)"

recipient="$2"

ADMIN=$(cast wallet address "$PRIVATE_KEY")

function grantRole() {
  local role
  role=$(cast call --rpc-url "$RPC_URL" "$1" "$2()(bytes32)")
  cast send --nonce "$nonce" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" "$1" 'grantRole(bytes32,address)' "$role" "$3" >/dev/null
}

nonce=$(cast nonce --rpc-url "$RPC_URL" "$ADMIN")
grantRole "$SLA_REGISTRY" DEFAULT_ADMIN_ROLE "$recipient"
((nonce += 1))

grantRole "$SLA_REGISTRY" UPGRADER_ROLE "$recipient"
((nonce += 1))

grantRole "$SLI_ORACLE" DEFAULT_ADMIN_ROLE "$recipient"
((nonce += 1))

grantRole "$SLI_ORACLE" UPGRADER_ROLE "$recipient"
((nonce += 1))

grantRole "$SLI_ORACLE" ORACLE_ROLE "$recipient"
((nonce += 1))

grantRole "$SLA_ALLOCATOR" DEFAULT_ADMIN_ROLE "$recipient"
((nonce += 1))

grantRole "$SLA_ALLOCATOR" UPGRADER_ROLE "$recipient"
((nonce += 1))

grantRole "$SLA_ALLOCATOR" MANAGER_ROLE "$recipient"
((nonce += 1))

grantRole "$SLA_ALLOCATOR" ATTESTATOR_ROLE "$recipient"
((nonce += 1))

grantRole "$BENEFICIARY_FACTORY" DEFAULT_ADMIN_ROLE "$recipient"
((nonce += 1))

grantRole "$BENEFICIARY_FACTORY" UPGRADER_ROLE "$recipient"
((nonce += 1))

grantRole "$CLIENT_SC" DEFAULT_ADMIN_ROLE "$recipient"
((nonce += 1))

grantRole "$CLIENT_SC" ALLOCATOR_ROLE "$recipient"
((nonce += 1))
