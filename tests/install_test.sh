#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

export HOME="$tmp_dir/home"
export XDG_CONFIG_HOME="$tmp_dir/config"
mkdir -p "$HOME"

sh "$repo_dir/install.sh"

functions_dir="$XDG_CONFIG_HOME/fish/functions"
test -f "$functions_dir/delete.fish"
test -f "$functions_dir/trash_cli.fish"
cmp -s "$repo_dir/delete.fish" "$functions_dir/delete.fish"
cmp -s "$repo_dir/trash_cli.fish" "$functions_dir/trash_cli.fish"

fish -c 'type -q delete; and type -q trash_cli'

printf 'install.sh tests passed\n'
