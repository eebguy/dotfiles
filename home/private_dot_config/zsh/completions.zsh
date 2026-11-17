# ~/.config/zsh/completions.zsh — Tab completion for tools that don't put a zsh
# completion file where zsh looks. Sourced by ~/.zshrc; compinit (ez-compinit) runs
# later, at the first prompt, so everything added to fpath here is picked up.
#
# Three kinds:
#   generated  the tool prints its own zsh completion; cached in ~/.cache/zsh/completions
#              and regenerated only when the tool's binary is newer than the cache
#   bash-style terraform, vault, nomad, consul, aws: the tool answers completion
#              requests itself (bash `complete -C`); _bash_complete asks it at Tab time
#   argcomplete az, gcloud (Python argcomplete); _argcomplete asks them at Tab time
#
# A completion that already exists elsewhere (Homebrew, a distro package, zsh itself)
# always wins; nothing here overrides it. Add a tool by adding it to a table below.

typeset -g _zcomp_cache=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions
fpath=($_zcomp_cache ${XDG_CONFIG_HOME:-$HOME/.config}/zsh/functions $fpath)

# command -> arguments that make it print its zsh completion script
typeset -gA _zcomp_generate=(
  kubectl      'completion zsh'
  helm         'completion zsh'
  gh           'completion -s zsh'
  chezmoi      'completion zsh'
  starship     'completions zsh'
  rg           '--generate complete-zsh'
  fd           '--gen-completions zsh'
  uv           'generate-shell-completion zsh'
  tree-sitter  'complete --shell zsh'
)
# Tweaks applied to a generated file (sed expression), keyed by command:
#   kubectl  asks the cluster for resource names; with no reachable cluster it retries
#            for ~30s and freezes the prompt, so cap each request at 2s
typeset -gA _zcomp_patch=(
  kubectl  's/__complete \${words\[2,-1\]}/__complete --request-timeout=2s ${words[2,-1]}/'
)
typeset -ga _zcomp_bash=(terraform vault nomad consul packer aws)
typeset -ga _zcomp_argcomplete=(az gcloud)

() {
  local cmd f changed=0
  local -a elsewhere=(${fpath:#$_zcomp_cache})   # every completion dir except our cache
  local -a found

  for cmd in ${(k)_zcomp_generate}; do
    (( $+commands[$cmd] )) || continue
    f=$_zcomp_cache/_$cmd
    if [[ -s $f ]]; then
      [[ $commands[$cmd] -nt $f ]] || continue           # cache is current
    else
      found=(${^elsewhere}/_$cmd(N))
      (( $#found )) && continue                           # shipped completion wins
    fi
    [[ -d $_zcomp_cache ]] || mkdir -p $_zcomp_cache
    if $cmd ${(z)_zcomp_generate[$cmd]} >| $f.tmp 2>/dev/null && [[ -s $f.tmp ]]; then
      [[ -n ${_zcomp_patch[$cmd]} ]] && sed -i.bak -e "${_zcomp_patch[$cmd]}" $f.tmp && rm -f $f.tmp.bak
      mv -f $f.tmp $f && changed=1
    else
      rm -f $f.tmp
    fi
  done

  # New completion files: drop the compinit cache so the next compinit sees them
  if (( changed )); then
    local dump=${ZSH_COMPDUMP:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump}
    rm -f $dump $dump.zwc
  fi

  # compdef here is ez-compinit's queue; the calls run once compinit has loaded
  for cmd in $_zcomp_bash; do
    local need=$cmd
    [[ $cmd == aws ]] && need=aws_completer               # aws completes via a helper
    (( $+commands[$need] )) || continue
    found=(${^elsewhere}/_$cmd(N)); (( $#found )) && continue
    compdef _bash_complete $cmd
  done
  for cmd in $_zcomp_argcomplete; do
    (( $+commands[$cmd] )) || continue
    found=(${^elsewhere}/_$cmd(N)); (( $#found )) && continue
    compdef _argcomplete $cmd
  done
}
