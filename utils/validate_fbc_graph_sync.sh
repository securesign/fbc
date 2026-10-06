#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path-context>" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
path_context="${1%/}"
graph_file="${repo_root}/${path_context}/graph.yaml"

if [[ ! -f "${graph_file}" ]]; then
    echo "Required graph file ${path_context}/graph.yaml does not exist." >&2
    exit 1
fi

package="$(
    awk '
        $1 == "name:" {
            value = $2
            gsub(/["'\''"]/, "", value)
            last_name = value
        }
        $1 == "schema:" && $2 == "olm.package" {
            print last_name
            exit
        }
        $1 == "package:" {
            value = $2
            gsub(/["'\''"]/, "", value)
            print value
            exit
        }
    ' "${graph_file}"
)"

if [[ -z "${package}" ]]; then
    echo "Failed to resolve package name from ${path_context}/graph.yaml." >&2
    exit 1
fi

catalog_dir="${repo_root}/${path_context}/catalog/${package}"
catalog_file="${catalog_dir}/catalog.json"

if [[ ! -d "${catalog_dir}" ]]; then
    echo "Resolved package ${package}, but catalog directory ${path_context}/catalog/${package} does not exist." >&2
    exit 1
fi

if [[ ! -f "${catalog_file}" ]]; then
    echo "Resolved package ${package}, but catalog file ${path_context}/catalog/${package}/catalog.json does not exist." >&2
    exit 1
fi

echo "Validating ${path_context} for package ${package}"
echo "Running opm validate on committed catalog..."
opm validate "${catalog_dir}"

echo "Checking graph.yaml and catalog.json stay in sync..."
graph_norm="$(mktemp)"
converted_template="$(mktemp)"
committed_norm="$(mktemp)"
trap 'rm -f "${graph_norm}" "${converted_template}" "${committed_norm}"' EXIT

normalize_template() {
    awk '
        function flush() {
            if (current != "") {
                if (!(previous ~ /^image:/ && current ~ /^name: /)) {
                    print current
                }
                previous = current
                current = ""
            }
        }
        {
            sub(/[[:space:]]+$/, "", $0)
            if ($0 ~ /^[[:space:]]*$/ || $0 == "---") {
                next
            }

            line = $0
            sub(/^[[:space:]]+/, "", line)

            if (line ~ /^- / || line ~ /^[A-Za-z0-9_.-]+:/) {
                flush()
                sub(/^- /, "", line)
                current = line
            } else if (current == "") {
                current = line
            } else {
                current = current " " line
            }
        }
        END {
            flush()
        }
    ' "$1" | sort
}

opm alpha convert-template basic "${catalog_file}" -o yaml > "${converted_template}"
normalize_template "${graph_file}" > "${graph_norm}"
normalize_template "${converted_template}" > "${committed_norm}"

if ! diff -q "${graph_norm}" "${committed_norm}" >/dev/null 2>&1; then
    echo "graph.yaml and catalog.json are out of sync" >&2
    diff -u "${graph_norm}" "${committed_norm}" | head -50 || true
    exit 1
fi

echo "Committed catalog is valid and graph.yaml is in sync."
