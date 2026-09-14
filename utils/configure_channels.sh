#!/bin/bash
set -euo pipefail

#export BUNDLE_NAME="rhtas-operator.v1.2.1"
#export CHANNELS="stable,stable-v1.2"
#export GRAPH="v4.19/rhtas-operator/graph.yaml"

version_lt() {
  [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

get_version() {
  echo "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

get_minor() {
  echo "$1" | grep -oE 'v[0-9]+\.[0-9]+' || echo ""
}

get_prev_minor() {
  local version
  version=$(get_version "$1")
  [[ -z "$version" ]] && echo "" && return
  local major minor prev_minor
  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)
  prev_minor=$((10#$minor - 1))
  if [[ $prev_minor -ge 0 ]]; then
    echo "v${major}.${prev_minor}"
  else
    echo ""
  fi
}

export PACKAGE_NAME=$(yq e '.entries[] | select(.schema=="olm.package") | .name' $GRAPH)
BUNDLE_VERSION=$(get_version "$BUNDLE_NAME")
export BUNDLE_MINOR=$(get_minor "$BUNDLE_NAME")
PREV_MINOR=$(get_prev_minor "$BUNDLE_NAME")

echo "Bundle: $BUNDLE_NAME (minor: $BUNDLE_MINOR, prev: ${PREV_MINOR:-none})"

IFS=',' read -ra channel_list <<< "$CHANNELS"
for channel in "${channel_list[@]}"; do
  echo "Processing channel: $channel"
  export channel
  CHANNEL_EXISTS=$(yq e '[.entries[] | select(.schema=="olm.channel" and .name==env(channel))] | (length > 0)' $GRAPH)

  if [[ "$CHANNEL_EXISTS" == "true" ]]; then
    echo "Channel $channel exists. Updating..."

    REPLACES="" REPLACES_FALLBACK=""
    for entry in $(yq e ".entries[] | select(.schema==\"olm.channel\" and .name==\"$channel\").entries[].name" $GRAPH); do
      [[ "$entry" == "$BUNDLE_NAME" ]] && continue
      ENTRY_VERSION=$(get_version "$entry")
      [[ -z "$ENTRY_VERSION" ]] && continue
      ENTRY_MINOR=$(get_minor "$entry")
      if version_lt "$ENTRY_VERSION" "$BUNDLE_VERSION"; then
        if [[ "$ENTRY_MINOR" == "$BUNDLE_MINOR" ]]; then
          [[ -z "$REPLACES" || $(version_lt "$(get_version "$REPLACES")" "$ENTRY_VERSION" && echo 1) ]] && REPLACES="$entry"
        elif [[ "$ENTRY_MINOR" == "$PREV_MINOR" ]]; then
          # Pick the highest entry in prev minor as the cross-minor upgrade base, to prevent forking
          if [[ -z "$REPLACES_FALLBACK" ]] || version_lt "$(get_version "$REPLACES_FALLBACK")" "$ENTRY_VERSION"; then
            REPLACES_FALLBACK="$entry"
          fi
        fi
      fi
    done
    [[ -z "$REPLACES" ]] && REPLACES="$REPLACES_FALLBACK"

    SKIP_RANGE=""
    [[ -n "$PREV_MINOR" ]] && SKIP_RANGE=">=${PREV_MINOR#v}.0 <${BUNDLE_VERSION}"

    # Add or update bundle with replaces/skipRange
    export REPLACES SKIP_RANGE
    if [[ -n "$REPLACES" && -n "$SKIP_RANGE" ]]; then
      NEW_ENTRY="{\"name\": env(BUNDLE_NAME), \"replaces\": env(REPLACES), \"skipRange\": strenv(SKIP_RANGE)}"
    elif [[ -n "$REPLACES" ]]; then
      NEW_ENTRY="{\"name\": env(BUNDLE_NAME), \"replaces\": env(REPLACES)}"
    else
      NEW_ENTRY="{\"name\": env(BUNDLE_NAME)}"
    fi

    ENTRY_EXISTS=$(yq e "(.entries[] | select(.schema == \"olm.channel\" and .name == env(channel)).entries[] | select(.name == env(BUNDLE_NAME))) | length > 0" $GRAPH)
    if [[ "$ENTRY_EXISTS" == "true" ]]; then
      yq -i -P eval "(.entries[] | select(.schema == \"olm.channel\" and .name == env(channel)).entries[] | select(.name == env(BUNDLE_NAME))) = ${NEW_ENTRY}" $GRAPH
    else
      yq -i -P eval "(.entries[] | select(.schema == \"olm.channel\" and .name == env(channel)).entries) += [${NEW_ENTRY}]" $GRAPH
    fi

    # Keep the replaces chain linear across minor boundaries
    yq -i -P eval '
      (.entries[] | select(.schema == "olm.channel" and .name == env(channel)).entries[] |
       select(.name != env(BUNDLE_NAME) and .replaces and
              (.name | match("v[0-9]+\.[0-9]+").string != env(BUNDLE_MINOR)) and
              (.replaces | match("v[0-9]+\.[0-9]+").string == env(BUNDLE_MINOR)))
      ).replaces = env(BUNDLE_NAME)
    ' $GRAPH
  else
    yq -i -P eval '
      (.entries) |= (.[0:1] + [{
        "entries": [{"name": env(BUNDLE_NAME)}],
        "name": env(channel),
        "package": env(PACKAGE_NAME),
        "schema": "olm.channel"
      }] + .[1:])
    ' $GRAPH
  fi
  echo "Processed channel: $channel"
done
