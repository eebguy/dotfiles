# dotfiles

One script to set up a machine: installs my packages for whatever OS/distro it's on,
then applies my configs with [chezmoi](https://chezmoi.io). Homebrew on macOS only;
Linux uses the distro's own package manager.

```sh
git clone https://github.com/eebguy/dotfiles.git ~/.local/share/chezmoi
~/.local/share/chezmoi/install.sh
```

| Flag | Does |
|---|---|
| `--dry-run` | show the plan, change nothing |
| `--list` | each package, whether it's installed, and how it would be installed here |
| `--only go,helm` | just these packages |
| `--upgrade` | reinstall upstream-release packages at their latest version |
| `--yes` / `--no-sudo` | use sudo without asking (unattended) / never elevate |
| `--packages-only` / `--dotfiles-only` | half the job |
| `--no-brew` | macOS: skip Homebrew, upstream releases only |

## Supported

macOS (Intel + Apple Silicon) · Debian/Ubuntu (apt) · Fedora/RHEL/Rocky/Amazon (dnf/yum) ·
Arch (pacman) · openSUSE (zypper) · Alpine (apk) · WSL. amd64 and arm64.

## macOS

Homebrew does the installing. If it isn't there yet, the script installs it (that's the
one step that needs sudo; answer no and it falls back to upstream releases), after the
Xcode Command Line Tools. Every package comes from Homebrew where it has one, so
`brew upgrade` keeps the Mac current; HashiCorp tools come from the `hashicorp/tap`,
and the font, Azure CLI and Google Cloud CLI are casks. `.zshenv` puts Homebrew's
`bin` and its zsh completions on the path.

## Sudo

Nothing runs as root without asking. Before installing anything, the script lists exactly
which steps need root (prerequisites, system packages, `/etc/shells`) and asks once, `y/N`.
Answer no — or run it with no terminal attached — and those steps are skipped while
everything that installs into `~/.local` still goes ahead. Passwordless sudo, `doas` and
running as root all work.

## Packages

Listed in [`packages.txt`](packages.txt), one per line — format is documented at the top.
On Linux each one is installed one of two ways (on macOS, Homebrew first — see above):

- **native** — the distro's package manager (`git`, `zsh`, `openssl`, `tmux`, anything you add by name).
- **vendor** — the official upstream release into `~/.local` (no sudo, always current):
  Go, govulncheck, Neovim, eza, chezmoi, starship, fzf, zoxide, ripgrep, fd, tree-sitter,
  Node.js (LTS), GitHub CLI, kubectl, Helm, Terraform, Vault, Nomad, Consul, AWS CLI v2,
  Azure CLI (via `uv`), Google Cloud CLI, Maple Mono NF. On WSL the font is also
  installed for Windows, since Windows Terminal renders with Windows fonts, and
  `win32yank` gives Neovim the Windows clipboard.

tree-sitter's Linux builds need glibc 2.39+; on older distros (Ubuntu 22.04) it is
compiled from source once, with a temporary Rust toolchain that is deleted afterwards.

To add a vendor package, write a `vendor_<name>` function in `install.sh`.
Changing `packages.txt` then `chezmoi apply` installs the new entries automatically.

## Layout

```
install.sh        bootstrap (POSIX sh)
packages.txt      package list
home/             chezmoi source state (.chezmoiroot points here)
```

## Configs

| Tool | Config | Notes |
|---|---|---|
| zsh | `~/.zshenv`, `~/.zshrc`, `~/.config/zsh/aliases.zsh` | antidote plugins, cached starship/zoxide init |
| Tab completion | `~/.config/zsh/completions.zsh`, `~/.config/zsh/functions/` | kubectl, helm, gh, chezmoi, rg, fd, uv, terraform, vault, nomad, consul, aws, az, gcloud; generated files cached in `~/.cache/zsh/completions`, rebuilt when a tool is upgraded |
| starship | `~/.config/starship/starship.toml` | BMW palette |
| tmux | `~/.config/tmux/tmux.conf` | prefix `Ctrl-a`, `Ctrl-h/j/k/l` shared with Neovim |
| Neovim | `~/.config/nvim/` | lazy.nvim; LSP for Go, Terraform, shell, YAML (Kubernetes), Lua, Markdown. `<Space>` shows the keymaps |

On first start Neovim installs its plugins, syntax parsers and language servers by itself
(give it a minute; `:Lazy` and `:Mason` show progress).

Day to day: `chezmoi edit ~/.zshrc`, `chezmoi apply`, `chezmoi cd` → commit → push.
