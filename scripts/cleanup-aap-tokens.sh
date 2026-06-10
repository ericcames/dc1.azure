#!/usr/bin/env bash
# ============================================================================
# cleanup-aap-tokens.sh — delete stale AAP gateway OAuth2 tokens
# ============================================================================
# Deletes every gateway token EXCEPT the keep-list (in-use tokens). Run it
# yourself; it reads creds from docs/dev-environment.sh. Self-verifies the
# remaining count at the end.
#
#   bash scripts/cleanup-aap-tokens.sh
#
# Keep-list (edit if needed):
#   79  = aap-selfservice-portal service token (admin)
#   287 = jr-dev portal token
#   292 = MCP Server - Claude Code token (admin)
#   296 = jr-dev portal token
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${HERE}/docs/dev-environment.sh"

G="${AAP_HOSTNAME}/api/gateway/v1"
KEEP_RE='^(79|287|292|296)$'
U="${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}"

echo "Listing tokens..."
ids=$(curl -sk -u "$U" "${G}/tokens/?page_size=200" \
  | python3 -c "import sys,json;[print(t['id']) for t in json.load(sys.stdin)['results']]")

deleted=0; kept=0; failed=0
for id in $ids; do
  if [[ "$id" =~ $KEEP_RE ]]; then
    echo "keep  $id"
    kept=$((kept + 1))
    continue
  fi
  code=$(curl -sk -u "$U" -o /dev/null -w "%{http_code}" -X DELETE "${G}/tokens/${id}/")
  echo "del   $id -> ${code}"
  if [[ "$code" == "204" ]]; then deleted=$((deleted + 1)); else failed=$((failed + 1)); fi
done

echo "----------------------------------------"
echo "deleted=${deleted} kept=${kept} failed=${failed}"
remaining=$(curl -sk -u "$U" "${G}/tokens/?page_size=1" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['count'])")
echo "remaining token count: ${remaining}"
