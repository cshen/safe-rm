# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

safe-rm is a safer `rm` replacement that moves files to the system trash instead of permanently deleting them. Supports common `rm` flags so it can be used as a drop-in alias. Three standalone implementations with no shared dependencies or build system.

## Project structure

| File | Language | Platform | Trash mechanism |
|---|---|---|---|
| `safe-rm.py` | Python 3.11+ (uv script) | macOS, Linux | `shutil.move` to `~/.Trash` or `~/.local/share/Trash/files` |
| `shell-safe-rm.fish` | Fish shell | macOS, Linux | `mv` to `~/.Trash` or `~/.local/share/Trash/files` |
| `delete.fish` | Fish shell (function) | macOS only | AppleScript → Finder Trash |

`safe-rm.py` and `shell-safe-rm.fish` are feature-identical ports of each other — they share the same CLI flags, safety guards, and trash-collision logic. `delete.fish` is a simpler macOS-only variant.

## Running / testing

No build step. Each file is a standalone script.

```bash
# Python
uv run safe-rm.py -v testfile.txt
SAFE_RM_DEBUG=1 uv run safe-rm.py -ri testdir/

# Fish
fish shell-safe-rm.fish -v testfile.txt
source delete.fish && delete -i testfile.txt
```

Set `SAFE_RM_TRASH` to override the trash path. Set `SAFE_RM_DEBUG=1` for debug output on stderr (Python and shell variants).

## Architecture notes for changes

- `safe-rm.py` and `shell-safe-rm.fish` should stay in sync on behavior. When adding a feature or fixing a bug in one, apply the equivalent change to the other.
- The argument parsing in both follows the same pre-parse → parse pattern: first split argv into options and files (with `--` divider, combined short-flag splitting, and a bare `-` acting as file + end-of-options), then interpret each option token.
- Safety guards (rejecting `/`, `.`, `..`, and paths ending in `/.` or `/..`) are duplicated in both files — keep them consistent.
- Name-collision resolution in the trash appends a timestamp (`YYYY-MM-DD_HH-MM-SS-N`) via `shutil.move` / `mv`, not a separate info file (unlike the FreeDesktop Trash spec).
- `delete.fish` validates all targets exist before acting on any; symlinks are `unlink`ed directly without involving Finder.
