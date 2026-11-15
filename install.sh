#!/bin/sh
# install.sh — bootstrap a machine: install packages from packages.txt, then
# apply dotfiles with chezmoi.
#
# POSIX sh on purpose: runs on macOS (bash 3.2 / zsh), Debian/Ubuntu (dash),
# Fedora/RHEL, Arch, openSUSE and Alpine (busybox) without installing anything first.
#
#   ./install.sh                 packages + dotfiles
#   ./install.sh --dry-run       show what would happen
#   ./install.sh --only go,helm  just these packages (implies --packages-only)
#   ./install.sh --upgrade       reinstall vendor packages at their latest release
#   ./install.sh --yes           don't ask before using sudo (CI / unattended)
#   ./install.sh --help
#
# Run straight from GitHub (clones the repo first):
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/eebguy/dotfiles/main/install.sh)"

set -u

DOTFILES_REPO=${DOTFILES_REPO:-https://github.com/eebguy/dotfiles.git}
PREFIX=${PREFIX:-$HOME/.local}          # vendor installs go here — no sudo needed
BIN=$PREFIX/bin
OPT=$PREFIX/opt
LOG_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/logs

DRY_RUN=0 UPGRADE=0 ONLY="" DO_PKGS=1 DO_DOTFILES=1 DO_CHSH=1 LIST=0
AUTO_YES=${DOTFILES_YES:-0} NO_SUDO=0

# ================================================================= output ====
# Colour only on a real terminal, and never when NO_COLOR is set (no-color.org).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  ESC=$(printf '\033')
  RST="$ESC[0m" BOLD="$ESC[1m" DIM="$ESC[2m"
  RED="$ESC[31m" GRN="$ESC[32m" YLW="$ESC[33m" BLU="$ESC[34m" MAG="$ESC[35m" CYN="$ESC[36m"
  FANCY=1
else
  RST="" BOLD="" DIM="" RED="" GRN="" YLW="" BLU="" MAG="" CYN="" FANCY=0
fi

# Unicode symbols on UTF-8 locales, plain ASCII otherwise.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UTF=1 ;;
  *) UTF=0 ;;
esac
if [ "$UTF" = 1 ]; then
  I_OK='✔' I_FAIL='✖' I_WARN='▲' I_SKIP='○' I_DOT='·' I_RUN='➜' I_ASK='?'
  I_PLATFORM='◎' I_PRIV='⬆' I_PREREQ='⚙' I_PKG='⬢' I_DOTS='✎' I_SHELL='❯' I_DONE='✦'
  H='─' TL='╭' TR='╮' BL='╰' BR='╯' V='│'
else
  I_OK='+' I_FAIL='x' I_WARN='!' I_SKIP='-' I_DOT='*' I_RUN='>' I_ASK='?'
  I_PLATFORM='#' I_PRIV='^' I_PREREQ='#' I_PKG='#' I_DOTS='#' I_SHELL='$' I_DONE='*'
  H='-' TL='+' TR='+' BL='+' BR='+' V='|'
fi

WIDTH=60
repeat() { r="" n=$2; while [ "$n" -gt 0 ]; do r="$r$1"; n=$((n - 1)); done; printf '%s' "$r"; }
RULE=$(repeat "$H" $WIDTH)

ok()   { printf '  %s%s%s %s\n' "$GRN" "$I_OK" "$RST" "$*"; }
fail() { printf '  %s%s%s %s\n' "$RED" "$I_FAIL" "$RST" "$*"; }
warn() { printf '  %s%s%s %s\n' "$YLW" "$I_WARN" "$RST" "$*"; }
skip() { printf '  %s%s %s%s\n' "$DIM" "$I_SKIP" "$*" "$RST"; }
step() { printf '  %s%s%s %s\n' "$CYN" "$I_RUN" "$RST" "$*"; }
note() { printf '      %s%s%s\n' "$DIM" "$*" "$RST"; }
kv()   { printf '  %s%s%s %-14s %s\n' "$BLU" "$I_DOT" "$RST" "$1" "$2"; }
die()  { printf '\n  %s%s error:%s %s\n\n' "$RED$BOLD" "$I_FAIL" "$RST" "$*" >&2; exit 1; }

STAGE_N=0 STAGE_TOTAL=0
stage() {   # icon colour title
  STAGE_N=$((STAGE_N + 1))
  printf '\n%s%s%s  %s%s%s  %s%d/%d%s\n' "$BOLD$2" "$1" "$RST" "$BOLD" "$3" "$RST" "$DIM" "$STAGE_N" "$STAGE_TOTAL" "$RST"
  printf '%s%s%s\n' "$DIM" "$RULE" "$RST"
}

banner() {   # ASCII content only, so printf padding lines up
  inner=$((WIDTH - 2))
  printf '\n%s%s%s%s%s\n' "$MAG" "$TL" "$(repeat "$H" $inner)" "$TR" "$RST"
  b_fmt="%s%s%s %s%-$((inner - 1))s%s%s%s%s\n"
  # shellcheck disable=SC2059
  printf "$b_fmt" "$MAG" "$V" "$RST" "$BOLD" "dotfiles bootstrap" "$RST" "$MAG" "$V" "$RST"
  # shellcheck disable=SC2059
  printf "$b_fmt" "$MAG" "$V" "$RST" "$DIM" "packages + configs via chezmoi" "$RST" "$MAG" "$V" "$RST"
  printf '%s%s%s%s%s\n' "$MAG" "$BL" "$(repeat "$H" $inner)" "$BR" "$RST"
}

now() { date +%s; }
dur() {   # seconds -> "4s" / "2m 05s"
  if [ "$1" -lt 60 ]; then printf '%ds' "$1"; else printf '%dm %02ds' $(($1 / 60)) $(($1 % 60)); fi
}

