# Zsh Cheat Sheet

Key bindings, completions, and tools for the zsh shell configuration.

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

## Tips

- Type partial command — **gray autosuggestion** appears — `Right-arrow` to accept
- Invalid commands turn **red** as you type (syntax highlighting)
- `~/.zsh_history` is the history file (100k entries)
