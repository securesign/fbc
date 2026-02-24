#!/usr/bin/env bash
set -euo pipefail

# Filter graph.yaml to keep only bundles that exist in registry.redhat.io
# Usage: filter_for_production.sh <graph_yaml>
#
# Environment:
#   SKOPEO_CMD - skopeo command (default: skopeo)
#   AUTH_FILE  - auth file flag for skopeo (e.g., "--authfile /path/to/config.json")
#   SKOPEO_CACHE_FILE - cache file for skopeo results (optional)

GRAPH="${1:-}"

if [[ -z "$GRAPH" ]]; then
  echo "Usage: filter_for_production.sh <graph_yaml>"
  exit 1
elif [[ ! -f "$GRAPH" ]]; then
  echo "Error: Graph file not found: $GRAPH"
  exit 1
fi

SKOPEO_CMD=${SKOPEO_CMD:-skopeo}
AUTH_FILE=${AUTH_FILE:-}
CACHE_FILE="${SKOPEO_CACHE_FILE:-${TMPDIR:-/tmp}/skopeo-cache.$$}"

check_image_exists() {
  local image="$1"
  local cache_key="${image##*@}"

  # Check cache first
  if grep -q "^${cache_key}=exists$" "$CACHE_FILE" 2>/dev/null; then
    return 0
  elif grep -q "^${cache_key}=notfound$" "$CACHE_FILE" 2>/dev/null; then
    return 1
  fi

  # Not cached, check registry
  if ${SKOPEO_CMD} inspect --no-tags ${AUTH_FILE} "docker://${image}" &>/dev/null; then
    echo "${cache_key}=exists" >> "$CACHE_FILE"
    return 0
  else
    echo "${cache_key}=notfound" >> "$CACHE_FILE"
    return 1
  fi
}

echo "Filtering graph for production: $GRAPH"
echo "Using cache: $CACHE_FILE"

echo "Checking bundle image availability..."
BUNDLES=$(yq e '.entries[] | select(.schema == "olm.bundle") | .name + "|" + .image' "$GRAPH")

while IFS='|' read -r BUNDLE IMAGE; do
  [[ -z "$BUNDLE" || -z "$IMAGE" ]] && continue

  echo -n "Checking $BUNDLE... "

  if check_image_exists "$IMAGE"; then
    echo "EXISTS"
  else
    echo "NOT FOUND - removing"
    export BUNDLE

    # Remove bundle entry
    yq -i 'del(.entries[] | select(.schema == "olm.bundle" and .name == env(BUNDLE)))' "$GRAPH"
    # Remove from channel entries
    yq -i '(.entries[] | select(.schema == "olm.channel").entries) |= map(select(.name != env(BUNDLE)))' "$GRAPH"
    # Remove from skips arrays
    yq -i '(.entries[] | select(.schema == "olm.channel").entries[].skips) |= map(select(. != env(BUNDLE)))' "$GRAPH"
    # Remove from replaces references
    yq -i 'del(.entries[] | select(.schema == "olm.channel").entries[] | select(.replaces == env(BUNDLE)).replaces)' "$GRAPH"
  fi
done <<< "$BUNDLES"

echo "Removing empty channels..."
yq -i 'del(.entries[] | select(.schema == "olm.channel" and (.entries | length) == 0))' "$GRAPH"

echo ""
echo "Filtering complete: $GRAPH"
