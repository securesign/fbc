#!/usr/bin/env bash
#
# Onboard a new OCP version's FBC components into the securesign/pipelines (CaC) repo.
#
# For each operator (rhtas, pco, mvo) this copies the latest ocp/<op>/vX.Y kustomize
# component to the new version (rewriting the version tokens) and wires the new
# component into that operator's overlay kustomization.
#
# Usage: utils/new_cac_version.sh <pipelines-repo-dir> <new-version> [source-version]
#   <pipelines-repo-dir>  path to a securesign/pipelines checkout
#   <new-version>         version to create,   e.g. v4.23
#   [source-version]      version to copy from (default: latest per operator)

set -euo pipefail

readonly OPERATORS=(rhtas pco mvo)

die() {
    echo "error: $*" >&2
    exit 1
}

assert_valid_version() {
    local version="$1"
    [[ "$version" =~ ^v[0-9]+\.[0-9]+$ ]] \
        || die "invalid version '$version' (expected vMAJOR.MINOR, e.g. v4.23)"
}

# Highest existing vX.Y directory under the given operator dir.
latest_version_in() {
    local dir="$1"
    ( cd "$dir" && ls -d v[0-9]*.[0-9]*/ 2>/dev/null | tr -d '/' | sort -V | tail -n1 )
}

# Rewrite version tokens on stdin -> stdout. A version appears three ways and all
# must change: dash (v4-22, resource names), dotted (v4.22, git context path) and
# bare (4.22, comments). Dots are escaped so sed matches them literally.
rewrite_version_tokens() {
    local source_version="$1" new_version="$2"
    local source_dash="${source_version//./-}"    new_dash="${new_version//./-}"
    local source_bare="${source_version#v}"       new_bare="${new_version#v}"
    local source_dotted_re="${source_version//./\\.}"
    local source_bare_re="${source_bare//./\\.}"

    sed -e "s/${source_dash}/${new_dash}/g" \
        -e "s/${source_dotted_re}/${new_version}/g" \
        -e "s/${source_bare_re}/${new_bare}/g"
}

# Add the new component to the operator's overlay kustomization (idempotent).
wire_into_overlay() {
    local operator="$1" overlay_base="$2" new_version="$3"
    local kustomization="$overlay_base/$operator-fbc/kustomization.yaml"
    local component_ref="../../base/ocp/$operator/$new_version"

    if yq e '.components[]' "$kustomization" | grep -qx "$component_ref"; then
        echo "    already wired into $operator-fbc"
        return
    fi
    yq e -i ".components += [\"$component_ref\"]" "$kustomization"
    echo "    wired into $operator-fbc"
}

# Copy one operator's component dir to the new version and wire it into the overlay.
onboard_operator() {
    local operator="$1" ocp_base="$2" overlay_base="$3" new_version="$4" source_override="$5"
    local operator_dir="$ocp_base/$operator"

    if [[ ! -d "$operator_dir" ]]; then
        echo "  skip $operator (no $operator_dir)"
        return
    fi

    local source_version
    source_version="${source_override:-$(latest_version_in "$operator_dir")}"
    [[ -n "$source_version" && -d "$operator_dir/$source_version" ]] \
        || die "no source version for $operator"

    local dst_dir="$operator_dir/$new_version"
    [[ ! -d "$dst_dir" ]] || die "$operator/$new_version already exists"
    echo "  $operator: $source_version -> $new_version"

    mkdir -p "$dst_dir"
    # kustomization.yaml is version-agnostic; patch.yaml needs its tokens rewritten.
    cp "$operator_dir/$source_version/kustomization.yaml" "$dst_dir/kustomization.yaml"
    rewrite_version_tokens "$source_version" "$new_version" \
        < "$operator_dir/$source_version/patch.yaml" > "$dst_dir/patch.yaml"

    wire_into_overlay "$operator" "$overlay_base" "$new_version"
}

main() {
    local pipelines_dir="${1:-}" new_version="${2:-}" source_override="${3:-}"
    [[ -n "$pipelines_dir" && -n "$new_version" ]] \
        || die "usage: $0 <pipelines-repo-dir> <new-version> [source-version]"
    assert_valid_version "$new_version"

    local ocp_base="$pipelines_dir/konflux-configs/base/project/base/ocp"
    local overlay_base="$pipelines_dir/konflux-configs/base/project/overlay"
    [[ -d "$ocp_base" && -d "$overlay_base" ]] \
        || die "not a pipelines CaC checkout: $pipelines_dir"

    local operator
    for operator in "${OPERATORS[@]}"; do
        onboard_operator "$operator" "$ocp_base" "$overlay_base" "$new_version" "$source_override"
    done

    echo "Done. Review the generated CaC files for $new_version."
}

main "$@"
