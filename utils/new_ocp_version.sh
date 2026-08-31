#!/usr/bin/env bash
#
# Generate an empty FBC skeleton for a new OCP version (e.g. v4.23 or v5.0).
#
# For each operator this creates the per-operator directory tree with a minimal
# graph.yaml / catalog.json / catalog.Dockerfile / devfile.yaml / license, copies
# the three .tekton push PipelineRuns, and adds the version to the sync-catalog
# cron matrix.
#
# `main` mirrors the *published* Red Hat catalog, so a brand-new version starts
# EMPTY (no package entries). The nightly cron populates it once the operators
# ship upstream.
#
# Usage: utils/new_ocp_version.sh <new-version> [source-version]
#   <new-version>     version to create,   e.g. v4.23 or v5.0
#   [source-version]  version to copy from (default: highest existing vX.Y dir)

set -euo pipefail

readonly OPERATORS=(rhtas-operator policy-controller-operator model-validation-operator)
readonly SYNC_WORKFLOW=".github/workflows/sync-catalog.yaml"

die() {
    echo "error: $*" >&2
    exit 1
}

# vX.Y -> vX-Y  (form used in .tekton file names and resource names).
version_to_dash() {
    local version="$1"
    echo "${version//./-}"
}

# vX.Y -> X  (major number, used to pick the openshiftN image group).
version_major() {
    local version="$1"
    version="${version#v}"
    echo "${version%%.*}"
}

assert_valid_version() {
    local version="$1"
    [[ "$version" =~ ^v[0-9]+\.[0-9]+$ ]] \
        || die "invalid version '$version' (expected vMAJOR.MINOR, e.g. v4.23)"
}

# Highest existing vX.Y directory in the repo root (default source version).
latest_existing_version() {
    ls -d v[0-9]*.[0-9]*/ 2>/dev/null | tr -d '/' | sort -V | tail -n1
}

# .tekton file-name prefix for an operator.
tekton_prefix() {
    case "$1" in
        rhtas-operator)             echo "rhtas" ;;
        policy-controller-operator) echo "pco" ;;
        model-validation-operator)  echo "mvo" ;;
        *) die "unknown operator '$1'" ;;
    esac
}

# catalog.Dockerfile FROM line. Red Hat moves the image group from openshift4 to
# openshift5 at v5.0, so the group must track the major version.
dockerfile_from_line() {
    local version="$1"
    echo "FROM registry.redhat.io/openshift$(version_major "$version")/ose-operator-registry-rhel9:${version}"
}

# Create one operator's empty FBC skeleton: <source-version> -> <new-version>.
create_operator_skeleton() {
    local operator="$1" source_version="$2" new_version="$3"
    local src="${source_version}/${operator}"
    local dst="${new_version}/${operator}"

    if [[ ! -d "$src" ]]; then
        echo "  skip $operator (not present in $source_version)"
        return
    fi
    echo "  operator: $operator"

    mkdir -p "$dst/catalog/$operator" "$dst/licenses" "$dst/$new_version"
    : > "$dst/$new_version/.empty"   # keep the otherwise-empty dir tracked by git

    # Empty graph on purpose: no package until the operator ships. A package with
    # no bundle fails `opm serve --cache-only` at build time.
    yq -n '.schema = "olm.template.basic" | .entries = []' > "$dst/graph.yaml"

    # Copy the Dockerfile, rewriting only the FROM line so the image group matches
    # the new major version.
    sed -E "s|^FROM registry.redhat.io/openshift[0-9]+/ose-operator-registry-rhel9:.*|$(dockerfile_from_line "$new_version")|" \
        "$src/catalog.Dockerfile" > "$dst/catalog.Dockerfile"

    # devfile differs only by the version string.
    sed "s/${source_version}/${new_version}/g" "$src/devfile.yaml" > "$dst/devfile.yaml"

    cp "$src/licenses/license.txt" "$dst/licenses/license.txt"

    # Render catalog.json from the empty graph (render_catalog.sh reads the target
    # file first, so create it empty).
    local catalog_file="$dst/catalog/$operator/catalog.json"
    : > "$catalog_file"
    OCP_VERSION="$new_version" FBC_DIR="$operator" CATALOG_FILE="$catalog_file" \
        ./utils/render_catalog.sh
}

# Copy an operator's .tekton push PipelineRun to the new version.
copy_tekton_pipelinerun() {
    local operator="$1" source_version="$2" new_version="$3"
    local prefix source_dash new_dash src dst
    prefix="$(tekton_prefix "$operator")"
    source_dash="$(version_to_dash "$source_version")"
    new_dash="$(version_to_dash "$new_version")"
    src=".tekton/${prefix}-fbc-${source_dash}-push.yaml"
    dst=".tekton/${prefix}-fbc-${new_dash}-push.yaml"

    if [[ ! -f "$src" ]]; then
        echo "  skip .tekton for $operator (no $src)"
        return
    fi
    sed -e "s/${source_dash}/${new_dash}/g" -e "s/${source_version}/${new_version}/g" \
        "$src" > "$dst"
    echo "  tekton: $dst"
}

# Add the new version to the nightly sync-catalog cron matrix (idempotent).
add_to_cron_matrix() {
    local new_version="$1"
    local path='.jobs.update-catalogs.strategy.matrix.ocp_version'

    if yq e "${path}[]" "$SYNC_WORKFLOW" | grep -qx "$new_version"; then
        echo "  cron matrix already lists $new_version"
        return
    fi
    yq e -i "${path} += [\"$new_version\"]" "$SYNC_WORKFLOW"
    echo "  added $new_version to $SYNC_WORKFLOW"
}

main() {
    local new_version="${1:-}" source_version="${2:-}"
    [[ -n "$new_version" ]] || die "usage: $0 <new-version> [source-version]"
    assert_valid_version "$new_version"

    # Run from the repo root (this script lives in utils/).
    cd "$(dirname "${BASH_SOURCE[0]}")/.."

    [[ ! -d "$new_version" ]] || die "version $new_version already exists"

    source_version="${source_version:-$(latest_existing_version)}"
    [[ -n "$source_version" && -d "$source_version" ]] \
        || die "source version not found: '${source_version:-<none>}'"
    assert_valid_version "$source_version"

    echo "Creating $new_version (from $source_version)"

    local operator
    for operator in "${OPERATORS[@]}"; do
        create_operator_skeleton "$operator" "$source_version" "$new_version"
    done
    for operator in "${OPERATORS[@]}"; do
        copy_tekton_pipelinerun "$operator" "$source_version" "$new_version"
    done
    add_to_cron_matrix "$new_version"

    echo "Done. Review the generated files for $new_version."
}

main "$@"