# Run a command in the background with a spinner; output goes to a log file.
# Falls back to running in the foreground when there's no terminal, or when
# doas may need to prompt for a password (the spinner would hide the prompt).
TASK_PID=""
task() {   # logfile label command...
  t_log=$1 t_label=$2; shift 2
  if [ "$FANCY" = 0 ] || [ "${NO_SPIN:-0}" = 1 ]; then
    [ "$FANCY" = 0 ] && printf '  %s %s\n' "$I_RUN" "$t_label"
    ( set -e; "$@" ) >"$t_log" 2>&1 </dev/null
    return
  fi
  ( set -e; "$@" ) >"$t_log" 2>&1 </dev/null &
  TASK_PID=$!
  t_i=0
  printf '%s[?25l' "$ESC"
  while kill -0 "$TASK_PID" 2>/dev/null; do
    if [ "$UTF" = 1 ]; then
      case $((t_i % 10)) in
        0) f='⠋' ;; 1) f='⠙' ;; 2) f='⠹' ;; 3) f='⠸' ;; 4) f='⠼' ;;
        5) f='⠴' ;; 6) f='⠦' ;; 7) f='⠧' ;; 8) f='⠇' ;; *) f='⠏' ;;
      esac
    else
      case $((t_i % 4)) in 0) f='|' ;; 1) f='/' ;; 2) f='-' ;; *) f='\' ;; esac
    fi
    printf '\r  %s%s%s %s %s(%s)%s' "$CYN" "$f" "$RST" "$t_label" "$DIM" "$(dur $((t_i / 10)))" "$RST"
    t_i=$((t_i + 1))
    sleep 0.1 2>/dev/null || sleep 1
  done
  printf '\r%s[K%s[?25h' "$ESC" "$ESC"
  wait "$TASK_PID"; t_rc=$?
  TASK_PID=""
  return $t_rc
}

show_log() {   # logfile — last lines of a failed step, indented
  [ -s "$1" ] || return 0
  tail -n 12 "$1" | while IFS= read -r l; do note "$l"; done
}

usage() {
  sed -n '2,/^$/s/^# \{0,1\}//p' "$0" 2>/dev/null
  cat <<'EOF'
Options:
  -n, --dry-run        print the plan, change nothing
  -u, --upgrade        reinstall vendor packages even if already present
  -o, --only LIST      comma-separated package names from packages.txt
  -l, --list           list packages and how each would be installed here
  -y, --yes            use sudo without asking (unattended runs)
      --no-sudo        never elevate; skip anything that needs root
      --packages-only  skip chezmoi apply
      --dotfiles-only  skip package installs
      --no-chsh        don't change the login shell to zsh
  -h, --help

Environment: PREFIX (default ~/.local), DOTFILES_REPO, PKG_FILE,
             DOTFILES_YES=1 (same as --yes), NO_COLOR=1 (plain output)
EOF
}

