# Terminal Cheat Sheet

Key bindings, completions, and tools for terminal usage across zsh and tmux.

## Key Bindings

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

- `git <Tab>` — menu of all git subcommands
- `git che<Tab>` — fuzzy match: `checkout`, `cherry-pick`
- `kill <Tab>` — scrollable process list
- `ls -<Tab>` — all flags with descriptions
- Case-insensitive: `doc<Tab>` matches `Documents`

## History

- `!!` — rerun last command (`histverify` lets you edit first)
- `!foo` — rerun last command starting with `foo`
- `Ctrl+r` — fuzzy search all history
- History shared across all terminals instantly

## fzf

| Use | How |
|-----|-----|
| Rerun old command | `Ctrl+r`, type to filter, Enter |
| Insert file path | `vim <Ctrl+t>`, type to filter, Enter |
| Jump to subdirectory | `Alt+c`, type to filter, Enter |
| Pipe anything | `git branch \| fzf`, `ps aux \| fzf` |

## direnv

- `cd` into dir with `.envrc` — auto loads env vars
- `direnv allow` — approve new `.envrc`
- `direnv deny` — block `.envrc`
- `direnv status` — show loaded envs

## Bash-Compat Fixes

- `scp host:*` — works (no `no matches found` error)
- `echo hello # comment` — inline comments work

## tmux

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

Leader key is `<Space>`. Press it in normal mode, then another key for a command.

### Modes

| Mode | Enter | Exit |
|------|-------|------|
| Normal | `Esc` or `Ctrl+[` | — (default) |
| Insert | `i` (before cursor), `a` (after), `o` (new line) | `Esc` |
| Visual | `v` (char), `V` (line), `Ctrl+v` (block) | `Esc` |

### Movement (normal mode)

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

| Key | Action |
|-----|--------|
| `/text` | search forward |
| `?text` | search backward |
| `n` / `N` | next / previous match |
| `*` | search word under cursor |

### Windows

| Key | Action |
|-----|--------|
| `Ctrl+w` `h/j/k/l` | move to window |
| `Ctrl+w` `c` | close window |
| `Ctrl+w` `o` | only this window (close others) |
| `Ctrl+w` `=` | equalize window sizes |

### System Clipboard

| Command | Action |
|---------|--------|
| `"+y` | yank to system clipboard |
| `"+p` | paste from system clipboard |

In visual mode: `"+y` copies selection to system clipboard.

### Essential Starter Commands

| Key | Action |
|-----|--------|
| `<Space>` | leader (wait for next key) |
| `<Space>e` | toggle file tree (neo-tree) |
| `<Space>ff` | find files (telescope) |
| `<Space>fg` | live grep (telescope) |
| `<Space>fb` | list buffers (telescope) |
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
