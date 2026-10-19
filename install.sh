#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
functions_dir="$config_home/fish/functions"

if ! command -v fish >/dev/null 2>&1; then
    printf '%s\n' "Error: Fish shell is not installed or not on PATH." >&2
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
