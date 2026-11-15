# ~/.config/zsh/aliases.zsh — sourced by ~/.zshrc. Managed by chezmoi:
# edit with `chezmoi edit ~/.config/zsh/aliases.zsh`, then `chezmoi apply`.

# editor aliases

alias vi='nvim'
alias vim='nvim'

# ls aliases (only when eza is installed, so plain ls still works without it)

if (( $+commands[eza] )); then
  alias ls='eza'
  alias ll='ls -l'
  alias la='ls -la'
  alias tree='ll --tree'
fi

# Debian/Ubuntu ship fd and bat under other names

if (( $+commands[fdfind] )); then alias fd='fdfind'; fi
if (( $+commands[batcat] )); then alias bat='batcat'; fi

# git aliases

alias g='git'
alias gps='git push'
alias gpsff='git push -ff'
alias gpl='git pull'
alias gbv='git branch -vvv'
alias gbc='git branch -c'
alias gbd='git branch -D'
alias gck='git checkout'
alias gckb='git checkout -b'
alias gcm='git commit -m'
alias gaa='git add .'

# go aliases

alias gmi='go mod init'
alias gg='go get'
alias gt='go test'

# govulncheck aliases

alias gvck='govulncheck ./...'

# kubectl aliases

alias k='kubectl'

# terraform aliases

alias tf='terraform'
alias tfv='terraform --version'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfaa='terraform apply -auto-approve'
alias tfd='terraform destroy'
alias tfda='terraform destroy -auto-approve'
alias tfs='terraform state list'
alias tft='terraform taint'
