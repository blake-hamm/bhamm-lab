# Terminal Cheat Sheet

Key bindings, completions, and tools for terminal usage across zsh and tmux.

## I Want To...

| Goal | Section |
|------|---------|
| Edit command line efficiently | Key Bindings |
| Find old commands or files | fzf |
| Reuse recent commands | History |
| Auto-load project environment variables | direnv |
| Keep terminal sessions alive across disconnects | tmux |
| Navigate around a file in neovim | Movement |
| Edit text in neovim | Editing |
| Open/switch files in neovim | Navigation & File Management |
| Look up code definitions or docs | Code Navigation (LSP) |
| Copy text between nvim and system clipboard | System Clipboard |

## Key Bindings

These bindings work in zsh (the shell) to move and edit the current command line.

| Key | Action |
|-----|--------|
| `Ctrl+a` | Beginning of line |
| `Ctrl+e` | End of line |
| `Alt+b` | Back one word |
| `Alt+f` | Forward one word |
| `Ctrl+w` | Delete word backward |
| `Alt+d` | Delete word forward |
| `Ctrl+u` | Delete to beginning of line |
| `Ctrl+k` | Delete to end of line |
| `Ctrl+r` | **fzf history search** |
| `Ctrl+t` | **fzf file search** (inserts path) |
| `Alt+c` | **fzf directory jump** |
| `Tab` | Completion menu (arrow keys to navigate) |
| `Shift+Tab` | Reverse completion |
| `Ctrl+l` | Clear screen |

## Completion

zsh suggests commands, flags, and filenames as you type. Press `Tab` to accept suggestions.

- `git <Tab>` — menu of all git subcommands
- `git che<Tab>` — fuzzy match: `checkout`, `cherry-pick`
- `kill <Tab>` — scrollable process list
- `ls -<Tab>` — all flags with descriptions
- Case-insensitive: `doc<Tab>` matches `Documents`

## History

zsh remembers every command you run. Access recent commands without retyping.

- `!!` — rerun last command (`histverify` lets you edit first)
- `!foo` — rerun last command starting with `foo`
- `Ctrl+r` — fuzzy search all history
- History shared across all terminals instantly

## fzf

fzf is a fuzzy finder. Use it to search through history, files, and directories interactively.

| Use | How |
|-----|-----|
| Rerun old command | `Ctrl+r`, type to filter, Enter |
| Insert file path | `vim <Ctrl+t>`, type to filter, Enter |
| Jump to subdirectory | `Alt+c`, type to filter, Enter |
| Pipe anything | `git branch \| fzf`, `ps aux \| fzf` |

## direnv

direnv automatically loads environment variables when you enter a project directory. Useful for per-project config like API keys or tool paths.

- `cd` into dir with `.envrc` — auto loads env vars
- `direnv allow` — approve new `.envrc`
- `direnv deny` — block `.envrc`
- `direnv status` — show loaded envs

## Bash-Compat Fixes

zsh behaves differently from bash in a few edge cases. These fixes prevent common errors.

- `scp host:*` — works (no `no matches found` error)
- `echo hello # comment` — inline comments work

## tmux

tmux is a terminal multiplexer. Use it to keep sessions running after disconnecting, or split one terminal into multiple panes.

Prefix key is `Ctrl+Space` (instead of default `Ctrl+b`).

### Sessions

| Command | Action |
|---------|--------|
| `tmux new -s foo` | New session named `foo` |
| `tmux attach -t foo` | Attach to session `foo` |
| `tmux ls` | List sessions |
| `Prefix + d` | Detach from session |
| `Prefix + s` | Interactive session switcher |
| `Prefix + $` | Rename session |

### Windows (tabs)

| Key | Action |
|-----|--------|
| `Prefix + c` | New window |
| `Prefix + n` | Next window |
| `Prefix + p` | Previous window |
| `Prefix + <number>` | Jump to window |
| `Prefix + ,` | Rename window |
| `Prefix + &` | Kill window |

### Panes (splits)

| Key | Action |
|-----|--------|
| `Prefix + %` | Split vertically |
| `Prefix + "` | Split horizontally |
| `Prefix + o` | Cycle panes |
| `Prefix + q` | Show pane numbers |
| `Prefix + x` | Kill pane |
| `Prefix + z` | Zoom pane (toggle) |

### Scroll / Copy

| Key | Action |
|-----|--------|
| `Prefix + [` | Copy mode (scroll with arrows/PgUp/PgDn) |
| `q` | Exit copy mode |

### Ghostty Integration

Ghostty is configured to auto-attach to a tmux session named `main` on launch. Every new Ghostty window joins the same session. Detach with `Prefix + d` to keep it running in the background.

## Neovim Basics

Neovim is a modal text editor. You switch between modes instead of using arrow keys and menus.