# ============================================================= repo setup ====
# Works both from a clone and piped from curl (then clone into chezmoi's default dir).
case $0 in
  */*) REPO_DIR=$(cd "$(dirname "$0")" && pwd -P) ;;
  *)   REPO_DIR="" ;;
esac
if [ -z "$REPO_DIR" ] || [ ! -f "$REPO_DIR/packages.txt" ]; then
  REPO_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi
  if [ ! -f "$REPO_DIR/packages.txt" ]; then
    command -v git >/dev/null 2>&1 || die "git is required to clone $DOTFILES_REPO"
    step "Cloning $DOTFILES_REPO"
    git clone --quiet "$DOTFILES_REPO" "$REPO_DIR" || die "clone failed"
  fi
  exec sh "$REPO_DIR/install.sh" "$@"
fi

while [ $# -gt 0 ]; do
  case $1 in
    -n|--dry-run)    DRY_RUN=1 ;;
    -u|--upgrade)    UPGRADE=1 ;;
    -o|--only)       [ $# -ge 2 ] || die "--only needs a value"; ONLY=$2; DO_DOTFILES=0; shift ;;
    --only=*)        ONLY=${1#*=}; DO_DOTFILES=0 ;;
    -l|--list)       LIST=1 ;;
    -y|--yes)        AUTO_YES=1 ;;
    --no-sudo)       NO_SUDO=1 ;;
    --packages-only) DO_DOTFILES=0 ;;
    --dotfiles-only) DO_PKGS=0 ;;
    --no-chsh)       DO_CHSH=0 ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

PKG_FILE=${PKG_FILE:-$REPO_DIR/packages.txt}
[ -f "$PKG_FILE" ] || die "missing $PKG_FILE"

# Scratch space lives on disk, not in /tmp: /tmp is often a small RAM disk (Raspberry Pi
# OS, Fedora, Arch), and unpacked Go / gcloud / AWS CLI / HashiCorp downloads easily pass
# 1-2 GB. Set TMPDIR to put it somewhere else. Each package gets its own download folder
# ($TMP), deleted as soon as that package is done; $WORK holds logs and run state.
WORK_BASE=${TMPDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles}
mkdir -p "$WORK_BASE" 2>/dev/null || die "can't create $WORK_BASE"
WORK=$(mktemp -d "$WORK_BASE/run.XXXXXX") || die "mktemp failed in $WORK_BASE"
TMP=$WORK
MAIN_PID=$$ KEEPALIVE_PID="" START=$(now)
cleanup() {
  [ -n "$TASK_PID" ] && kill "$TASK_PID" 2>/dev/null
  [ -n "$KEEPALIVE_PID" ] && kill "$KEEPALIVE_PID" 2>/dev/null
  [ "$FANCY" = 1 ] && printf '%s[?25h' "$ESC"     # make sure the cursor comes back
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'printf "\n\n  %s%s Interrupted%s\n\n" "$RED$BOLD" "$I_FAIL" "$RST"; exit 130' INT TERM

# =============================================================== platform ====
case $(uname -s) in
  Linux)  OS=linux ;;
  Darwin) OS=darwin ;;
  *)      die "unsupported OS: $(uname -s)" ;;
esac
case $(uname -m) in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *)             die "unsupported CPU: $(uname -m)" ;;
esac

DISTRO="" DISTRO_LIKE="" DISTRO_NAME="" WSL=0 MUSL=0
if [ "$OS" = linux ]; then
  if [ -r /etc/os-release ]; then
    DISTRO=$(. /etc/os-release && echo "${ID:-}")
    DISTRO_LIKE=$(. /etc/os-release && echo "${ID_LIKE:-}")
    DISTRO_NAME=$(. /etc/os-release && echo "${PRETTY_NAME:-$ID}")
  fi
  grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && WSL=1
  if ls /lib/ld-musl-* >/dev/null 2>&1; then MUSL=1; fi
else
  DISTRO=macos DISTRO_NAME="macOS $(sw_vers -productVersion 2>/dev/null)"
fi

detect_pm() {
  if [ "$OS" = darwin ]; then
    # No Homebrew. MacPorts is used only if you've installed it yourself.
    if command -v port >/dev/null 2>&1; then echo port; else echo none; fi
    return
  fi
  for id in $DISTRO $DISTRO_LIKE; do
    case $id in
      debian|ubuntu|linuxmint|pop|elementary|raspbian|kali|neon|zorin) echo apt; return ;;
      fedora|rhel|centos|rocky|almalinux|ol|amzn|nobara)
        if command -v dnf >/dev/null 2>&1; then echo dnf; else echo yum; fi; return ;;
      arch|manjaro|endeavouros|garuda|artix|cachyos) echo pacman; return ;;
      opensuse*|suse|sles|sled) echo zypper; return ;;
      alpine|postmarketos) echo apk; return ;;
    esac
  done
  for pm in apt-get dnf yum pacman zypper apk; do
    if command -v $pm >/dev/null 2>&1; then
      case $pm in apt-get) echo apt ;; *) echo $pm ;; esac; return
    fi
  done
  echo none
}
PM=$(detect_pm)

# ============================================================= privileges ====
# PRIV: granted | denied | unknown. Nothing runs as root until the user says yes.
SUDO="" SUDO_BIN="" PRIV=unknown NO_SPIN=0
if [ "$(id -u)" -eq 0 ]; then
  PRIV=granted
elif command -v sudo >/dev/null 2>&1; then
  SUDO_BIN=sudo
elif command -v doas >/dev/null 2>&1; then
  SUDO_BIN=doas
fi

have_tty() { { true </dev/tty; } 2>/dev/null; }   # not `:` — a failed redirect on a special builtin exits sh

# ask_yn "question" [y|n default] — reads /dev/tty so it works under `curl | sh`
ask_yn() {
  q_def=${2:-n}
  if [ "$q_def" = y ]; then q_hint='[Y/n]'; else q_hint='[y/N]'; fi
  if [ "$AUTO_YES" = 1 ]; then
    printf '  %s%s%s %s %s%s yes (--yes)%s\n' "$MAG" "$I_ASK" "$RST" "$1" "$DIM" "$q_hint" "$RST"
    return 0
  fi
  if ! have_tty; then
    printf '  %s%s%s %s %s%s no terminal, answering no%s\n' "$MAG" "$I_ASK" "$RST" "$1" "$DIM" "$q_hint" "$RST"
    return 1
  fi
  printf '  %s%s%s %s%s%s %s%s%s ' "$MAG$BOLD" "$I_ASK" "$RST" "$BOLD" "$1" "$RST" "$DIM" "$q_hint" "$RST" >/dev/tty
  read -r q_ans </dev/tty || q_ans=""
  case ${q_ans:-$q_def} in [Yy]|[Yy][Ee][Ss]) return 0 ;; *) return 1 ;; esac
}

# elevate "reason" ["reason" ...] — ask once per run; later calls reuse the answer.
elevate() {
  case $PRIV in granted) return 0 ;; denied) return 1 ;; esac
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s%s%s Would ask for %s to:\n' "$YLW" "$I_PRIV" "$RST" "${SUDO_BIN:-root}"
    for r in "$@"; do note "$I_DOT $r"; done
    return 1
  fi
  if [ "$NO_SUDO" = 1 ]; then
    PRIV=denied; warn "--no-sudo: skipping steps that need root"; return 1
  fi
  if [ -z "$SUDO_BIN" ]; then
    PRIV=denied; warn "Not root and neither sudo nor doas is installed — skipping steps that need root"
    return 1
  fi
  printf '  %s%s Elevated privileges (%s) are needed to:%s\n' "$YLW$BOLD" "$I_PRIV" "$SUDO_BIN" "$RST"
  for r in "$@"; do printf '      %s%s%s %s\n' "$YLW" "$I_DOT" "$RST" "$r"; done
  if ! ask_yn "Allow $SUDO_BIN for these steps?" n; then
    PRIV=denied
    warn "Continuing without root — those steps will be skipped"
    return 1
  fi
  if [ "$SUDO_BIN" = sudo ]; then
    # Authenticate once up front, then keep the timestamp fresh so background
    # steps (run with `sudo -n`) never block on a hidden password prompt.
    if sudo -n true 2>/dev/null; then
      :                                   # passwordless sudo (or a still-valid timestamp)
    elif ! have_tty; then
      PRIV=denied; fail "sudo needs a password and there's no terminal — skipping steps that need root"; return 1
    elif ! sudo -v </dev/tty; then
      PRIV=denied; fail "sudo authentication failed — skipping steps that need root"; return 1
    fi
    ( while kill -0 "$MAIN_PID" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 30; done ) >/dev/null 2>&1 &
    KEEPALIVE_PID=$!
    SUDO="sudo -n"
  else
    # doas can't refresh credentials, so its steps run in the foreground where it can prompt.
    doas true || { PRIV=denied; fail "doas authentication failed — skipping steps that need root"; return 1; }
    SUDO=doas NO_SPIN=1
  fi
  PRIV=granted
  ok "Privileges granted for this run"
}

as_root() { [ "$PRIV" = granted ] && $SUDO "$@"; }

# ======================================================== package manager ====
pm_refresh() {
  [ -f "$WORK/.pm-refreshed" ] && return 0
  : >"$WORK/.pm-refreshed"
  case $PM in
    apt)    as_root apt-get update -qq ;;
    pacman) as_root pacman -Syu --noconfirm ;;   # Arch: never sync without upgrading
    zypper) as_root zypper --non-interactive --quiet refresh ;;
    apk)    as_root apk update -q ;;
    *)      : ;;
  esac
}

# pm_has <pkg> — does the package manager offer this package?
# Refreshes the index (once, if we have root) before giving up, e.g. on a fresh container.
pm_has() {
  pm_search "$1" && return 0
  [ ! -f "$WORK/.pm-refreshed" ] && [ "$PRIV" = granted ] && [ "$DRY_RUN" = 0 ] || return 1
  pm_refresh >/dev/null 2>&1 && pm_search "$1"
}
pm_search() {
  case $PM in
    apt)     apt-cache show "$1" >/dev/null 2>&1 ;;
    dnf|yum) $PM info -q "$1" >/dev/null 2>&1 ;;
    pacman)  pacman -Si "$1" >/dev/null 2>&1 ;;
    zypper)  zypper --non-interactive --quiet search --match-exact "$1" >/dev/null 2>&1 ;;
    apk)     [ -n "$(apk search -e "$1" 2>/dev/null)" ] ;;
    port)    port -q info "$1" >/dev/null 2>&1 ;;
    *)       return 1 ;;
  esac
}

pm_install() {
  case $PM in
    apt)     as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" ;;
    dnf|yum) as_root $PM install -y -q "$@" ;;
    pacman)  as_root pacman -S --needed --noconfirm "$@" ;;
    zypper)  as_root zypper --non-interactive --quiet install --no-recommends "$@" ;;
    apk)     as_root apk add -q "$@" ;;
    port)    as_root port -N install "$@" ;;
    *)       return 1 ;;
  esac
}

pm_label() {
  case $PM in
    pacman) echo "pacman (syncs and upgrades the system first: pacman -Syu)" ;;
    port)   echo "MacPorts" ;;
    *)      echo "$PM" ;;
  esac
}

# =============================================================== download ====
fetch() { curl -fsSL --retry 3 --proto '=https' --tlsv1.2 -o "$2" "$1"; }
fetch_text() { curl -fsSL --retry 3 --proto '=https' --tlsv1.2 "$1"; }

gh_asset() { echo "https://github.com/$1/releases/latest/download/$2"; }

hashicorp_install() {  # terraform | vault | packer | ...
  v=$(fetch_text "https://checkpoint-api.hashicorp.com/v1/check/$1" |
      sed -n 's/.*"current_version":"\([^"]*\)".*/\1/p')
  [ -n "$v" ]
  fetch "https://releases.hashicorp.com/$1/$v/${1}_${v}_${OS}_${ARCH}.zip" "$TMP/$1.zip"
  unzip -oq "$TMP/$1.zip" "$1" -d "$TMP/$1"
  install -m 755 "$TMP/$1/$1" "$BIN/$1"
}

