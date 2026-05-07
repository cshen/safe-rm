# safe-rm

A safer `rm` replacement that **moves files to the system trash** instead of permanently deleting them. Supports the common `rm` flags so it can be used as a drop-in alias.

Three implementations are provided — pick whichever fits your workflow:

| File | Runtime | Platform |
|---|---|---|
| `shell-safe-rm.fish` | [Fish shell](https://fishshell.com/) | macOS, Linux |
| `safe-rm.py` | Python 3.11+ via [uv](https://docs.astral.sh/uv/) | macOS, Linux |
| `delete.fish` | [Fish shell](https://fishshell.com/) | macOS only |
| `delete.sh` |    Bash shell | macOS only |


## `delete.fish`

A lightweight macOS-only fish function that moves files to the **macOS Trash via Finder**. Symlinks are removed with `unlink` instead of going through Finder.

### Usage

```
delete [-f] [-i] [--] <files...>
```

### Flags

| Flag | Description |
|---|---|
| `-f`, `--force` | Suppress error messages for missing files; overrides `-i` |
| `-i`, `--interactive` | Prompt `remove <file>?` before each removal (same behaviour as `rm -i`) |
| `--` | End option parsing; treat all remaining arguments as file names |

### Behaviour

- Files and directories are moved to the macOS Trash via Finder (AppleScript).
- **Symlinks** (including broken ones) are removed with `unlink` — Finder is not involved.
- By default files are trashed without a prompt. Use `-i` to confirm each one interactively.
- All targets are validated before any action is taken. If any target is missing the whole operation is aborted (use `-f` to silence missing-file errors and continue).
- `-f` overrides `-i`: combined `-fi` skips all prompts.

### Installation

Source the file from your `config.fish`, or copy it to a directory on `$PATH`:

```fish
# Source in config.fish
source path/to/delete.fish

# Or install as a standalone command
cp delete.fish ~/.config/fish/functions/delete.fish
```

I'd suggest: `abbr -a rm delete -i --` 
to alias `rm` to `delete` with interactive mode by default, but you can customize the alias however you like.

---

## `shell-safe-rm.fish` and `safe-rm.py`

### Trash location

| OS | Default path |
|---|---|
| macOS | `~/.Trash` |
| Linux | `~/.local/share/Trash/files` |

If the trash directory does not exist you will be prompted to create it. Override the path with the `SAFE_RM_TRASH` environment variable.

### Usage

```
safe-rm [-f | -i | -I] [-rRvW] file ...
```

### Flags

| Flag | Description |
|---|---|
| `-f`, `--force` | Suppress error messages for missing files |
| `-i`, `--interactive` | Prompt before every removal |
| `-I`, `--interactive=once` | Prompt once when removing 3+ files or using `-r` |
| `-r`, `-R`, `--recursive` | Remove directories and their contents |
| `-v`, `--verbose` | Print each file name as it is removed |
| `--` | End option parsing; treat remaining arguments as file names |

### Safety guardrails

- `/` is always refused.
- `.` and `..` (and paths ending in `/.` or `/..`) are always refused.
- Name collisions in the trash are resolved by appending a timestamp.

### Installation

#### Fish shell

Source or copy `shell-safe-rm.fish` and add an alias in your `config.fish`:

```fish
alias rm='path/to/shell-safe-rm.fish'
```
or
```fish
abbr -a rm 'path/to/shell-safe-rm.fish'
```

Or copy it somewhere on your `$PATH` (e.g. `~/.local/bin/rm`, `~/bin/rm`) and make it executable:

```fish
cp shell-safe-rm.fish ~/.local/bin/rm
chmod +x ~/.local/bin/rm
```

#### Python (uv script)

`safe-rm.py` uses [uv's inline script metadata](https://docs.astral.sh/uv/guides/scripts/) and requires no manual dependency installation.

```bash
# Run directly
uv run safe-rm.py myfile.txt

# Or install as a system command
cp safe-rm.py ~/.local/bin/rm
chmod +x ~/.local/bin/rm
```

### Environment variables

| Variable | Description |
|---|---|
| `SAFE_RM_TRASH` | Override the trash directory |
| `SAFE_RM_DEBUG` | Set to any non-empty value to print debug output to stderr |
