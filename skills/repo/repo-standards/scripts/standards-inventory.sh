#!/usr/bin/env bash
# Re-export: canonical implementation in skills/repo/_contract/scripts/
set -euo pipefail
CONTRACT_SCRIPTS="$(cd "$(dirname "$0")/../../_contract/scripts" && pwd)"
exec bash "$CONTRACT_SCRIPTS/standards-inventory.sh" "$@"
