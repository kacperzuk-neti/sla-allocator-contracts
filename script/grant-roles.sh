#!/bin/bash

set -euo pipefail

BENEFICIARY_FACTORY="0xB2263396076fc04098924c8e36a1bD9a664bCf51"
SLA_ALLOCATOR="0xa4C13fc621Ab04E4092d2f5b2Ed0e2e67C1cc3aE"
SLA_REGISTRY="0x4d239cD2c62475BEa41e09BACBe59a9380C28220"
SLI_ORACLE="0xc0fbfCB6F7F98f1192F4bB84A1FfF282EdB421Ae"
CLIENT_SC="0x155849df024014E891FD3f54857ed1Ad69DdE010"

recipient="$1"

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

grantRole "$BENEFICIARY_FACTORY" DEFAULT_ADMIN_ROLE "$recipient"
((nonce += 1))

grantRole "$BENEFICIARY_FACTORY" UPGRADER_ROLE "$recipient"
((nonce += 1))

grantRole "$CLIENT_SC" DEFAULT_ADMIN_ROLE "$recipient"
((nonce += 1))

grantRole "$CLIENT_SC" ALLOCATOR_ROLE "$recipient"
((nonce += 1))
