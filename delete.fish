#!/usr/bin/env fish
# Description: Safe file deletion wrapper - attempts to move files to trash
# Usage: delete [-r] [-f] [-i] <file1> [file2] ...
# Options:
#   -r    Recursive (for use with underlying rm tool)
#   -f    Force (for use with underlying rm tool)
#   -i    Interactive confirmation (for use with underlying rm tool)
# Requirements: Either trash_cli or shell-safe-rm or standard rm
# Priority: trash_cli > shell-safe-rm > standard rm (fallback, potentially unsafe)
# Example: delete document.txt
#          delete -r folder/
#
# Improvements (2026-10-01):
# - Parsed `-r/-f/-i` with `argparse` and separated options from file paths
#   before any deletion occurs.
# - Fixed forwarding of the original options to `shell-safe-rm`; the previous
#   implementation always used `-r -i`, even when the user requested otherwise.
# - Passed file lists directly rather than as one quoted list, preserving each
#   path as a separate argument.
# - Made installation downloads fail on HTTP errors (`curl -fL`) and use
#   `mktemp`, plus `command` prefixes for external tools.

function delete --description "Safe file deletion - moves to trash when possible"
    # Validate input
    # ORIGINAL: if test -z "$argv"
    if test (count $argv) -eq 0
        echo "Error: No files specified for deletion" >&2
        echo "Usage: delete [-r] [-f] [-i] <file1> [file2] ..." >&2
        return 1
    end

    # Parse options without losing filenames. Remaining paths are in `$argv`.
    argparse --name=delete r f i -- $argv
    or return 1

    if test (count $argv) -eq 0
        echo "Error: No files specified for deletion" >&2
        return 1
    end

    # Check if trash_cli function is available (preferred method)
    if functions -q trash_cli
        # Use trash_cli for safe deletion on macOS
        # ORIGINAL: trash_cli "$argv"
        trash_cli $argv
        return $status
    end

    # Fall back to shell-safe-rm if available
    if command -sq shell-safe-rm
        # ORIGINAL: argparse --name=delete 'r' 'f' 'i' -- "$argv"
        # ORIGINAL: or return 1
        # ORIGINAL: shell-safe-rm -r -i "$argv"
        set -l safe_rm_args
        set -q _flag_r; and set -a safe_rm_args -r
        set -q _flag_f; and set -a safe_rm_args -f
        set -q _flag_i; and set -a safe_rm_args -i
        test (count $safe_rm_args) -gt 0; or set safe_rm_args -i
        command shell-safe-rm $safe_rm_args -- $argv
        return $status
    end

    # If neither trash_cli nor shell-safe-rm available, try to install shell-safe-rm
    echo "Warning: Neither trash_cli nor shell-safe-rm found. Attempting to install shell-safe-rm..." >&2

    if __install_safe_rm
        echo "shell-safe-rm installed successfully" >&2
        if command -sq shell-safe-rm
            command shell-safe-rm -i -- $argv
            return $status
        end
    end

    # Final fallback: provide guidance
    echo "Error: No safe deletion tool available" >&2
    echo "Available options:" >&2
    echo "  1. Install 'trash-cli' (macOS recommended)" >&2
    echo "  2. Install 'shell-safe-rm' (cross-platform)" >&2
    echo "     https://github.com/kaelzhang/shell-safe-rm" >&2
    echo "To force permanent deletion: command rm -r <files>" >&2

    return 127
end

