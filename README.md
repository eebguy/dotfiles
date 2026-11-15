# dotfiles

One script to set up a machine: installs my packages for whatever OS/distro it's on,
then applies my configs with [chezmoi](https://chezmoi.io). No Homebrew.

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

## Supported

macOS (Intel + Apple Silicon) · Debian/Ubuntu (apt) · Fedora/RHEL/Rocky/Amazon (dnf/yum) ·
Arch (pacman) · openSUSE (zypper) · Alpine (apk) · WSL. amd64 and arm64.

## Sudo

Nothing runs as root without asking. Before installing anything, the script lists exactly
which steps need root (prerequisites, system packages, `/etc/shells`) and asks once, `y/N`.
Answer no — or run it with no terminal attached — and those steps are skipped while
everything that installs into `~/.local` still goes ahead. Passwordless sudo, `doas` and
running as root all work.

## Packages

Listed in [`packages.txt`](packages.txt), one per line — format is documented at the top.
Each one is installed one of two ways:

- **native** — the distro's package manager (`git`, `zsh`, `openssl`, anything you add by name).
- **vendor** — the official upstream release into `~/.local` (no sudo, always current):
  Go, Neovim, eza, chezmoi, starship, GitHub CLI, kubectl, Helm, Terraform, Vault,
  Nomad, Consul, AWS CLI v2,
  Azure CLI (via `uv`), Google Cloud CLI, Maple Mono NF. On WSL the font is also
  installed for Windows, since Windows Terminal renders with Windows fonts.

To add a vendor package, write a `vendor_<name>` function in `install.sh`.
Changing `packages.txt` then `chezmoi apply` installs the new entries automatically.

## Layout

```
install.sh        bootstrap (POSIX sh)
packages.txt      package list
home/             chezmoi source state (.chezmoiroot points here)
```

Day to day: `chezmoi edit ~/.zshrc`, `chezmoi apply`, `chezmoi cd` → commit → push.
