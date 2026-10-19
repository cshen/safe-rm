#!/bin/sh

set -eu

if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s\n' "Error: install.sh only supports macOS." >&2
    exit 1
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
functions_dir="$config_home/fish/functions"

find_fish() {
    if command -v fish >/dev/null 2>&1; then
        return 0
    fi

    for candidate in \
        /opt/homebrew/bin/fish \
        /usr/local/bin/fish \
        /opt/local/bin/fish \
        /usr/bin/fish \
        "$HOME/bin/fish" \
        "$HOME/.local/bin/fish"; do
        if [ -x "$candidate" ]; then
            return 0
        fi
    done

    return 1
}

if ! find_fish; then
    printf '%s\n' "Error: Fish shell is not installed or could not be found." >&2
    printf '%s\n' "Checked PATH, /opt/homebrew/bin, /usr/local/bin, /opt/local/bin, /usr/bin, $HOME/bin, and $HOME/.local/bin." >&2
    exit 1
fi

for file in delete.fish trash_cli.fish; do
    if [ ! -f "$script_dir/$file" ]; then
        printf '%s\n' "Error: Missing required file: $script_dir/$file" >&2
        exit 1
    fi
done

mkdir -p "$functions_dir"
install -m 0644 "$script_dir/delete.fish" "$functions_dir/delete.fish"
install -m 0644 "$script_dir/trash_cli.fish" "$functions_dir/trash_cli.fish"

printf '%s\n' "Installed delete.fish and trash_cli.fish to:"
printf '  %s\n' "$functions_dir"
printf '%s\n' "Start a new Fish shell or run 'exec fish' to load them."

# shellcheck disable=SC2016
printf '%s\n' 'strongly suggest to define a new abbr: `abbr -a rm delete -i --`'
