#!/usr/bin/env bash
# delete — Move specified files to the macOS Trash (Bash port of delete.fish)
#
# Usage: delete [-f] [-i] [--] <files...>
#
#   -f, --force       Skip existence checks for missing targets
#   -i, --interactive Prompt before each removal
#   --                End of options; remaining arguments are files
#
# Symlinks are unlinked directly. Regular files and directories are moved to
# the Trash via Finder's AppleScript interface (macOS only).

set -o noglob

# ── option parsing ────────────────────────────────────────────────────────

force=0
interactive=0
targets=()
end_of_opts=0

for arg in "$@"; do
    if (( end_of_opts )); then
        targets+=("$arg")
        continue
    fi
    case "$arg" in
        --)
            end_of_opts=1
            ;;
        -f|--force)
            force=1
            ;;
        -i|--interactive)
            interactive=1
            ;;
        -*)
            echo >&2 "delete: unknown option: $arg"
            echo >&2 "Usage: delete [-f] [-i] [--] <files...>"
            exit 1
            ;;
        *)
            targets+=("$arg")
            ;;
    esac
done

# ── basic sanity checks ───────────────────────────────────────────────────

if (( ${#targets[@]} == 0 )); then
    echo >&2 "Usage: delete [-f] [-i] [--] <files...>"
    exit 1
fi

if [[ "$(uname -s)" != Darwin ]]; then
    echo >&2 "delete: macOS not detected."
    exit 1
fi

# ── validate every target first ───────────────────────────────────────────
# Use the original argument (not resolved) so prompts and unlink match what
# the user typed. Check -L before -e: -e follows symlinks and misses broken ones.

valid_targets=()
had_error=0

for file in "${targets[@]}"; do
    if [[ -L "$file" || -e "$file" ]]; then
        valid_targets+=("$file")
    elif (( ! force )); then
        echo >&2 "delete: No such file or directory: '$file'"
        had_error=1
    fi
done

# Abort if any target was missing — don't trash the ones that did exist
if (( had_error )); then
    exit 1
fi

if (( ${#valid_targets[@]} == 0 )); then
    exit 0
fi

# ── helper: resolve a path to an absolute POSIX path ─────────────────────
resolve_path() {
    local file="$1"
    if [[ "$file" == /* ]]; then
        echo "$file"
    else
        echo "$PWD/$file"
    fi
}

# ── per-file: confirm, then route to unlink or Finder ────────────────────

osascript_args=()
exit_code=0

for file in "${valid_targets[@]}"; do
    # -i prompt: "remove <arg>?" — skipped when -f is set
    if (( interactive && ! force )); then
        printf 'remove %s? ' "$file"
        read -r answer
        case "$answer" in
            [yY]*) ;;
            *) continue ;;
        esac
    fi

    # Symlinks are unlinked directly — no need to involve Finder
    if [[ -L "$file" ]]; then
        if unlink "$file"; then
            echo >&2 "delete: unlinked '$file'."
        else
            echo >&2 "delete: could not unlink '$file'"
            exit_code=1
        fi
    else
        osascript_args+=("the POSIX file \"$(resolve_path "$file")\"")
    fi
done

# ── move regular files/dirs to Trash via Finder ───────────────────────────

if (( ${#osascript_args[@]} > 0 )); then
    # Build comma-separated list for the AppleScript record
    joined_args=""
    for item in "${osascript_args[@]}"; do
        if [[ -z "$joined_args" ]]; then
            joined_args="$item"
        else
            joined_args="$joined_args, $item"
        fi
    done

    if osascript >/dev/null 2>&1 \
        -e "tell app \"Finder\" to move { $joined_args } to trash"; then
        echo >&2 "delete: moved ${#osascript_args[@]} item(s) to Trash."
    else
        echo >&2 "delete: Finder refused to move the files to Trash."
        exit_code=1
    fi
fi

exit "$exit_code"