# Vendor installers -----------------------------------------------------------
# vendor_<name> (dashes -> underscores) installs the official upstream release
# into $PREFIX. Runs in a subshell with `set -e`, so any failing step aborts it.
# `return 3` = no upstream build for this platform; the package manager is tried instead.

vendor_go() {
  v=$(fetch_text 'https://go.dev/VERSION?m=text' | head -n 1)
  fetch "https://go.dev/dl/$v.$OS-$ARCH.tar.gz" "$TMP/go.tgz"
  rm -rf "$PREFIX/go"
  tar -C "$PREFIX" -xzf "$TMP/go.tgz"
  ln -sf "$PREFIX/go/bin/go" "$BIN/go"          # go resolves GOROOT through symlinks
  ln -sf "$PREFIX/go/bin/gofmt" "$BIN/gofmt"
}

vendor_govulncheck() {   # built from source with Go (listed after go in packages.txt)
  if ! command -v go >/dev/null 2>&1; then
    echo "govulncheck needs Go — install the go package first" >&2
    return 1
  fi
  env GOBIN="$BIN" go install golang.org/x/vuln/cmd/govulncheck@latest
}

vendor_chezmoi() {
  fetch https://get.chezmoi.io "$TMP/chezmoi.sh"
  sh "$TMP/chezmoi.sh" -b "$BIN"
}

vendor_starship() {
  fetch https://starship.rs/install.sh "$TMP/starship.sh"
  sh "$TMP/starship.sh" --yes --bin-dir "$BIN" >/dev/null
}

vendor_neovim() {
  [ "$MUSL" = 1 ] && return 3                   # upstream builds are glibc-only
  case $OS in linux) o=linux ;; darwin) o=macos ;; esac
  case $ARCH in amd64) a=x86_64 ;; arm64) a=arm64 ;; esac
  fetch "$(gh_asset neovim/neovim "nvim-$o-$a.tar.gz")" "$TMP/nvim.tgz"
  rm -rf "$OPT/nvim" && mkdir -p "$OPT/nvim"
  tar -C "$OPT/nvim" --strip-components=1 -xzf "$TMP/nvim.tgz"
  [ "$OS" = darwin ] && xattr -cr "$OPT/nvim" 2>/dev/null
  ln -sf "$OPT/nvim/bin/nvim" "$BIN/nvim"
}

vendor_eza() {
  [ "$OS" = darwin ] && return 3                # eza publishes no macOS binaries
  case $ARCH-$MUSL in
    amd64-0) t=x86_64-unknown-linux-gnu ;;
    amd64-1) t=x86_64-unknown-linux-musl ;;
    arm64-0) t=aarch64-unknown-linux-gnu ;;
    *)       return 3 ;;
  esac
  fetch "$(gh_asset eza-community/eza "eza_$t.tar.gz")" "$TMP/eza.tgz"
  tar -C "$TMP" -xzf "$TMP/eza.tgz"
  install -m 755 "$TMP/eza" "$BIN/eza"
}

vendor_fzf() {   # distro fzf is often too old for `fzf --zsh` (needs >= 0.48)
  v=$(gh_latest_version junegunn/fzf)
  [ -n "$v" ]
  fetch "https://github.com/junegunn/fzf/releases/download/v$v/fzf-$v-${OS}_$ARCH.tar.gz" "$TMP/fzf.tgz"
  tar -C "$TMP" -xzf "$TMP/fzf.tgz"
  install -m 755 "$TMP/fzf" "$BIN/fzf"
}

vendor_kubernetes_cli() {
  v=$(fetch_text https://dl.k8s.io/release/stable.txt)
  fetch "https://dl.k8s.io/release/$v/bin/$OS/$ARCH/kubectl" "$TMP/kubectl"
  install -m 755 "$TMP/kubectl" "$BIN/kubectl"
}

vendor_helm() {
  v=$(fetch_text https://get.helm.sh/helm-latest-version)
  fetch "https://get.helm.sh/helm-$v-$OS-$ARCH.tar.gz" "$TMP/helm.tgz"
  tar -C "$TMP" -xzf "$TMP/helm.tgz"
  install -m 755 "$TMP/$OS-$ARCH/helm" "$BIN/helm"
}

vendor_terraform() { hashicorp_install terraform; }
vendor_vault()     { hashicorp_install vault; }
vendor_nomad()     { hashicorp_install nomad; }
vendor_consul()    { hashicorp_install consul; }

gh_latest_version() {   # owner/repo -> "2.104.0", via the releases/latest redirect (no API rate limit)
  curl -fsSLI --retry 3 -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" |
    sed -n 's|.*/tag/v\{0,1\}||p'
}

vendor_github_cli() {
  v=$(gh_latest_version cli/cli)
  [ -n "$v" ]
  case $OS in
    linux)
      d="gh_${v}_linux_$ARCH"
      fetch "https://github.com/cli/cli/releases/download/v$v/$d.tar.gz" "$TMP/gh.tgz"
      tar -C "$TMP" -xzf "$TMP/gh.tgz" ;;
    darwin)
      d="gh_${v}_macOS_$ARCH"
      fetch "https://github.com/cli/cli/releases/download/v$v/$d.zip" "$TMP/gh.zip"
      unzip -oq "$TMP/gh.zip" -d "$TMP" ;;
  esac
  install -m 755 "$TMP/$d/bin/gh" "$BIN/gh"
}

