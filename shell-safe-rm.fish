#!/usr/bin/env fish

# You could modify these environment variables to change the default constants
# Default to ~/.Trash on Mac, ~/.local/share/Trash/files on Linux.
set -l DEFAULT_TRASH $HOME/.Trash
if test (uname -s) = Linux
    set DEFAULT_TRASH $HOME/.local/share/Trash/files
end

if not set -q SAFE_RM_TRASH
    set -g SAFE_RM_TRASH $DEFAULT_TRASH
end

# Print debug info or not
if not set -q SAFE_RM_DEBUG
    set -g SAFE_RM_DEBUG ""
end

# -------------------------------------------------------------------------------

# Script basename (equivalent of ${0##*/})
set -g COMMAND (basename (status filename))

# Working directory
set -g __DIRNAME (pwd)

# Collision counter for duplicate trash names
set -g GUID 0
set -g TIME ""

function date_time
    set -g TIME (date +%Y-%m-%d_%H-%M-%S)-$GUID
    set -g GUID (math $GUID + 1)
end

function debug
    if test -n "$SAFE_RM_DEBUG"
        echo "[D] $argv" >&2
    end
end


# parse argv -------------------------------------------------------------------------------

function invalid_option
    # rm only takes the second char of the option string for its error message
    echo "rm: illegal option -- "(string sub --start 2 --length 1 -- $argv[1])
    usage
end

function usage
    echo "usage: rm [-f | -i | -I] [-dPRrvW] file ..."
    echo "       unlink file"
    exit 64
end


if test (count $argv) -eq 0
    echo "safe-rm"
    usage
end

set -g ARGS
set -g FILE_NAMES

function split_push_arg
    # Strip leading '-' and split combined short options: -vif -> v,i,f -> -v,-i,-f
    set -l stripped (string sub --start 2 -- $argv[1])
    for ch in (string split "" -- $stripped)
        if test -n "$ch"
            set -ga ARGS "-$ch"
        end
    end
end

function push_arg
    set -ga ARGS $argv[1]
end

function push_file
    set -ga FILE_NAMES $argv[1]
end

# Pre-parse argument vector
# NOTE: Fish case patterns use fnmatch globs — [a-z] character classes are NOT supported.
# Use '--*' and '-*' wildcards; handle the bare '-' edge case explicitly.
set -l ARG_END ""
for arg in $argv
    # Once ARG_END is set, everything is a file (even if it looks like an option)
    if test -n "$ARG_END"
        push_file $arg

    else
        switch $arg
            # rm -- -a  (end-of-options divider — must come before '--*')
            case '--'
                set ARG_END 1
                debug "divider"

            # rm --force a  (long options)
            case '--*'
                push_arg $arg
                debug "option $arg"

            # rm -v -f -i a b  /  rm -vf -ir a b  (short options, possibly combined)
            # '-*' also matches bare '-', so handle that as a file
            case '-*'
                if test "$arg" = '-'
                    push_file $arg
                    debug "file $arg"
                    set ARG_END 1
                else
                    split_push_arg $arg
                    debug "short option $arg"
                end

            # Plain filenames and anything else → file, and stop option parsing
            case '*'
                push_file $arg
                debug "file $arg"
                set ARG_END 1
        end
    end
end

# Flags — use bare 'set' (not set -l) so functions can read these globals
set OPT_FORCE ""
set OPT_INTERACTIVE ""
set OPT_INTERACTIVE_ONCE ""
set OPT_RECURSIVE ""
set OPT_VERBOSE ""

# Global exit code
set EXIT_CODE 0

# Parse options
# NOTE: Fish case does not support [a-z] char-class patterns, so list each
# variant explicitly (e.g. '-r' and '-R' as separate patterns on the same case).
for arg in $ARGS
    switch $arg
        case '-f' '--force'
            set OPT_FORCE 1
            debug "force        : $arg"

        # interactive=always
        case '-i' '--interactive' '--interactive=always'
            set OPT_INTERACTIVE 1
            debug "interactive  : $arg"
            set OPT_INTERACTIVE_ONCE ""

        # interactive=once (exclusive with interactive=always)
        case '-I' '--interactive=once'
            set OPT_INTERACTIVE_ONCE 1
            debug "interactive_once  : $arg"
            set OPT_INTERACTIVE ""

        # both -r and -R are allowed; --recursive and --Recursive
        case '-r' '-R' '--recursive' '--Recursive'
            set OPT_RECURSIVE 1
            debug "recursive    : $arg"

        # only lowercase -v
        case '-v' '--verbose'
            set OPT_VERBOSE 1
            debug "verbose      : $arg"

        case '*'
            invalid_option $arg
    end
end
# /parse argv -------------------------------------------------------------------------------