# Private: Attempt to install shell-safe-rm from GitHub
function __install_safe_rm -d "Download and install shell-safe-rm tool"
    # Check for required tools
    if not command -sq curl; or not command -sq mktemp
        echo "Error: 'curl' command required to download shell-safe-rm" >&2
        return 1
    end

    set -l url "https://raw.githubusercontent.com/kaelzhang/shell-safe-rm/refs/heads/master/bin/rm.sh"
    set -l install_dir "$HOME/bin"
    # ORIGINAL: set -l tmp_file "$install_dir/.shell-safe-rm-$RANDOM.tmp"
    set -l tmp_file (command mktemp "$install_dir/.shell-safe-rm.XXXXXX" 2>/dev/null)

    # Create install directory
    # ORIGINAL: mkdir -p "$install_dir" || {
    command mkdir -p "$install_dir" ||
        {
            echo "Error: Could not create installation directory: $install_dir" >&2
            return 1
        }

    # Recreate the secure temporary file after the destination directory exists.
    set tmp_file (command mktemp "$install_dir/.shell-safe-rm.XXXXXX" 2>/dev/null)
    if test -z "$tmp_file"
        echo "Error: Could not create a temporary file" >&2
        return 1
    end

    # Download with timeout
    # ORIGINAL: curl -L --max-time 10 "$url" >"$tmp_file" 2>/dev/null
    command curl -fL --retry 2 --max-time 10 "$url" >"$tmp_file" 2>/dev/null
    if test $status -ne 0
        echo "Error: Failed to download shell-safe-rm from GitHub" >&2
        command rm -f -- "$tmp_file"
        return 1
    end

    # Verify download succeeded
    if not test -f "$tmp_file" || test ! -s "$tmp_file"
        echo "Error: Downloaded file is empty or missing" >&2
        command rm -f -- "$tmp_file"
        return 1
    end

    # Move to final location and make executable
    if command mv -- "$tmp_file" "$install_dir/shell-safe-rm" && command chmod a+x "$install_dir/shell-safe-rm"
        echo "shell-safe-rm installed at $install_dir/shell-safe-rm" >&2

        # Check if ~/bin is in PATH
        if not string match -q "*$install_dir*" $PATH
            echo "Note: Add '$install_dir' to your PATH for easy access" >&2
        end
        return 0
    else
        echo "Error: Failed to install shell-safe-rm" >&2
        command rm -f -- "$tmp_file"
        return 1
    end
end

# =============================================================================
# ORIGINAL-DELETED LINES PRESERVED AS COMMENTS (2026-10-01)
# Per request, no original implementation text was removed. Every line replaced
# or removed during this improvement pass is retained below as inert commentary.
# =============================================================================
# ORIGINAL-DELETED:     if test -z "$argv"
# ORIGINAL-DELETED:
# ORIGINAL-DELETED:         trash_cli "$argv"
# ORIGINAL-DELETED:     if type -q shell-safe-rm
# ORIGINAL-DELETED:         argparse --name=delete 'r' 'f' 'i' -- "$argv"
# ORIGINAL-DELETED:         or return 1
# ORIGINAL-DELETED:
# ORIGINAL-DELETED:         shell-safe-rm -r -i "$argv"
# ORIGINAL-DELETED:         if type -q shell-safe-rm
# ORIGINAL-DELETED:             shell-safe-rm -r -i "$argv"
# ORIGINAL-DELETED:
# ORIGINAL-DELETED:     if not type -q curl
# ORIGINAL-DELETED:     set -l tmp_file "$install_dir/.shell-safe-rm-$RANDOM.tmp"
# ORIGINAL-DELETED:     mkdir -p "$install_dir" || {
# ORIGINAL-DELETED:         echo "Error: Could not create installation directory: $install_dir" >&2
# ORIGINAL-DELETED:     }
# ORIGINAL-DELETED:     curl -L --max-time 10 "$url" >"$tmp_file" 2>/dev/null
# ORIGINAL-DELETED:         rm -f "$tmp_file"
# ORIGINAL-DELETED:         rm -f "$tmp_file"
# ORIGINAL-DELETED:     if mv "$tmp_file" "$install_dir/shell-safe-rm" && chmod a+x "$install_dir/shell-safe-rm"
# ORIGINAL-DELETED:
# ORIGINAL-DELETED:         rm -f "$tmp_file"