vendor_awscli() {
  if [ "$OS" = darwin ]; then
    # Official .pkg, installed into the home directory (no sudo) via a choices file.
    fetch https://awscli.amazonaws.com/AWSCLIV2.pkg "$TMP/AWSCLIV2.pkg"
    mkdir -p "$OPT"
    cat >"$TMP/choices.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><array><dict>
  <key>choiceAttribute</key><string>customLocation</string>
  <key>attributeSetting</key><string>$OPT</string>
  <key>choiceIdentifier</key><string>default</string>
</dict></array></plist>
EOF
    installer -pkg "$TMP/AWSCLIV2.pkg" -target CurrentUserHomeDirectory \
      -applyChoiceChangesXML "$TMP/choices.xml" >/dev/null
    ln -sf "$OPT/aws-cli/aws" "$BIN/aws"
    ln -sf "$OPT/aws-cli/aws_completer" "$BIN/aws_completer"
  else
    [ "$MUSL" = 1 ] && return 3
    case $ARCH in amd64) a=x86_64 ;; arm64) a=aarch64 ;; esac
    fetch "https://awscli.amazonaws.com/awscli-exe-linux-$a.zip" "$TMP/awscli.zip"
    unzip -q "$TMP/awscli.zip" -d "$TMP"
    "$TMP/aws/install" --install-dir "$OPT/aws-cli" --bin-dir "$BIN" --update >/dev/null
  fi
}

ensure_uv() {
  command -v uv >/dev/null 2>&1 && return 0
  fetch https://astral.sh/uv/install.sh "$TMP/uv.sh"
  env UV_INSTALL_DIR="$BIN" INSTALLER_NO_MODIFY_PATH=1 sh "$TMP/uv.sh" >/dev/null
}

vendor_azurecli() {
  # Microsoft's pip-based install, isolated in its own venv by uv.
  ensure_uv
  env UV_TOOL_BIN_DIR="$BIN" uv tool install --quiet --force --python 3.12 azure-cli
}

vendor_google_cloud_sdk() {
  case $OS-$ARCH in
    linux-amd64|darwin-amd64) a=x86_64 ;;
    linux-arm64|darwin-arm64) a=arm ;;
  esac
  fetch "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-$OS-$a.tar.gz" "$TMP/gcloud.tgz"
  rm -rf "$OPT/google-cloud-sdk" && mkdir -p "$OPT"
  tar -C "$OPT" -xzf "$TMP/gcloud.tgz"
  "$OPT/google-cloud-sdk/install.sh" --quiet --usage-reporting=false \
    --path-update=false --command-completion=false >/dev/null
  for c in gcloud gsutil bq; do ln -sf "$OPT/google-cloud-sdk/bin/$c" "$BIN/$c"; done
}

# Maple Mono Nerd Font (https://github.com/subframe7536/maple-font)
font_dir() {
  case $OS in
    darwin) echo "$HOME/Library/Fonts" ;;
    linux)  echo "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/MapleMono-NF" ;;
  esac
}
win_fonts_dir() {   # WSL: the per-user Windows font folder (the terminal renders with Windows fonts)
  ps=$(command -v powershell.exe 2>/dev/null || echo /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe)
  d=$("$ps" -NoProfile -NonInteractive -Command '[Environment]::GetFolderPath("LocalApplicationData")' </dev/null 2>/dev/null | tr -d '\r')
  [ -n "$d" ] && echo "$(wslpath -u "$d")/Microsoft/Windows/Fonts"
}
have_maple_mono_nf() {
  if [ "$WSL" = 1 ]; then
    w=$(win_fonts_dir) && [ -f "$w/MapleMono-NF-Regular.ttf" ]
  else
    [ -f "$(font_dir)/MapleMono-NF-Regular.ttf" ]
  fi
}
vendor_maple_mono_nf() {
  case $OS in darwin) z=MapleMono-NF-unhinted.zip ;; *) z=MapleMono-NF.zip ;; esac
  fetch "$(gh_asset subframe7536/maple-font "$z")" "$TMP/maple.zip"
  mkdir -p "$TMP/maple"
  unzip -oq "$TMP/maple.zip" -d "$TMP/maple"
  d=$(font_dir) && mkdir -p "$d"
  find "$TMP/maple" -name '*.ttf' -exec cp {} "$d/" \;
  [ "$OS" = linux ] && command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$d" >/dev/null
  if [ "$WSL" = 1 ]; then
    w=$(win_fonts_dir) && mkdir -p "$w"
    reg=$(command -v reg.exe 2>/dev/null || echo /mnt/c/Windows/System32/reg.exe)
    for f in "$TMP"/maple/*.ttf "$TMP"/maple/*/*.ttf; do
      [ -f "$f" ] || continue
      n=$(basename "$f" .ttf)
      [ -f "$w/$n.ttf" ] || cp "$f" "$w/"   # Windows locks fonts in use; keep existing ones
      "$reg" add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
        /v "$n (TrueType)" /t REG_SZ /d "$(wslpath -w "$w/$n.ttf")" /f >/dev/null
    done
    : >"$WORK/.font-windows"     # summary reminds you to restart Windows Terminal
  fi
}

# ========================================================== prerequisites ====
BASE_MISSING=""
find_base_missing() {
  BASE_MISSING=""
  [ "$OS" = linux ] || return 0
  for c in curl git unzip tar gzip python3; do
    command -v $c >/dev/null 2>&1 || BASE_MISSING="$BASE_MISSING $c"
  done
}