# Make sure the recycled bin exists
if not test -e "$SAFE_RM_TRASH"
    echo "Directory \"$SAFE_RM_TRASH\" does not exist, do you want create it?"
    printf '(yes/no): '
    read -l answer
    if test "$answer" = yes; or test -z "$answer"
        mkdir -p "$SAFE_RM_TRASH"
    else
        echo "Canceled!"
        exit 1
    end
end


# List all files maintaining outward sequence (contents before the dir itself)
function list_files
    if test -d $argv[1]
        for f in (ls -A -- $argv[1] 2>/dev/null)
            list_files "$argv[1]/$f"
        end
    end
    echo $argv[1]
end


# Move a file or directory into the trash folder
function do_trash
    debug "trash $argv[1]"

    set -l file $argv[1]
    set -l move $file
    set -l base (basename -- $file)
    set -l travel ""

    # Handle relative dirs whose basename starts with '.' (e.g. ./ or ../)
    if test -d "$file"; and test (string sub --start 1 --length 1 -- $base) = '.'
        cd $file
        set move (basename (pwd))
        cd ..
        set travel 1
    end

    set -l trash_name $SAFE_RM_TRASH/$base

    # If a name collision exists in the trash, append a timestamp
    if test -e "$trash_name"
        date_time
        set trash_name "$trash_name-$TIME"
    end

    if test "$OPT_VERBOSE" = 1
        list_files $file
    end

    debug "mv $move to $trash_name"
    mv -- $move $trash_name

    if test "$travel" = 1
        cd $__DIRNAME 2>/dev/null
    end

    return 0
end


function recursive_remove
    for entry in (ls -A -- $argv[1] 2>/dev/null)
        remove "$argv[1]/$entry"
    end
end


function remove
    set -l file $argv[1]

    if test -d "$file"
        # It's a directory

        if test "$OPT_RECURSIVE" != 1
            debug "$file: is a directory"
            echo "$COMMAND: $file: is a directory"
            return 1
        end

        if test "$file" = './'
            echo "$COMMAND: $file: Invalid argument"
            return 1
        end

        if test "$OPT_INTERACTIVE" = 1
            printf 'examine files in directory %s? ' $file
            read -l answer

            # Any answer starting with y/Y → proceed
            if string match -qr '^[yY]' -- $answer
                # Recursively check/remove files first
                recursive_remove $file

                # Then interact with the dir itself
                printf 'remove %s? ' $file
                read -l answer
                if string match -qr '^[yY]' -- $answer
                    set -l dir_contents (ls -A -- $file 2>/dev/null)
                    if test (count $dir_contents) -gt 0
                        echo "$COMMAND: $file: Directory not empty"
                        return 1
                    else
                        do_trash $file
                        debug "trash returned status $status"
                    end
                end
            end
        else
            do_trash $file
            debug "trash returned status $status"
        end

    else
        # It's a regular file

        if test "$OPT_INTERACTIVE" = 1
            printf 'remove %s? ' $file
            read -l answer
            if not string match -qr '^[yY]' -- $answer
                return 0
            end
        end

        do_trash $file
        debug "trash returned status $status"
    end
end


# Debug: report how many targets were collected
debug (count $FILE_NAMES)" files or directory to process: $FILE_NAMES"

# interactive=once: ask once when removing 3+ files or using recursive
if test "$OPT_INTERACTIVE_ONCE" = 1
    if test (count $FILE_NAMES) -gt 2; or test "$OPT_RECURSIVE" = 1
        printf '%s: remove all arguments? ' $COMMAND
        read -l answer
        if not string match -qr '^[yY]' -- $answer
            debug "EXIT_CODE $EXIT_CODE"
            exit $EXIT_CODE
        end
    end
end

for file in $FILE_NAMES
    debug "result file $file"

    if test "$file" = /
        echo "it is dangerous to operate recursively on /"
        echo "are you insane?"
        set EXIT_CODE 1
        debug "EXIT_CODE $EXIT_CODE"
        exit $EXIT_CODE
    end

    if test "$file" = .; or test "$file" = ..
        echo "$COMMAND: \".\" and \"..\" may not be removed"
        set EXIT_CODE 1
        continue
    end

    # Also check /. and /..
    if test (basename -- $file) = .; or test (basename -- $file) = ..
        echo "$COMMAND: \".\" and \"..\" may not be removed"
        set EXIT_CODE 1
        continue
    end

    # Expand wildcards (and redirect errors) — ls -d lets the shell/ls resolve globs
    set -l ls_result (ls -d -- $file 2>/dev/null)
    debug "ls_result: $ls_result"

    if test (count $ls_result) -gt 0
        for f in $ls_result
            remove $f
            set -l s $status
            debug "remove returned status: $s"
            if test $s -ne 0
                set EXIT_CODE 1
            end
        end
    else
        echo "$COMMAND: $file: No such file or directory"
        set EXIT_CODE 1
    end
end

debug "EXIT_CODE $EXIT_CODE"
exit $EXIT_CODE
