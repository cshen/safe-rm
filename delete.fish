function delete --description 'Move specified files to the macOS Trash'

    # ── option parsing ────────────────────────────────────────────────────────
    set -l force 0
    set -l interactive 0
    set -l targets
    set -l end_of_opts 0

    for arg in $argv
        if test $end_of_opts -eq 1
            set -a targets $arg
            continue
        end
        switch $arg
            case --
                set end_of_opts 1
            case -f --force
                set force 1
            case -i --interactive
                set interactive 1
            case '-*'
                echo >&2 "delete: unknown option: $arg"
                echo >&2 "Usage: delete [-f] [-i] [--] <files...>"
                return 1
            case '*'
                set -a targets $arg
        end
    end

    # ── basic sanity checks ───────────────────────────────────────────────────
    if test (count $targets) -eq 0
        echo >&2 "Usage: delete [-f] [-i] [--] <files...>"
        return 1
    end

    if test (uname -s) != Darwin
        echo >&2 "delete: macOS not detected."
        return 1
    end

    # ── validate every target first ───────────────────────────────────────────
    # Use the original argument (not resolved) so prompts and unlink match what
    # the user typed. Check -L before -e: -e follows symlinks and misses broken ones.
    set -l valid_targets
    set -l had_error 0

    for file in $targets
        if test -L "$file"; or test -e "$file"
            set -a valid_targets "$file"
        else if test $force -eq 0
            echo >&2 "delete: No such file or directory: '$file'"
            set had_error 1
        end
    end

    # Abort if any target was missing — don't trash the ones that did exist
    if test $had_error -eq 1
        return 1
    end

    if test (count $valid_targets) -eq 0
        return 0
    end

    # ── per-file: confirm, then route to unlink or Finder ────────────────────
    set -l osascript_args
    set -l exit_code 0

    for file in $valid_targets
        # -i prompt: "remove <arg>?" — skipped when -f is set
        if test $interactive -eq 1; and test $force -eq 0
            printf 'remove %s? ' "$file"
            read -l answer
            if not string match -qr '^[yY]' -- $answer
                continue
            end
        end

        # Symlinks are unlinked directly — no need to involve Finder
        if test -L "$file"
            unlink "$file"
            if test $status -ne 0
                echo >&2 "delete: could not unlink '$file'"
                set exit_code 1
            end
        else
            set -a osascript_args "the POSIX file \""(path resolve "$file")"\""
        end
    end

    # ── move regular files/dirs to Trash via Finder ───────────────────────────
    if test (count $osascript_args) -gt 0
        osascript >/dev/null 2>&1 \
            -e "tell app \"Finder\" to move { "(string join ", " $osascript_args)" } to trash"

        if test $status -ne 0
            echo >&2 "delete: Finder refused to move the files to Trash."
            set exit_code 1
        end
    end

    return $exit_code
end