ensure_base() {
  if [ "$OS" = darwin ]; then
    if xcode-select -p >/dev/null 2>&1; then
      ok "Xcode Command Line Tools $(xcode-select -p 2>/dev/null)"
      return 0
    fi
    [ "$DRY_RUN" = 1 ] && { skip "would install Xcode Command Line Tools"; return 0; }
    step "Opening the Xcode Command Line Tools installer (git, make, clang)"
    xcode-select --install >/dev/null 2>&1 || true
    die "Finish the Command Line Tools installer, then re-run ./install.sh"
  fi
  find_base_missing
  if [ -z "$BASE_MISSING" ]; then
    ok "curl git unzip tar gzip python3"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then skip "would install with $PM:$BASE_MISSING"; return 0; fi
  [ "$PM" = none ] && die "No supported package manager to install:$BASE_MISSING"
  elevate "install prerequisites with $(pm_label):$BASE_MISSING" ||
    die "Prerequisites missing:$BASE_MISSING — re-run and allow sudo, or install them yourself"
  task "$WORK/base.log" "Refreshing $PM package index" pm_refresh || { fail "$PM refresh failed"; show_log "$WORK/base.log"; }
  # shellcheck disable=SC2086
  if task "$WORK/base.log" "Installing$BASE_MISSING" pm_install $BASE_MISSING ca-certificates fontconfig; then
    ok "Installed$BASE_MISSING"
  else
    fail "Could not install prerequisites"; show_log "$WORK/base.log"; exit 1
  fi
}

# =============================================================== manifest ====
# Each manifest line becomes: name via cmd native_name
parse_manifest() {
  set -f
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    # shellcheck disable=SC2086
    set -- $line
    [ $# -eq 0 ] && continue
    name=$1; shift
    via=auto cmd=$name native=$name
    for kv in "$@"; do
      k=${kv%%=*} v=${kv#*=}
      case $k in
        via) via=$v ;;
        cmd) cmd=$v ;;
        "$PM") native=$v ;;
        apt|dnf|yum|pacman|zypper|apk|port) ;;
        *) warn "packages.txt: unknown key '$k' for $name" >&2 ;;
      esac
    done
    # yum distros use dnf names
    if [ "$PM" = yum ]; then
      for kv in "$@"; do case $kv in dnf=*) native=${kv#dnf=} ;; esac; done
    fi
    echo "$name $via $cmd $native"
  done <"$PKG_FILE"
  set +f
}

selected() { case ",$ONLY," in ,,|*",$1,"*) return 0 ;; *) return 1 ;; esac; }

has_fn() { command -v "$1" >/dev/null 2>&1; }

is_installed() {   # name cmd
  id=$(echo "$1" | tr '-' '_')
  if has_fn "have_$id"; then "have_$id"
  elif [ "$2" = - ]; then return 1
  else command -v "$2" >/dev/null 2>&1
  fi
}

native_ok() { [ "$1" != - ] && [ "$PM" != none ] && pm_has "$1"; }

# Decide how a package gets installed here: prints "vendor", "native" or "none".
# Only searches the package manager when the answer depends on it.
plan_for() {   # name via native
  id=$(echo "$1" | tr '-' '_')
  case $2 in
    native) if native_ok "$3"; then echo native; else echo none; fi ;;
    vendor) if has_fn "vendor_$id"; then echo vendor
            elif native_ok "$3"; then echo native; else echo none; fi ;;
    *)      if native_ok "$3"; then echo native
            elif has_fn "vendor_$id"; then echo vendor; else echo none; fi ;;
  esac
}

needs_install() {   # name via cmd
  is_installed "$1" "$3" || return 0
  [ "$UPGRADE" = 1 ] && [ "$2" != native ] && return 0
  return 1
}

# ================================================================ install ====
N_OK=0 N_HAVE=0 N_FAIL=0 N_NOROOT=0
FAILED="" NOROOT=""

pkg_line() {   # icon colour name detail [seconds]
  p_t=""
  [ $# -ge 5 ] && p_t="$(dur "$5")"
  printf '  %s%s%s %-18s %s%s%s %s%s%s\n' "$2" "$1" "$RST" "$3" "$DIM" "$4" "$RST" "$DIM" "$p_t" "$RST"
}

mark_failed() {   # name logfile [exit code]
  N_FAIL=$((N_FAIL + 1)); FAILED="$FAILED $1"
  if [ -s "$2" ]; then
    mkdir -p "$LOG_DIR" && cp "$2" "$LOG_DIR/$1.log" 2>/dev/null
    show_log "$2"
  fi
  # curl 23 = couldn't write, unzip 50 = disk full
  if grep -qi 'no space left' "$2" 2>/dev/null || [ "${3:-}" = 23 ] || [ "${3:-}" = 50 ]; then
    note "Looks like the disk filled up: $(free_space_h "$WORK") free in $WORK_BASE, $(free_space_h "$PREFIX") in $PREFIX"
    DISK_FULL=1
  fi
}

install_native() {   # name native
  if ! elevate "install $2 with $(pm_label)"; then
    pkg_line "$I_WARN" "$YLW" "$1" "needs root to install with $PM — skipped"
    N_NOROOT=$((N_NOROOT + 1)); NOROOT="$NOROOT $1"
    return
  fi
  i_log="$WORK/$1.log" i_t0=$(now)
  if task "$i_log" "$1  installing with $PM" sh_pm_install "$2"; then
    pkg_line "$I_OK" "$GRN" "$1" "$PM: $2" $(($(now) - i_t0)); N_OK=$((N_OK + 1))
  else
    pkg_line "$I_FAIL" "$RED" "$1" "$PM install failed" $(($(now) - i_t0)); mark_failed "$1" "$i_log"
  fi
}
sh_pm_install() { pm_refresh; pm_install "$@"; }

# run_vendor <id> — run vendor_<id> with its own empty download folder in $TMP.
# Callers delete "$WORK/dl-<id>" afterwards so disk use never piles up across packages.
run_vendor() {
  TMP="$WORK/dl-$1"
  rm -rf "$TMP" && mkdir -p "$TMP"
  "vendor_$1"
}

install_one() {   # name via cmd native
  name=$1 via=$2 cmd=$3 native=$4
  id=$(echo "$name" | tr '-' '_')

  if ! needs_install "$name" "$via" "$cmd"; then
    pkg_line "$I_SKIP" "$DIM" "$name" "already installed"; N_HAVE=$((N_HAVE + 1))
    return
  fi

  how=$(plan_for "$name" "$via" "$native")
  if [ "$DRY_RUN" = 1 ]; then
    case $how in
      vendor) pkg_line "$I_RUN" "$CYN" "$name" "would install the upstream release" ;;
      native) pkg_line "$I_RUN" "$CYN" "$name" "would install '$native' with $PM (needs root)" ;;
      none)   pkg_line "$I_WARN" "$YLW" "$name" "no installer available on $DISTRO/$PM" ;;
    esac
    return
  fi

  case $how in
    native) install_native "$name" "$native" ;;
    vendor)
      i_log="$WORK/$name.log" i_t0=$(now)
      task "$i_log" "$name  downloading upstream release" run_vendor "$id"; rc=$?
      rm -rf "$WORK/dl-$id"
      if [ $rc -eq 0 ]; then
        pkg_line "$I_OK" "$GRN" "$name" "upstream" $(($(now) - i_t0)); N_OK=$((N_OK + 1))
      elif [ $rc -eq 3 ] && native_ok "$native"; then
        install_native "$name" "$native"
      elif [ $rc -eq 3 ]; then
        pkg_line "$I_FAIL" "$RED" "$name" "no upstream build for $OS/$ARCH, not available from $PM"
        N_FAIL=$((N_FAIL + 1)); FAILED="$FAILED $name"
      else
        pkg_line "$I_FAIL" "$RED" "$name" "upstream install failed (exit $rc)" $(($(now) - i_t0))
        mark_failed "$name" "$i_log" "$rc"
      fi ;;
    none)
      pkg_line "$I_FAIL" "$RED" "$name" "not in $PM and no upstream installer"
      N_FAIL=$((N_FAIL + 1)); FAILED="$FAILED $name" ;;
  esac
}

