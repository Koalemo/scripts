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

CALLER_ROOT=$(find_repo_root) || { echo "[fetch-repos] ERROR: could not find repo root."; exit 1; }
mkdir -p "$CALLER_ROOT/deps"

ensure_tool() {
    local name="$1" check_fn="$2" install_fn="$3"
    if eval "$check_fn"; then
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
            if eval "$install_fn"; then
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

mapfile -t submodule_names < <(git -C "$CALLER_ROOT" config --file "$CALLER_ROOT/.gitmodules" --get-regexp path | awk '{print $2}')
for name in "${submodule_names[@]}"; do

    submodule_state() {
        local status_line
        status_line=$(git -C "$CALLER_ROOT" submodule status -- "$1" 2>/dev/null)
        if [ -z "$status_line" ]; then
            echo "unregistered"      # no gitlink at all -> pathspec error case
        elif [[ "$status_line" == -* ]]; then
            echo "not_initialized"   # registered, never checked out
        elif [[ "$status_line" == +* ]]; then
            echo "wrong_commit"      # checked out, but HEAD != pinned commit
        else
            echo "ok"
        fi
    }

    submodule_check() { [ "$(submodule_state "$1")" = "ok" ]; }

    submodule_install() {
        local state
        state=$(submodule_state "$1")
        case "$state" in
            unregistered)
                echo "[fetch-repos] ERROR: '$1' has no gitlink in the index — run 'git submodule add' once manually."
                return 1
                ;;
            not_initialized)
                git -C "$CALLER_ROOT" submodule update --init --recursive -- "$1"
                ;;
            wrong_commit)
                if submodule_dirty "$1"; then
                    echo "[fetch-repos] WARNING: '$1' has uncommitted changes, skipping update."
                    return 1
                fi
                echo "[fetch-repos] '$1' is on a different commit than expected, updating..."
                git -C "$CALLER_ROOT" submodule update --init --recursive -- "$1"
                ;;
        esac
    }

    ensure_tool "submodule:$name" "submodule_check $name" "submodule_install $name"
  done
