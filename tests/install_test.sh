#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

export HOME="$tmp_dir/home"
export XDG_CONFIG_HOME="$tmp_dir/config"
mkdir -p "$HOME"

fake_bin="$tmp_dir/fake-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' Linux
EOF
chmod +x "$fake_bin/uname"

non_mac_output="$tmp_dir/non-mac-output"
if PATH="$fake_bin:$PATH" sh "$repo_dir/install.sh" >"$non_mac_output" 2>&1; then
    printf 'install.sh should abort on non-macOS systems\n' >&2
    exit 1
fi
if ! grep -q 'only supports macOS' "$non_mac_output"; then
    printf 'install.sh did not report a non-macOS system:\n' >&2
    cat "$non_mac_output" >&2
    exit 1
fi

minimal_bin="$tmp_dir/minimal-bin"
mkdir -p "$minimal_bin"
for tool in uname dirname mkdir install; do
    ln -s "$(command -v "$tool")" "$minimal_bin/$tool"
done

no_fish_path_output="$tmp_dir/no-fish-path-output"
if ! PATH="$minimal_bin" /bin/sh "$repo_dir/install.sh" >"$no_fish_path_output" 2>&1; then
    printf 'install.sh could not find Fish outside PATH:\n' >&2
    cat "$no_fish_path_output" >&2
    exit 1
fi

sh "$repo_dir/install.sh"

functions_dir="$XDG_CONFIG_HOME/fish/functions"
test -f "$functions_dir/delete.fish"
test -f "$functions_dir/trash_cli.fish"
cmp -s "$repo_dir/delete.fish" "$functions_dir/delete.fish"
cmp -s "$repo_dir/trash_cli.fish" "$functions_dir/trash_cli.fish"

fish -c 'type -q delete; and type -q trash_cli'

printf 'install.sh tests passed\n'
