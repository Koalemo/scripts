#!/usr/bin/env bash
# deps/scripts/setup/fetch-repos.sh [-y|--yes]
# Downloads/syncs git submodule dependencies only.

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

ensure_tool() {
    local name="$1" check_fn="$2" install_fn="$3"
    if "$check_fn"; then
        echo "[fetch-repos] $name already present, skipping."
        return
    fi
    local answer="n"
    if [ "$ASSUME_YES" -eq 1 ]; then
        answer="y"
    else
        read -p "$name not found. Install it now? [y/N] " answer
    fi
    case "$answer" in
        y|Y|yes|Yes)
            echo "[fetch-repos] Installing $name ..."
            if "$install_fn"; then
                echo "[fetch-repos] $name installed."
            else
                echo "[fetch-repos] ERROR: failed to install $name."
            fi
            ;;
        *)
            echo "[fetch-repos] Skipping $name install."
            ;;
    esac
}

while IFS= read -r name; do
    submodule_dirty() { [ -n "$(git -C "$CALLER_ROOT/$1" status --porcelain 2>/dev/null)" ]; }
    submodule_check() { ! git -C "$CALLER_ROOT" submodule status -- "$1" | grep -qE '^[+-]'; }
    submodule_install() {
        if submodule_dirty "$1"; then
            echo "[fetch-repos] WARNING: submodule '$1' has uncommitted changes, skipping update."
            return 1
        fi
        git -C "$CALLER_ROOT" submodule update --init --recursive -- "$1"
    }
    ensure_tool "submodule:$name" "submodule_check $name" "submodule_install $name"
done < <(git -C "$CALLER_ROOT" config --file "$CALLER_ROOT/.gitmodules" --get-regexp path | awk '{print $2}') 3<&0 <&-
