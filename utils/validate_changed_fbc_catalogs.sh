#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "${repo_root}"

usage() {
    echo "Usage: $0 --all | <base-revision> [head-revision]" >&2
}

all_contexts() {
    find . -mindepth 3 -maxdepth 3 -type f -name graph.yaml -path './v*/*/graph.yaml' \
        | sed -e 's#^\./##' -e 's#/graph.yaml$##' \
        | sort -u
}

if [[ $# -eq 1 && "$1" == "--all" ]]; then
    mapfile -t contexts < <(all_contexts)
elif [[ $# -ge 1 && $# -le 2 ]]; then
    base_revision="$1"
    head_revision="${2:-HEAD}"

    if ! git cat-file -e "${head_revision}^{commit}" 2>/dev/null; then
        echo "Head revision ${head_revision} does not resolve to a commit." >&2
        exit 2
    fi

    if [[ "${base_revision}" =~ ^0+$ ]] || ! git cat-file -e "${base_revision}^{commit}" 2>/dev/null; then
        echo "Base revision is unavailable; validating all catalogs."
        mapfile -t contexts < <(all_contexts)
    else
        changed_files="$(git diff --name-only --diff-filter=ACDMRT "${base_revision}" "${head_revision}")"

        if grep -Eq '^utils/|^\.github/actions/install-opm/action\.yaml$|^\.github/workflows/(create-release|sync-catalog|validate-fbc-catalogs)\.yaml$' \
            <<< "${changed_files}"; then
            echo "Validation tooling changed; validating all catalogs."
            mapfile -t contexts < <(all_contexts)
        else
            mapfile -t contexts < <(
                awk -F/ '
                    $1 ~ /^v[0-9]+\.[0-9]+$/ &&
                    NF >= 3 &&
                    ($3 == "graph.yaml" || $3 == "catalog") {
                        print $1 "/" $2
                    }
                ' <<< "${changed_files}" | sort -u
            )
        fi
    fi
else
    usage
    exit 2
fi

if [[ ${#contexts[@]} -eq 0 ]]; then
    echo "No changed FBC catalogs require validation."
    exit 0
fi

echo "Catalog contexts to validate:"
printf '  %s\n' "${contexts[@]}"

failed=0
for context in "${contexts[@]}"; do
    if [[ ! -d "${context}" ]]; then
        echo "Catalog context ${context} was removed; skipping."
        continue
    fi

    if ! "${script_dir}/validate_fbc_graph_sync.sh" "${context}"; then
        failed=1
    fi
done

exit "${failed}"
