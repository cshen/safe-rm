# safe-rm

A safer `rm` replacement that **moves files to the system trash** instead of permanently deleting them. Supports the common `rm` flags so it can be used as a drop-in alias.

Two implementations are provided — pick whichever fits your workflow:

| File | Runtime |
|---|---|
| `shell-safe-rm.fish` | [Fish shell](https://fishshell.com/) |
| `safe-rm.py` | Python 3.11+ via [uv](https://docs.astral.sh/uv/) |

## Trash location

| OS | Default path |
|---|---|
| macOS | `~/.Trash` |
| Linux | `~/.local/share/Trash/files` |

If the trash directory does not exist you will be prompted to create it. Override the path with the `SAFE_RM_TRASH` environment variable.

## Usage

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

## Installation

### Fish shell

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

### Python (uv script)

`safe-rm.py` uses [uv's inline script metadata](https://docs.astral.sh/uv/guides/scripts/) and requires no manual dependency installation.

```bash
# Run directly
uv run safe-rm.py myfile.txt

# Or install as a system command
cp safe-rm.py ~/.local/bin/rm
chmod +x ~/.local/bin/rm
```

## Environment variables

| Variable | Description |
|---|---|
| `SAFE_RM_TRASH` | Override the trash directory |
| `SAFE_RM_DEBUG` | Set to any non-empty value to print debug output to stderr |
