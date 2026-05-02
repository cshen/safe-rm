#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""safe-rm.py — Python port of shell-safe-rm.fish

Moves files/directories to a trash folder instead of permanently deleting them.

Environment variables:
  SAFE_RM_TRASH   Override the trash directory (default: ~/.Trash on macOS,
                  ~/.local/share/Trash/files on Linux)
  SAFE_RM_DEBUG   Set to any non-empty string to enable debug output on stderr
"""

import os
import platform
import re
import shutil
import sys
from datetime import datetime


# ---------------------------------------------------------------------------
# Environment / globals
# ---------------------------------------------------------------------------

_DEFAULT_TRASH = os.path.expanduser("~/.Trash")
if platform.system() == "Linux":
    _DEFAULT_TRASH = os.path.expanduser("~/.local/share/Trash/files")

SAFE_RM_TRASH: str = os.environ.get("SAFE_RM_TRASH", _DEFAULT_TRASH)
SAFE_RM_DEBUG: str = os.environ.get("SAFE_RM_DEBUG", "")

# Equivalent of ${0##*/}
COMMAND: str = os.path.basename(sys.argv[0])

# Remember the original working directory (needed after cd tricks in do_trash)
_DIRNAME: str = os.getcwd()

# Collision counter for duplicate trash names
_guid: int = 0
_time_str: str = ""

# Option flags — module-level so all functions share them
OPT_FORCE = False
OPT_INTERACTIVE = False
OPT_INTERACTIVE_ONCE = False
OPT_RECURSIVE = False
OPT_VERBOSE = False

EXIT_CODE = 0


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

def _date_time() -> None:
    global _guid, _time_str
    _time_str = datetime.now().strftime("%Y-%m-%d_%H-%M-%S") + f"-{_guid}"
    _guid += 1


def _debug(msg: str) -> None:
    if SAFE_RM_DEBUG:
        print(f"[D] {msg}", file=sys.stderr)


def _ask(prompt: str) -> str:
    """Print prompt without newline, read a line. Returns '' on EOF/interrupt."""
    try:
        return input(prompt)
    except (EOFError, KeyboardInterrupt):
        return ""


def _invalid_option(opt: str) -> None:
    # rm shows only the second character of the flag string
    char = opt[1:2] if len(opt) > 1 else ""
    print(f"rm: illegal option -- {char}")
    _usage()


def _usage() -> None:
    print("usage: rm [-f | -i | -I] [-dPRrvW] file ...")
    print("       unlink file")
    sys.exit(64)


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def _parse_argv(argv: list[str]) -> tuple[list[str], list[str]]:
    """Pre-parse argv into (option_tokens, file_paths).

    Mirrors the bash/fish pre-parse logic:
      '--'        → end-of-options divider (not added to either list)
      '--xyz'     → pushed whole to options
      '-abc'      → split into ['-a', '-b', '-c'] and pushed to options
      bare '-'    → pushed to files, ends option scanning
      anything else → pushed to files, ends option scanning
    """
    options: list[str] = []
    files: list[str] = []
    arg_end = False

    for arg in argv:
        if arg_end:
            files.append(arg)

        elif arg == "--":
            arg_end = True
            _debug("divider")

        elif arg.startswith("--") and len(arg) > 2:
            options.append(arg)
            _debug(f"option {arg}")

        elif arg.startswith("-") and len(arg) > 1:
            # Split combined short options: -vrf → -v, -r, -f
            for ch in arg[1:]:
                options.append(f"-{ch}")
            _debug(f"short option {arg}")

        else:
            # Plain filename or bare '-'
            files.append(arg)
            _debug(f"file {arg}")
            arg_end = True

    return options, files


def _parse_options(option_args: list[str]) -> None:
    global OPT_FORCE, OPT_INTERACTIVE, OPT_INTERACTIVE_ONCE, OPT_RECURSIVE, OPT_VERBOSE

    for arg in option_args:
        if arg in ("-f", "--force"):
            OPT_FORCE = True
            _debug(f"force        : {arg}")

        elif arg in ("-i", "--interactive", "--interactive=always"):
            OPT_INTERACTIVE = True
            OPT_INTERACTIVE_ONCE = False
            _debug(f"interactive  : {arg}")

        elif arg in ("-I", "--interactive=once"):
            OPT_INTERACTIVE_ONCE = True
            OPT_INTERACTIVE = False
            _debug(f"interactive_once  : {arg}")

        elif arg in ("-r", "-R", "--recursive", "--Recursive"):
            OPT_RECURSIVE = True
            _debug(f"recursive    : {arg}")

        elif arg in ("-v", "--verbose"):
            OPT_VERBOSE = True
            _debug(f"verbose      : {arg}")

        else:
            _invalid_option(arg)


# ---------------------------------------------------------------------------
# Core operations
# ---------------------------------------------------------------------------

def _list_files(path: str) -> None:
    """Print files in outward order: directory contents recursively, then the
    directory itself — mirroring 'rm -v' outward listing sequence."""
    if os.path.isdir(path):
        try:
            entries = os.listdir(path)
        except OSError:
            entries = []
        for entry in entries:
            _list_files(os.path.join(path, entry))
    print(path)


def _do_trash(file_path: str) -> int:
    """Move file_path into SAFE_RM_TRASH, handling name collisions."""
    _debug(f"trash {file_path}")

    file = file_path
    move = file
    base = os.path.basename(file)
    travel = False

    # Special handling for relative dirs whose basename starts with '.'
    # (e.g. ./.git, .hidden_dir): cd in to get the real name from pwd,
    # then cd back so mv works from the parent.
    if os.path.isdir(file) and base.startswith("."):
        os.chdir(file)
        move = os.path.basename(os.getcwd())
        os.chdir("..")
        travel = True

    trash_name = os.path.join(SAFE_RM_TRASH, base)

    # Append a timestamp when a name collision exists in the trash
    if os.path.lexists(trash_name):
        _date_time()
        trash_name = f"{trash_name}-{_time_str}"

    if OPT_VERBOSE:
        _list_files(file)

    _debug(f"mv {move} to {trash_name}")
    shutil.move(move, trash_name)

    if travel:
        try:
            os.chdir(_DIRNAME)
        except OSError:
            pass

    return 0


def _recursive_remove(dir_path: str) -> None:
    """Call _remove on every entry inside dir_path (mirrors recursive_remove)."""
    try:
        entries = os.listdir(dir_path)
    except OSError:
        entries = []
    for entry in entries:
        _remove(os.path.join(dir_path, entry))


def _remove(file_path: str) -> int:
    """Trash file_path, honouring interactive / recursive flags."""
    file = file_path

    if os.path.isdir(file):
        # ── Directory ────────────────────────────────────────────────────────

        if not OPT_RECURSIVE:
            _debug(f"{file}: is a directory")
            print(f"{COMMAND}: {file}: is a directory")
            return 1

        if file == "./":
            print(f"{COMMAND}: {file}: Invalid argument")
            return 1

        if OPT_INTERACTIVE:
            answer = _ask(f"examine files in directory {file}? ")
            if re.match(r"^[yY]", answer):
                # Interactively process contents first, then ask about the dir
                _recursive_remove(file)

                answer = _ask(f"remove {file}? ")
                if re.match(r"^[yY]", answer):
                    try:
                        remaining = os.listdir(file)
                    except OSError:
                        remaining = []
                    if remaining:
                        print(f"{COMMAND}: {file}: Directory not empty")
                        return 1
                    else:
                        _do_trash(file)
                        _debug("trash returned")
        else:
            _do_trash(file)
            _debug("trash returned")

    else:
        # ── File / symlink ───────────────────────────────────────────────────

        if OPT_INTERACTIVE:
            answer = _ask(f"remove {file}? ")
            if not re.match(r"^[yY]", answer):
                return 0

        _do_trash(file)
        _debug("trash returned")

    return 0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    global EXIT_CODE, SAFE_RM_TRASH

    if len(sys.argv) < 2:
        print("safe-rm")
        _usage()

    option_args, file_names = _parse_argv(sys.argv[1:])

    _parse_options(option_args)

    _debug(f"{len(file_names)} files or directory to process: {file_names}")

    # Ensure the trash directory exists
    if not os.path.exists(SAFE_RM_TRASH):
        print(f'Directory "{SAFE_RM_TRASH}" does not exist, do you want create it?')
        answer = _ask("(yes/no): ")
        if answer == "yes" or answer == "":
            os.makedirs(SAFE_RM_TRASH, exist_ok=True)
        else:
            print("Canceled!")
            sys.exit(1)

    # interactive=once: ask a single confirmation when removing 3+ items or
    # using --recursive (mirrors the -I behaviour)
    if OPT_INTERACTIVE_ONCE and (len(file_names) > 2 or OPT_RECURSIVE):
        answer = _ask(f"{COMMAND}: remove all arguments? ")
        if not re.match(r"^[yY]", answer or ""):
            _debug(f"EXIT_CODE {EXIT_CODE}")
            sys.exit(EXIT_CODE)

    for file in file_names:
        _debug(f"result file {file}")

        if file == "/":
            print("it is dangerous to operate recursively on /")
            print("are you insane?")
            EXIT_CODE = 1
            _debug(f"EXIT_CODE {EXIT_CODE}")
            sys.exit(EXIT_CODE)

        if file in (".", ".."):
            print(f'{COMMAND}: "." and ".." may not be removed')
            EXIT_CODE = 1
            continue

        # Also guard against paths ending in /. or /..
        if os.path.basename(file) in (".", ".."):
            print(f'{COMMAND}: "." and ".." may not be removed')
            EXIT_CODE = 1
            continue

        # Use lexists so broken symlinks are also treated as existing files
        if os.path.lexists(file):
            status = _remove(file)
            _debug(f"remove returned status: {status}")
            if status != 0:
                EXIT_CODE = 1
        else:
            print(f"{COMMAND}: {file}: No such file or directory")
            EXIT_CODE = 1

    _debug(f"EXIT_CODE {EXIT_CODE}")
    sys.exit(EXIT_CODE)


if __name__ == "__main__":
    main()