Leader key is `<Space>`. Press it in normal mode, then another key for a command.

### Modes

You must be in the right mode before running commands. Normal mode is for navigation and commands; Insert mode is for typing text.

| Mode | Enter | Exit |
|------|-------|------|
| Normal | `Esc` or `Ctrl+[` | — (default) |
| Insert | `i` (before cursor), `a` (after), `o` (new line) | `Esc` |
| Visual | `v` (char), `V` (line), `Ctrl+v` (block) | `Esc` |

### Movement (normal mode)

Use these in Normal mode to jump around a file without moving your hands from the home row.

| Key | Action |
|-----|--------|
| `h` `j` `k` `l` | left, down, up, right |
| `w` / `b` | next / previous word |
| `0` / `$` | start / end of line |
| `gg` / `G` | first / last line of file |
| `Ctrl+d` / `Ctrl+u` | half-page down / up |
| `{` / `}` | previous / next paragraph |
| `H` / `M` / `L` | top / middle / bottom of screen |

### Editing

These commands modify text. Most work in Normal mode; some require Visual mode.

| Key | Action |
|-----|--------|
| `x` | delete character under cursor |
| `dd` | delete line |
| `yy` | yank (copy) line |
| `p` | paste after cursor |
| `u` | undo |
| `Ctrl+r` | redo |
| `r` | replace single character |
| `c` | change (e.g., `cw` = change word) |
| `>` / `<` | indent / unindent (visual mode) |

### Files and Buffers

Buffers are open files. These commands manage what you're editing.

| Command | Action |
|---------|--------|
| `:e path` | open file |
| `:w` | save |
| `:q` | quit |
| `:q!` | quit without saving |
| `:wq` | save and quit |
| `:bn` / `:bp` | next / previous buffer |
| `:bd` | close buffer |
| `:sp file` | horizontal split |
| `:vsp file` | vertical split |

### Searching

Search within the current file.

| Key | Action |
|-----|--------|
| `/text` | search forward |
| `?text` | search backward |
| `n` / `N` | next / previous match |
| `*` | search word under cursor |

### Windows

Splits let you view multiple files or parts of a file at once.

| Key | Action |
|-----|--------|
| `Ctrl+w` `h/j/k/l` | move to window |
| `Ctrl+w` `c` | close window |
| `Ctrl+w` `o` | only this window (close others) |
| `Ctrl+w` `=` | equalize window sizes |

### System Clipboard

By default, nvim uses its own clipboard. Use these to copy/paste with the OS.

| Command | Action |
|---------|--------|
| `"+y` | yank to system clipboard |
| `"+p` | paste from system clipboard |

In visual mode: `"+y` copies selection to system clipboard.

### Navigation & File Management

These commands replicate VSCode's sidebar, quick-open, and global search.

| Key | Action |
|-----|--------|
| `<Space>e` | toggle file tree (neo-tree) |
| `<Space>ff` | find files (telescope) — like `Ctrl+P` |
| `<Space>fg` | live grep (telescope) — like `Ctrl+Shift+F` |
| `<Space>fb` | list open buffers (telescope) |

**Neo-tree** (file explorer):
- Open with `<Space>e`, navigate with `j`/`k`
- `Enter` — open file in current window
- `s` — open file in **vertical split** (tree stays left)
- `S` — open file in horizontal split
- `a` — add file/directory
- `d` — delete
- `r` — rename
- `m` — move
- `q` — close tree

**Switching focus between tree and editor:**
- `Ctrl+w h` — move focus to the left window (neo-tree)
- `Ctrl+w l` — move focus to the right window (editor)
- `<Space>e` toggles the tree and puts focus inside it automatically


**Telescope** (fuzzy finder):
- `<Space>ff` then type — fuzzy match filenames
- `<Space>fg` then type — search text across all files
- `Ctrl+n` / `Ctrl+p` — move between results
- `Ctrl+v` — open result in vertical split
- `Ctrl+x` — open result in horizontal split
- `Esc` — close telescope

**The VSCode layout**: Open a directory with `nvim .`, then `<Space>e`. The tree appears on the left. Press `s` on any file to open it on the right while the tree stays visible.

### Code Navigation (LSP)

These commands require a language server (LSP) for the file type. Use them when editing code to jump to definitions, see docs, or refactor.

| Key | Action |
|-----|--------|
| `<Space>` | leader (wait for next key) |
| `<Space>th` | toggle terminal |
| `gd` | go to definition |
| `gr` | go to references |
| `K` | hover documentation |
| `<Space>ca` | code action |
| `<Space>rn` | rename symbol |

## Tips

- Type partial command — **gray autosuggestion** appears — `Right-arrow` to accept
- Invalid commands turn **red** as you type (syntax highlighting)
- `~/.zsh_history` is the history file (100k entries)
