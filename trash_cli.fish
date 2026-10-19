#!/usr/bin/env fish
# Description: Safe file deletion - moves files to macOS trash instead of permanently deleting
# Usage: trash_cli <file1> [file2] [file3] ...
# Requirements: macOS
# Notes: Prefers a same-volume move to ~/.Trash, then the native `trash`
#        helper, then Finder AppleScript as the final fallback.
# Example: trash_cli document.txt
#          trash_cli file1.txt file2.pdf document.docx
#
# Improvements (2026-10-19):
# - Removed Finder as the primary backend. Finder automation can fail before
#   the script starts, which previously produced an unhelpful generic error.
# - Added collision-safe same-volume moves and retained external helpers for
#   cross-volume files.
# - Preserved symlinks instead of resolving them to their targets.

function __trash_unique_destination -d "Return a collision-free path in the Trash"
    set -l trash_dir $argv[1]
    set -l file $argv[2]
    set -l name (path basename -- "$file")
    set -l stem (path basename -E -- "$name")
    set -l extension (path extension -- "$name")
    set -l candidate "$trash_dir/$name"
    set -l suffix 2

    while test -e "$candidate"; or test -L "$candidate"
        if test -n "$stem"; and test -n "$extension"
            set candidate "$trash_dir/$stem $suffix$extension"
        else
            set candidate "$trash_dir/$name $suffix"
        end
        set suffix (math "$suffix + 1")
    end

    printf '%s\n' "$candidate"
end

function trash_cli -d "Move files to macOS trash safely"
    if test (count $argv) -eq 0
        echo "Usage: trash_cli <file> [file2] [file3]..." >&2
        echo "Moves specified files to the macOS trash" >&2
        return 1
    end

    if test (command uname -s) != Darwin
        echo "Error: trash_cli only works on macOS" >&2
        return 1
    end

    set -l files
    for file in $argv
        if not test -e "$file"; and not test -L "$file"
            echo "Error: File not found: '$file'" >&2
            return 1
        end

        # Canonicalize without resolving symlinks, so deleting a link does not
        # accidentally target the file it points to.
        set -l abs_path (path normalize -- "$file")
        if not string match -q '/*' -- "$abs_path"
            set abs_path (path normalize -- "$PWD/$abs_path")
        end
        set -a files "$abs_path"
    end

    set -l trash_dir "$HOME/.Trash"
    if not test -d "$trash_dir"
        command mkdir -p -- "$trash_dir"
        or begin
            echo "Error: Could not create trash directory: $trash_dir" >&2
            return 1
        end
    end

    set -l trash_device (command stat -f '%d' "$trash_dir" 2>/dev/null)
    if test -z "$trash_device"
        echo "Error: Could not inspect trash directory: $trash_dir" >&2
        return 1
    end

    echo "Moving to trash:"
    for file in $files
        echo "  - $(path basename -- "$file")"
    end

    set -l failures
    for file in $files
        set -l file_device (command stat -f '%d' "$file" 2>/dev/null)
        set -l move_error
        set -l helper_error

        # A same-volume move is atomic and avoids Finder/AppleScript entirely.
        if test "$file_device" = "$trash_device"
            set -l destination (__trash_unique_destination "$trash_dir" "$file")
            set move_error (command mv -- "$file" "$destination" 2>&1)
            set -l move_status $status
            if test $move_status -eq 0
                continue
            end
        end

        # Let the installed helper handle cross-volume files and volume-local
        # trash directories. It uses NSFileManager rather than Finder.
        if command -sq trash
            set helper_error (command trash "$file" 2>&1)
            set -l helper_status $status
            if test $helper_status -eq 0
                continue
            end
        end

        # Finder remains the last fallback. 'delete' is Finder's native
        # move-to-trash command and does not depend on a 'trash' variable.
        set -l apple_script 'on run argv
    tell application "Finder"
        delete (POSIX file (item 1 of argv))
    end tell
end run'
        set -l finder_error (printf '%s\n' "$apple_script" | command osascript - "$file" 2>&1)
        set -l finder_status $status
        if test $finder_status -eq 0
            continue
        end

        set -a failures "$file"
        if test -n "$move_error"
            echo "Error moving '$file': $move_error" >&2
        end
        if test -n "$helper_error"
            echo "Error from trash helper for '$file': $helper_error" >&2
        end
        if test -n "$finder_error"
            echo "Finder error for '$file': $finder_error" >&2
        end
    end

    if test (count $failures) -gt 0
        echo "Error: Failed to move files to trash: $failures" >&2
        return 1
    end

    echo "Successfully moved to trash"
    return 0
end

# =============================================================================
# ORIGINAL-DELETED LINES PRESERVED AS COMMENTS (2026-10-01)
# Per request, no original implementation text was removed. Every line replaced
# or removed during this improvement pass is retained below as inert commentary.
# =============================================================================
# ORIGINAL-DELETED:     if test (uname -s) != Darwin
# ORIGINAL-DELETED:         set -a files "the POSIX file \"$abs_path\""
# ORIGINAL-DELETED:     # Use osascript to move files to trash via Finder
# ORIGINAL-DELETED:     osascript 2>&1 >/dev/null -e "tell app \"Finder\" to move { "(string join ", " $files)" } to trash"
# ORIGINAL-DELETED:
