# Sourced by the explicitly installed interactive zsh integration.
[[ -o interactive ]] || return 0
(( ${+_TH_LOADED} )) && return 0
typeset -g _TH_LOADED=1 _TH_ACTIVE=0 _TH_ORIGINAL='' _TH_CURSOR=0
zmodload zsh/stat || return 0
zmodload zsh/mapfile || return 0

_th_enabled() {
  local base="$HOME/Library/Application Support/Terminal Helper" value
  local -A info
  [[ -d "$base" && ! -L "$base" && -O "$base" ]] || return 1
  zstat -H info -- "$base" 2>/dev/null || return 1
  (( (info[mode] & 0777) == 0700 )) || return 1
  [[ -f "$base/state" && ! -L "$base/state" && -O "$base/state" ]] || return 1
  zstat -H info -- "$base/state" 2>/dev/null || return 1
  (( (info[mode] & 0777) == 0600 && info[size] == 22 )) || return 1
  value=${mapfile[$base/state]}
  [[ "$value" == $'terminal-helper-v1:on\n' ]]
}

_th_supported() {
  [[ "$BUFFER" != *[[:cntrl:]]* && "$BUFFER" != *['$`*?[]{};|&<>()']* ]]
}

_th_correct() {
  setopt localoptions extendedglob nullglob
  local token=$PREFIX parent leaf candidate
  [[ -n "$token" ]] || return 1
  [[ -e "$token" || -L "$token" ]] && return 1
  if [[ "$token" == */* ]]; then
    parent=${token:h}
    leaf=${token:t}
  else
    parent=.
    leaf=$token
  fi
  [[ "$parent" == '~' ]] && parent=$HOME
  [[ "$parent" == '~/'* ]] && parent="$HOME/${parent#\~/}"
  [[ -d "$parent" && ${#leaf} -ge 3 && ${#leaf} -le 128 ]] || return 1
  # shortcut: directory enumeration is filesystem-dependent; no fuzzy work above 256 entries.
  local -a entries candidates
  entries=("$parent"/*(ND[1,257]))
  (( ${#entries} <= 256 )) || return 1
  for candidate in "$entries[@]"; do
    [[ "${candidate:t}" == *[[:cntrl:]]* ]] && continue
    [[ "${words[1]}" == cd && ! -d "$candidate" ]] && continue
    [[ "${candidate:t}" == (#a1)"$leaf" ]] || continue
    candidates+=("${candidate:t}")
    (( ${#candidates} == 20 )) && break
  done
  (( ${#candidates} )) || return 1
  local -a expl
  _description corrections expl 'typo corrections (choose explicitly)'
  compadd "$expl[@]" -W "$parent" -- "$candidates[@]"
}

_th_tab() {
  _th_enabled || { zle -M 'Terminal Helper: Off'; return 0; }
  _th_supported || { zle -M 'Terminal Helper: unsupported syntax; input unchanged'; return 0; }
  if (( ! ${+functions[compdef]} )); then
    autoload -Uz compinit
    # Retain zsh completion ownership/permission checks and avoid dump/cache creation.
    compinit -D || return 0
  fi
  _TH_ORIGINAL=$BUFFER
  _TH_CURSOR=$CURSOR
  _TH_ACTIVE=1
  zle _th_completion
}

_th_completion() {
  local MENUSELECT=1 LISTMAX=20
  _main_complete _complete _th_correct
  compstate[insert]=menu
}

_th_accept() {
  if (( _TH_ACTIVE )); then
    _th_enabled || { BUFFER=$_TH_ORIGINAL; CURSOR=$_TH_CURSOR; }
    _TH_ACTIVE=0
    zle -M ''
    return 0
  fi
  zle _th_original_accept
}

_th_cancel() {
  if (( _TH_ACTIVE )); then
    BUFFER=$_TH_ORIGINAL
    CURSOR=$_TH_CURSOR
    _TH_ACTIVE=0
    zle -M ''
  else
    zle send-break
  fi
}

_th_redraw() {
  if (( _TH_ACTIVE )) && ! _th_enabled; then
    BUFFER=$_TH_ORIGINAL
    CURSOR=$_TH_CURSOR
    _TH_ACTIVE=0
    zle -M 'Terminal Helper: Off; suggestion cancelled'
  fi
}

_th_line_finish() { _TH_ACTIVE=0; }

zle -A accept-line _th_original_accept
zle -N _th_tab
zle -N _th_accept
zle -N _th_cancel
zle -C _th_completion complete-word _th_completion
# Tab is the explicit opt-in binding; Enter delegates unchanged when idle.
bindkey '^I' _th_tab
bindkey '^[' _th_cancel
zle -N accept-line _th_accept
zmodload zsh/complist
bindkey -M menuselect '^M' _th_accept
bindkey -M menuselect '^J' _th_accept
bindkey -M menuselect '^I' _th_tab
bindkey -M menuselect '^[' _th_cancel
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-pre-redraw _th_redraw
add-zle-hook-widget line-finish _th_line_finish