free_kb() { df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print $4 }'; }
free_space_h() {
  f=$(free_kb "$1"); [ -n "$f" ] || { echo "?"; return; }
  if [ "$f" -ge 1048576 ]; then awk -v k="$f" 'BEGIN { printf "%.1f GB", k / 1048576 }'
  else echo "$((f / 1024)) MB"; fi
}
DISK_FULL=0
check_disk() {   # the full package set needs ~3 GB in $PREFIX plus ~1 GB of scratch at peak
  for d in "$PREFIX" "$WORK"; do
    f=$(free_kb "$d"); [ -n "$f" ] || continue
    if [ "$f" -lt 3145728 ]; then
      warn "Only $(free_space_h "$d") free in $d — a full install needs about 3 GB"
    fi
  done
}

# What will need root? Collected before anything runs so there's one prompt, up front.
preflight() {
  set --
  find_base_missing
  [ -n "$BASE_MISSING" ] && set -- "$@" "install prerequisites with $(pm_label):$BASE_MISSING"
  if [ "$DO_PKGS" = 1 ]; then
    p_list=""
    while read -r name via cmd native; do
      selected "$name" || continue
      needs_install "$name" "$via" "$cmd" || continue
      [ "$native" = - ] || [ "$PM" = none ] && continue
      id=$(echo "$name" | tr '-' '_')
      case $via in
        native) p_list="$p_list $native" ;;
        auto)   if ! has_fn "vendor_$id" || pm_search "$native"; then p_list="$p_list $native"; fi ;;
      esac
    done <"$WORK/manifest"
    [ -n "$p_list" ] && set -- "$@" "install with $(pm_label):$p_list"
  fi
  if [ "$DO_DOTFILES" = 1 ] && [ "$DO_CHSH" = 1 ] && [ "$OS" = linux ]; then
    z=$(command -v zsh 2>/dev/null)
    if [ -n "$z" ] && [ "$(basename "${SHELL:-}")" != zsh ] && ! grep -qx "$z" /etc/shells 2>/dev/null; then
      set -- "$@" "add $z to /etc/shells"
    fi
  fi

  if [ $# -eq 0 ]; then
    ok "Nothing needs root — everything installs into $PREFIX"
    return
  fi
  if [ "$PRIV" = granted ]; then
    ok "Running as root"
    return
  fi
  elevate "$@" || true
}

# =============================================================== dotfiles ====
apply_dotfiles() {
  if ! command -v chezmoi >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 1 ]; then skip "would install chezmoi first"; return; fi
    task "$WORK/chezmoi.log" "Installing chezmoi" run_vendor chezmoi ||
      { fail "Could not install chezmoi"; show_log "$WORK/chezmoi.log"; exit 1; }
    ok "chezmoi installed"
  fi
  kv "Source" "$REPO_DIR"
  changes=$(chezmoi --source "$REPO_DIR" status 2>/dev/null)
  if [ -z "$changes" ]; then
    ok "Everything already up to date"
    [ "$DRY_RUN" = 1 ] && return
  else
    echo "$changes" | while read -r st path; do
      case $st in
        *R*) printf '  %s%s%s run   %s\n' "$MAG" "$I_RUN" "$RST" "$path" ;;
        A*)  printf '  %s%s%s add   ~/%s\n' "$GRN" "$I_DOTS" "$RST" "$path" ;;
        D*)  printf '  %s%s%s del   ~/%s\n' "$RED" "$I_DOTS" "$RST" "$path" ;;
        *)   printf '  %s%s%s write ~/%s\n' "$BLU" "$I_DOTS" "$RST" "$path" ;;
      esac
    done
    [ "$DRY_RUN" = 1 ] && { skip "dry run — not applied"; return; }
  fi
  # Foreground, so chezmoi can ask if a file was edited outside chezmoi.
  # DOTFILES_BOOTSTRAP stops the run_onchange package script from re-running this installer.
  if have_tty; then
    DOTFILES_BOOTSTRAP=1 chezmoi init --apply --source "$REPO_DIR" </dev/tty; rc=$?
  else
    DOTFILES_BOOTSTRAP=1 chezmoi init --apply --source "$REPO_DIR" --no-tty </dev/null; rc=$?
  fi
  if [ $rc -eq 0 ]; then
    ok "Dotfiles applied"
  else
    fail "chezmoi left changes unapplied — run: chezmoi apply -v"; N_FAIL=$((N_FAIL + 1)); FAILED="$FAILED dotfiles"
  fi
}

