#!/usr/bin/env bash
# deps/scripts/setup/fetch-tarballs.sh [-y|--yes]
# Downloads tar.gz/tgz dependencies described in tarballs.yaml
# at the root of the calling repo.

set -uo pipefail

ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
    esac
done

find_repo_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        [ -e "$dir/.git" ] && { echo "$dir"; return 0; }
        dir=$(dirname "$dir")
    done
    return 1
}

CALLER_ROOT=$(find_repo_root) || { echo "[fetch-tarballs] ERROR: could not find repo root."; exit 1; }
mkdir -p "$CALLER_ROOT/deps"

MANIFEST="$CALLER_ROOT/tarballs.yaml"
[ -f "$MANIFEST" ] || { echo "[fetch-tarballs] No tarballs.yaml found, nothing to do."; exit 0; }

fetch_tarball() {
    local name="$1" url="$2" hash="$3"
    local dest="$CALLER_ROOT/deps/$name"
    local archive="$CALLER_ROOT/deps/.cache/$name.archive"

    if [ -d "$dest" ]; then
        local actual_hash=""
        [ -f "$archive" ] && actual_hash=$(sha256sum "$archive" | awk '{print $1}')
        if [ -n "$hash" ] && [ -n "$actual_hash" ] && [ "$hash" != "$actual_hash" ]; then
            echo "[fetch-tarballs] WARNING: '$name' hash mismatch."
            local answer="n"
            if [ "$ASSUME_YES" -eq 1 ]; then answer="y"; else
                read -p "Overwrite '$name'? [y/N] " answer
            fi
            case "$answer" in y|Y|yes|Yes) ;; *) return 0 ;; esac
        else
            return 0
        fi
    fi

    mkdir -p "$CALLER_ROOT/deps/.cache"
    curl -fsSL "$url" -o "$archive"
    mkdir -p "$dest"
    tar -xf "$archive" -C "$dest" --strip-components=1
}

# Minimal YAML parse: name/url/hash blocks
name="" url="" hash=""
while IFS= read -r line; do
    case "$line" in
        [a-zA-Z0-9_-]*:) [ -n "$name" ] && fetch_tarball "$name" "$url" "$hash"
                         name="${line%:}"; url=""; hash="" ;;
        *url:*)  url=$(echo "$line" | awk '{print $2}') ;;
        *hash:*) hash=$(echo "$line" | awk '{print $2}') ;;
    esac
done < "$MANIFEST"
[ -n "$name" ] && fetch_tarball "$name" "$url" "$hash"
