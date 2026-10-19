# Sourced by the explicitly installed interactive zsh integration.
[[ -o interactive ]] || return 0
(( ${+_TH_LOADED} )) && return 0
typeset -g _TH_LOADED=1 _TH_ACTIVE=0 _TH_ORIGINAL='' _TH_CURSOR=0 _TH_CANCELLED=0 _TH_READY=0 _TH_PREVIEW_SET=0 _TH_PREVIEW='' _TH_MENU_ACTIVE=0

# Explicit management commands work independently of the suggestions switch.
if ! whence -w terminal-helper >/dev/null 2>&1; then
  function terminal-helper {
    local flag base="$HOME/Library/Application Support/Terminal Helper" record app executable
    local -A info
    (( $# == 1 )) || { print -u2 'Usage: terminal-helper version|check|update'; return 2; }
    case "$1" in
      version) flag=--version ;;
      check) flag=--check-for-updates ;;
      update) flag=--update ;;
      *) print -u2 'Usage: terminal-helper version|check|update'; return 2 ;;
    esac
    zmodload zsh/stat zsh/mapfile || return 1
    if [[ ! -d "$base" || -L "$base" || ! -O "$base" ]] ||
       ! zstat -H info -- "$base" 2>/dev/null ||
       (( (info[mode] & 8#7777) != 8#700 )); then
      print -u2 'Open Terminal Helper and reinstall shell integration.'
      return 1
    fi
    if [[ ! -f "$base/app-path" || -L "$base/app-path" || ! -O "$base/app-path" ]] ||
       ! zstat -H info -- "$base/app-path" 2>/dev/null ||
       (( (info[mode] & 8#7777) != 8#600 || info[size] < 2 || info[size] > 4097 )); then
      print -u2 'Open Terminal Helper and reinstall shell integration.'
      return 1
    fi
    record=$mapfile[$base/app-path]
    app=$record[1,-2]
    if [[ "$record" != "$app"$'\n' || "$app" != /*.app || "$app" == *[[:cntrl:]]* ]]; then
      print -u2 'Open Terminal Helper and reinstall shell integration.'
      return 1
    fi
    executable="$app/Contents/MacOS/TerminalHelper"
    if [[ ! -d "$app" || -L "$app" || ! -f "$executable" || -L "$executable" || ! -x "$executable" ]]; then
      print -u2 'Recorded app is unavailable. Open Terminal Helper and reinstall shell integration.'
      return 1
    fi
    "$executable" "$flag"
  }
fi

_th_enabled() {
  zmodload zsh/stat zsh/mapfile || return 1
  local base="$HOME/Library/Application Support/Terminal Helper" value
  local -A info
  [[ -d "$base" && ! -L "$base" && -O "$base" ]] || return 1
  zstat -H info -- "$base" 2>/dev/null || return 1
  (( (info[mode] & 8#777) == 8#700 )) || return 1
  [[ -f "$base/state" && ! -L "$base/state" && -O "$base/state" ]] || return 1
  zstat -H info -- "$base/state" 2>/dev/null || return 1
  (( (info[mode] & 8#777) == 8#600 && info[size] == 22 )) || return 1
  value=${mapfile[$base/state]}
  [[ "$value" == $'terminal-helper-v1:on\n' ]]
}

_th_supported() {
  local forbidden
  [[ "$BUFFER" != *[[:cntrl:]]* ]] || return 1
  for forbidden in '$' '`' '*' '?' '[' ']' '{' '}' ';' '|' '&' '<' '>' '(' ')'; do
    [[ "$BUFFER" != *"$forbidden"* ]] || return 1
  done
  return 0
}

_th_correct() {
  setopt localoptions extendedglob nullglob
  local token=$PREFIX parent leaf candidate insert_parent=
  [[ -n "$token" && -z "$SUFFIX" ]] || return 1
  (( CURRENT > 1 )) || [[ "$token" == */* ]] || return 1
  [[ -e "$token" || -L "$token" ]] && return 1
  if [[ "$token" == */* ]]; then
    parent=${token:h}
    insert_parent="$parent/"
    leaf=${token:t}
  else
    parent=.
    leaf=$token
  fi
  [[ "$parent" == '~' ]] && parent=$HOME
  [[ "$parent" == '~/'* ]] && parent="$HOME/${parent#\~/}"
  [[ -e "$parent/$leaf" || -L "$parent/$leaf" ]] && return 1
  [[ -d "$parent" && ${#leaf} -ge 3 && ${#leaf} -le 128 ]] || return 1
  # Short-circuit enumeration after 257 entries; native command completions have their own limits.
  local -a entries candidates
  entries=("$parent"/*(NDY257))
  (( ${#entries} <= 256 )) || return 1
  for candidate in "$entries[@]"; do
    # A bare leading dash would become a command option, even when shell-quoted.
    [[ -z "$insert_parent" && "${candidate:t}" == -* ]] && continue
    [[ "${candidate:t}" == *[[:cntrl:]]* ]] && continue
    [[ "${words[1]}" == cd && ! -d "$candidate" ]] && continue
    [[ "${candidate:t}" == (#a1)"$leaf" ]] || continue
    candidates+=("${candidate:t}")
    (( ${#candidates} == 20 )) && break
  done
  (( ${#candidates} )) || return 1
  local -a expl
  _description corrections expl 'typo corrections (choose explicitly)'
  compadd "$expl[@]" -U -f -p "$insert_parent" -W "$parent" -- "$candidates[@]"
}

_th_tab() {
  _th_enabled || { zle -M 'Terminal Helper: Off'; return 0; }
  _th_supported || { zle -M 'Terminal Helper: unsupported syntax; input unchanged'; return 0; }
  if (( ! _TH_READY )); then
    zmodload zsh/complist || return 0
    zle -C _th_completion .menu-select _th_completion
    autoload -Uz add-zle-hook-widget
    add-zle-hook-widget line-pre-redraw _th_redraw
    add-zle-hook-widget line-finish _th_line_finish
    _TH_READY=1
  fi
  if (( ! ${+functions[compdef]} )); then
    autoload -Uz compinit
    # Retain zsh completion ownership/permission checks and avoid dump/cache creation.
    compinit -D || return 0
  fi
  _TH_CANCELLED=0
  if (( ! _TH_ACTIVE )); then
    _TH_ORIGINAL=$BUFFER
    _TH_CURSOR=$CURSOR
    _TH_ACTIVE=1
  fi
  _TH_PREVIEW_SET=0
  # Native selection continues after the completion call; retain this map until it ends.
  if (( ! _TH_MENU_ACTIVE )); then
    bindkey -N _th_helper_menu menuselect
    bindkey -A menuselect _th_user_menu
    bindkey -M _th_helper_menu '^M' _th_menu_accept
    bindkey -M _th_helper_menu '^J' _th_menu_accept
    bindkey -M _th_helper_menu '^I' menu-complete
    bindkey -M _th_helper_menu '^[' _th_cancel
    bindkey -A _th_helper_menu menuselect
    _TH_MENU_ACTIVE=1
  fi
  {
    zle _th_completion
  } always {
    (( ! TRY_BLOCK_ERROR && _TH_ACTIVE )) || _th_restore_menu
  }
  if (( _TH_ACTIVE )); then
    _TH_PREVIEW=$BUFFER
    _TH_PREVIEW_SET=1
  fi
}

_th_completion() {
  local LISTMAX=20
  _main_complete _complete _th_correct
  if (( compstate[nmatches] )); then
    compstate[insert]=menu
  else
    _TH_ACTIVE=0
  fi
}

_th_restore_menu() {
  if (( _TH_MENU_ACTIVE )); then
    bindkey -A _th_user_menu menuselect
    bindkey -D _th_helper_menu _th_user_menu
    _TH_MENU_ACTIVE=0
  fi
}

_th_accept() {
  if (( _TH_CANCELLED )); then
    _TH_CANCELLED=0
    return 0
  fi
  if (( _TH_ACTIVE )); then
    _th_enabled || { BUFFER=$_TH_ORIGINAL; CURSOR=$_TH_CURSOR; }
    _TH_ACTIVE=0
    _th_restore_menu
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
    _th_restore_menu
    zle -M ''
  else
    if (( ${+widgets[_th_original_escape]} )); then
      zle _th_original_escape
    else
      zle send-break
    fi
  fi
}

_th_redraw() {
  if (( _TH_ACTIVE )) && ! _th_enabled; then
    BUFFER=$_TH_ORIGINAL
    CURSOR=$_TH_CURSOR
    _TH_ACTIVE=0
    _TH_CANCELLED=1
    _th_restore_menu
    zle -M 'Terminal Helper: Off; suggestion cancelled'
  elif (( _TH_ACTIVE && _TH_PREVIEW_SET )) && [[ "$BUFFER" != "$_TH_PREVIEW" ]]; then
    # Arrow selection also edits BUFFER; only actual editing widgets end the pending suggestion.
    case "$LASTWIDGET" in
      self-insert|quoted-insert|bracketed-paste|kill-whole-line|kill-buffer|backward-kill-line|backward-delete-char|delete-char|kill-word|backward-kill-word)
        _TH_ACTIVE=0
        _TH_PREVIEW_SET=0
        _th_restore_menu
        ;;
    esac
  fi
}

_th_return() {
  if (( _TH_ACTIVE || _TH_CANCELLED )); then _th_accept; else zle _th_original_return; fi
}

_th_newline() {
  if (( _TH_ACTIVE || _TH_CANCELLED )); then _th_accept; else zle _th_original_newline; fi
}

_th_line_finish() { _TH_ACTIVE=0; _TH_CANCELLED=0; _th_restore_menu; }

_th_menu_accept() {
  # A custom menu widget exits selection; never accept/execute the command here.
  (( _TH_ACTIVE || _TH_CANCELLED )) && _th_accept
  return 0
}

# Key macros cannot be safely delegated as widgets; leave this shell unchanged.
typeset -a _th_bindings
_th_bindings=("${(@f)$(bindkey '^M'; bindkey '^J'; bindkey '^[')}")
typeset _th_return_binding=${${(z)_th_bindings[1]}[-1]}
typeset _th_newline_binding=${${(z)_th_bindings[2]}[-1]}
typeset _th_escape_binding=${${(z)_th_bindings[3]}[-1]}
(( ${+widgets[$_th_return_binding]} && ${+widgets[$_th_newline_binding]} && ${+widgets[$_th_escape_binding]} )) || return 0
zle -A accept-line _th_original_accept
zle -A "$_th_return_binding" _th_original_return
zle -A "$_th_newline_binding" _th_original_newline
zle -A "$_th_escape_binding" _th_original_escape
unset _th_return_binding _th_newline_binding _th_escape_binding _th_bindings

zle -N _th_tab
zle -N _th_return
zle -N _th_newline
zle -N _th_accept
zle -N _th_menu_accept
zle -N _th_cancel
# Tab is the explicit opt-in binding; Enter delegates unchanged when idle.
bindkey '^I' _th_tab
bindkey '^M' _th_return
bindkey '^J' _th_newline
bindkey '^[' _th_cancel
zle -N accept-line _th_accept