change_shell() {
  zsh_path=$(command -v zsh 2>/dev/null)
  if [ -z "$zsh_path" ]; then warn "zsh isn't installed — keeping ${SHELL:-current shell}"; return; fi
  if [ "$(basename "${SHELL:-}")" = zsh ]; then ok "Login shell is already zsh"; return; fi
  kv "Current" "${SHELL:-unknown}"
  if [ "$DRY_RUN" = 1 ]; then skip "would change login shell to $zsh_path"; return; fi
  if ! ask_yn "Make $zsh_path your login shell?" y; then
    skip "Keeping ${SHELL:-current shell} — change later with: chsh -s $zsh_path"; return
  fi
  if [ "$OS" = linux ] && ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    if elevate "add $zsh_path to /etc/shells"; then
      echo "$zsh_path" | as_root tee -a /etc/shells >/dev/null
    else
      warn "$zsh_path isn't in /etc/shells and there's no root to add it — skipping"; return
    fi
  fi
  me=$(id -un)
  # With root already granted, change it without a second password prompt.
  if [ "$PRIV" = granted ] && as_root chsh -s "$zsh_path" "$me" >/dev/null 2>&1; then
    ok "Login shell changed to $zsh_path"
  elif have_tty && chsh -s "$zsh_path" </dev/tty; then
    ok "Login shell changed to $zsh_path"
  else
    warn "chsh failed — run it yourself: chsh -s $zsh_path"
  fi
}

summary() {
  elapsed=$(($(now) - START))
  printf '\n%s%s%s  %sSummary%s  %s%s%s\n' "$BOLD$MAG" "$I_DONE" "$RST" "$BOLD" "$RST" "$DIM" "$(dur $elapsed)" "$RST"
  printf '%s%s%s\n' "$DIM" "$RULE" "$RST"
  if [ "$DO_PKGS" = 1 ] && [ "$DRY_RUN" = 0 ]; then
    printf '  %s%s %d installed%s   %s%s %d already present%s' "$GRN" "$I_OK" "$N_OK" "$RST" "$DIM" "$I_SKIP" "$N_HAVE" "$RST"
    [ "$N_NOROOT" -gt 0 ] && printf '   %s%s %d skipped (no root)%s' "$YLW" "$I_WARN" "$N_NOROOT" "$RST"
    [ "$N_FAIL" -gt 0 ] && printf '   %s%s %d failed%s' "$RED" "$I_FAIL" "$N_FAIL" "$RST"
    printf '\n'
  fi
  [ -n "$NOROOT" ] && note "Needs root:$NOROOT — re-run and answer y to install them"
  if [ -n "$FAILED" ]; then
    note "Failed:$FAILED"
    [ "$DISK_FULL" = 1 ] && note "Free up space (or set TMPDIR to a bigger disk), then re-run — finished packages are skipped"
    [ -d "$LOG_DIR" ] && note "Logs: $LOG_DIR"
  fi
  [ -f "$WORK/.font-windows" ] && note "Maple Mono NF was installed for Windows — restart Windows Terminal and pick 'Maple Mono NF'"
  if [ "$DRY_RUN" = 1 ]; then
    printf '\n  %s%s Dry run complete — nothing was changed.%s\n\n' "$CYN$BOLD" "$I_DONE" "$RST"
  elif [ -n "$FAILED" ]; then
    printf '\n  %s%s Finished with errors.%s\n\n' "$RED$BOLD" "$I_FAIL" "$RST"
    exit 1
  else
    printf '\n  %s%s All done!%s Open a new terminal to start using everything.\n\n' "$GRN$BOLD" "$I_DONE" "$RST"
  fi
}

# =================================================================== main ====
mkdir -p "$BIN" "$OPT"
PATH="$BIN:$PATH"; export PATH
parse_manifest >"$WORK/manifest"
if [ -n "$ONLY" ]; then
  for want in $(echo "$ONLY" | tr ',' ' '); do
    grep -q "^$want " "$WORK/manifest" || die "--only: '$want' is not in packages.txt"
  done
fi

if [ "$LIST" = 1 ]; then
  printf '\n  %s%-18s %-10s %-8s %s%s\n' "$BOLD" "PACKAGE" "STATE" "VIA" "INSTALLS WITH" "$RST"
  while read -r name via cmd native; do
    if is_installed "$name" "$cmd"; then st="installed" sc=$GRN si=$I_OK; else st="missing" sc=$YLW si=$I_SKIP; fi
    how=$(plan_for "$name" "$via" "$native")
    [ "$how" = native ] && how="$PM ($native)"
    [ "$how" = vendor ] && how="upstream release"
    printf '  %s%s %-16s%s %s%-10s%s %-8s %s\n' "$sc" "$si" "$name" "$RST" "$sc" "$st" "$RST" "$via" "$how"
  done <"$WORK/manifest"
  echo
  exit 0
fi

STAGE_TOTAL=2   # platform + privileges
[ "$DO_PKGS" = 1 ] && STAGE_TOTAL=$((STAGE_TOTAL + 2))
[ "$DO_DOTFILES" = 1 ] && STAGE_TOTAL=$((STAGE_TOTAL + 1))
[ "$DO_DOTFILES" = 1 ] && [ "$DO_CHSH" = 1 ] && STAGE_TOTAL=$((STAGE_TOTAL + 1))

banner

stage "$I_PLATFORM" "$BLU" "Platform"
kv "System" "${DISTRO_NAME:-$OS}$( [ $WSL = 1 ] && echo ' (WSL)')$( [ $MUSL = 1 ] && echo ' (musl)')"
kv "Architecture" "$ARCH"
kv "Packages" "$( [ "$PM" = none ] && echo 'none (upstream releases only)' || echo "$PM")"
kv "Install dir" "$PREFIX"
if [ "$PRIV" = granted ]; then kv "User" "root"; else kv "User" "$(id -un)${SUDO_BIN:+ ($SUDO_BIN available)}"; fi
[ "$DRY_RUN" = 1 ] && kv "Mode" "${YLW}dry run — nothing will be changed${RST}"

stage "$I_PRIV" "$YLW" "Privileges"
preflight

if [ "$DO_PKGS" = 1 ]; then
  stage "$I_PREREQ" "$CYN" "Prerequisites"
  check_disk
  ensure_base

  stage "$I_PKG" "$GRN" "Packages"
  while read -r name via cmd native; do
    selected "$name" || continue
    install_one "$name" "$via" "$cmd" "$native" </dev/null
  done <"$WORK/manifest"
fi

if [ "$DO_DOTFILES" = 1 ]; then
  stage "$I_DOTS" "$MAG" "Dotfiles"
  apply_dotfiles
  if [ "$DO_CHSH" = 1 ]; then
    stage "$I_SHELL" "$BLU" "Login shell"
    change_shell
  fi
fi

summary
