# shellnote

Markdown notes in `~/.notes`, edited with your existing Neovim configuration.

## Setup

Requires Bash 3.2 or newer, Neovim, ripgrep, and fzf on macOS or Linux.
Git is optional for versioning and pushing notes.

Run `./bin/shellnote` from this repository or add its `bin` directory to your PATH.
For this checkout, add the following to your shell configuration if desired:

```sh
export PATH="$HOME/.local/shellnote/bin:$PATH"
```

Your existing Neovim configuration, including lazy.nvim, loads normally.
No editor plugin is required.

## Create a note

```sh
shellnote new case 04512 nginx 502s
```

Arguments need no quotes.
Put `--` before text that starts with a hyphen, as in `shellnote find -- --force`.
Storage is created on first use.
Titles become Markdown headings, and files receive unique timestamped names.

## Capture command output

```sh
journalctl -u nginx --since -1h | shellnote new case 04512 nginx logs
```

```sh
nginx -t 2>&1 | shellnote add 04512
```

`new` with piped input creates the note without opening the editor.
`add` appends piped input to the note matching every word, or to the most recently modified note when no words are given.
Output lands in a fenced code block, and empty input changes nothing.
Input redirected from a file counts as piped.

## Find and edit

| Command | Action |
| --- | --- |
| `shellnote` | Browse notes by title with previews and open a selection. |
| `shellnote edit 04512 nginx` | Edit the note whose title or path contains every word. |
| `shellnote last` | Edit the most recently modified note at its last line. |
| `shellnote show 04512` | Print the matching note without opening an editor. |
| `shellnote list` | Print note titles and paths. |
| `shellnote list --tag work` | Print notes with the exact tag `#work`. |
| `shellnote find connection refused` | Search literal text and jump to the selected line. |
| `shellnote find -p connection refused` | Print matching note paths, lines, and text. |
| `shellnote tags` | Pick a tag, then a matching note. |
| `shellnote tags work` | Find the exact tag `#work`. |
| `shellnote help` | Show command help. `shellnote COMMAND -h` shows one command's usage. |

`edit` and `show` match words against titles and paths, ignoring case.
One match opens directly, and several matches open the picker.
The browser, `list`, and match pickers show recently modified notes first.
`find` ignores case unless the text contains a capital letter.

`find --print` groups terminal matches under Markdown headings and shows short excerpts. When piped, it prints `path:line:text` records.

Use Enter to select and Escape to cancel.
Add inline tags such as `#work` or `#project-alpha` to Markdown notes.
Tags are case-sensitive and start at a line boundary or after whitespace.
They contain ASCII letters, digits, underscores, and hyphens, starting with a letter or digit.
`#work` does not match `#workshop` or `#Work`.
Markdown headings are not tags, but tags inside code fences count.

## Appearance and configuration

The CLI and picker use your terminal palette and default background.
The editor uses your Neovim colorscheme.
Set `NO_COLOR=1` for plain output or `NOTE_EMOJI=1` for optional decorations.
Unicode and emoji in note text depend on terminal font support.
Set `NOTES_DIR` to use another private directory.
Ripgrep and fzf global option files are bypassed to keep search scope and picker behavior predictable.

## Git

The notes repository is separate from the shellnote program repository.
Initialize it explicitly:

```sh
shellnote init --git
```

Commit Markdown additions, edits, and deletions:

```sh
shellnote commit weekly notes
```

Shellnote also includes its own generated `.gitignore`.
It refuses to commit if unrelated files are already staged.
It preserves an existing `.gitignore` and leaves that file under your manual Git control.

Configure your remote and the branch's upstream using ordinary Git commands in `~/.notes` (or `NOTES_DIR`).
Then push explicitly:

```sh
shellnote push
```

There are no automatic commits, pushes, pulls, or remote changes.
Pushed notes and history are readable by everyone with access to that repository.

## Privacy

The notes directory has mode `0700` and notes have mode `0600`.
Existing storage or notes with unsafe permissions are rejected without silently changing them.
The editor invocation disables swap, backups, persistent undo, and ShaDa persistence.
Personal Neovim plugins can still copy or transmit contents and are outside shellnote's control.
Notes and their Git history are unencrypted.
Permissions do not protect against your account, administrators, offline disk access, or people who can read a pushed repository.

## Checks

```sh
bash tests/shellnote.sh
```

Tests use temporary storage and never open your personal notes or Neovim configuration.
