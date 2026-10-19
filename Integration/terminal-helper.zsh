# Sourced by the explicitly installed interactive zsh integration.
[[ -o interactive ]] || return 0
(( ${+_TH_LOADED} )) && return 0
typeset -gr _TH_INTEGRATION_VERSION=0.3.3
typeset -gA _TH_MAP_STATUS _TH_TAB_NAMES
typeset -g _TH_LOADED=1 _TH_ACTIVE=0 _TH_ORIGINAL='' _TH_CURSOR=0 _TH_CANCELLED=0 _TH_READY=0 _TH_PREVIEW_SET=0 _TH_PREVIEW='' _TH_MENU_ACTIVE=0 _TH_SELECTING=0

# Explicit management commands work independently of the suggestions switch.
if ! whence -w terminal-helper >/dev/null 2>&1; then
  function terminal-helper {
    local flag base="$HOME/Library/Application Support/Terminal Helper" record app executable
    local -A info
    (( $# == 1 )) || { print -u2 'Usage: terminal-helper version|check|update|doctor'; return 2; }
    case "$1" in
      doctor) _th_doctor; return $? ;;
      version) flag=--version ;;
      check) flag=--check-for-updates ;;
      update) flag=--update ;;
      *) print -u2 'Usage: terminal-helper version|check|update|doctor'; return 2 ;;
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

# Read widget names without evaluating bindkey output or exposing macro payloads.
_th_binding_widget() {
  local -a binding
  binding=( ${(z)"$(bindkey -M "$1" -L "$2" 2>/dev/null)"} )
  (( $#binding )) || { REPLY=unavailable; return 1; }
  (( ${binding[(Ie)-s]} )) && { REPLY=macro; return 1; }
  REPLY=${(Q)binding[-1]}
  (( ${+widgets[$REPLY]} ))
}

_th_doctor() {
  local base="$HOME/Library/Application Support/Terminal Helper" state_status='invalid or missing (helper disabled)'
  local app_status='unavailable; reinstall integration from the app' record app plist version map owner diag_status shortcut REPLY
  local -A info
  print -r -- "Terminal Helper integration: $_TH_INTEGRATION_VERSION"
  zmodload zsh/stat zsh/mapfile || { print -r -- 'Shell modules unavailable; restart zsh.'; return 1; }
  if [[ -d "$base" && ! -L "$base" && -O "$base" ]] &&
     zstat -H info -- "$base" 2>/dev/null && (( (info[mode] & 8#7777) == 8#700 )); then
    if [[ -f "$base/state" && ! -L "$base/state" && -O "$base/state" ]] &&
       zstat -H info -- "$base/state" 2>/dev/null &&
       (( (info[mode] & 8#7777) == 8#600 && (info[size] == 22 || info[size] == 23) )); then
      case "$mapfile[$base/state]" in
        $'terminal-helper-v1:on\n') state_status=On ;;
        $'terminal-helper-v1:off\n') state_status=Off ;;
      esac
    fi
    if [[ -f "$base/app-path" && ! -L "$base/app-path" && -O "$base/app-path" ]] &&
       zstat -H info -- "$base/app-path" 2>/dev/null &&
       (( (info[mode] & 8#7777) == 8#600 && info[size] > 1 && info[size] <= 4097 )); then
      record=$mapfile[$base/app-path]
      app=$record[1,-2]
      plist="$app/Contents/Info.plist"
      if [[ "$record" == "$app"$'\n' && "$app" == /*.app && "$app" != *[[:cntrl:]]* &&
            -d "$app" && ! -L "$app" && -f "$plist" && ! -L "$plist" ]] &&
         zstat -H info -- "$plist" 2>/dev/null && (( info[size] <= 65536 )); then
        # Fixed platform metadata reader; never run the recorded application or PATH tools.
        version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null)
        if [[ -n "$version" && ${#version} -le 40 && "$version" != *[^0-9.]* ]]; then
          app_status="$version (recorded app metadata)"
        fi
      fi
    fi
  fi
  print -r -- "Shared state: $state_status"
  print -r -- "App version: $app_status"
  local -a main_alias
  main_alias=( ${(z)"$(bindkey -l -L main 2>/dev/null)"} )
  if [[ "${(Q)main_alias[2]}" == -A ]]; then
    print -r -- "Main keymap: ${(qqqq)${(Q)main_alias[3]}}"
  else
    print -r -- 'Main keymap: custom (inspect with bindkey -l -L main)'
  fi
  for map in emacs viins; do
    if _th_binding_widget "$map" '^I'; then owner=$REPLY; else owner=$REPLY; fi
    diag_status=${_TH_MAP_STATUS[$map]:-not installed}
    if [[ "$diag_status" == integrated && "$owner" != "_th_tab_$map" ]]; then
      diag_status='conflict: a later binding owns Tab; left untouched'
    fi
    print -r -- "$map Tab: ${(qqqq)owner}; $diag_status"
    if _th_binding_widget "$map" '^X^P'; then
      if [[ "$REPLY" == undefined-key ]]; then
        shortcut=available
      else
        shortcut=${(qqqq)REPLY}
        [[ "$REPLY" == _th_python_* ]] || shortcut="$shortcut (existing binding; left untouched)"
      fi
    elif [[ "$REPLY" == macro ]]; then
      shortcut='macro (left untouched)'
    else
      shortcut=available
    fi
    print -r -- "$map Ctrl-X Ctrl-P: $shortcut"
  done
  print -r -- 'Off delegates your original Tab; it disables Terminal Helper corrections.'
  print -r -- 'To refresh bindings, open a new shell after loading completion plugins.'
  print -r -- 'To remove integration, use Settings > Remove Shell Integration, then open a new shell.'
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
  local map=${WIDGET#_th_tab_}
  if ! _th_enabled; then
    if (( _TH_ACTIVE )); then BUFFER=$_TH_ORIGINAL; CURSOR=$_TH_CURSOR; fi
    _TH_ACTIVE=0 _TH_CANCELLED=0 _TH_PREVIEW_SET=0
    _th_restore_menu
    zle "_th_original_tab_$map"
    return
  fi
  if ! _th_supported; then
    _TH_ACTIVE=0 _TH_CANCELLED=0 _TH_PREVIEW_SET=0
    _th_restore_menu
    zle "_th_original_tab_$map"
    return
  fi
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
  # Keep Up/Down useful even when native completion lays out matches in one row.
  # The native menuselect name is protected: change bindings, never replace its map.
  bindkey -N _th_user_menu menuselect
  bindkey -M menuselect '^M' _th_menu_accept
  bindkey -M menuselect '^J' _th_menu_accept
  bindkey -M menuselect '^I' menu-complete
  bindkey -M menuselect '^[[B' menu-complete
  bindkey -M menuselect '^[OB' menu-complete
  bindkey -M menuselect '^[[A' reverse-menu-complete
  bindkey -M menuselect '^[OA' reverse-menu-complete
  bindkey -M menuselect '^[' _th_cancel
  _TH_MENU_ACTIVE=1
  _TH_SELECTING=1
  {
    zle _th_completion
  } always {
    _TH_SELECTING=0
    _th_restore_menu
  }
  if (( _TH_ACTIVE )) && ! _th_enabled; then
    BUFFER=$_TH_ORIGINAL
    CURSOR=$_TH_CURSOR
    _TH_ACTIVE=0
    _TH_CANCELLED=1
  fi
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
  (( _TH_SELECTING )) && return 0
  if (( _TH_MENU_ACTIVE )); then
    local key REPLY
    local -a binding
    local -A expected
    expected=('^M' _th_menu_accept '^J' _th_menu_accept '^I' menu-complete
              '^[' _th_cancel '^[[B' menu-complete '^[OB' menu-complete
              '^[[A' reverse-menu-complete '^[OA' reverse-menu-complete)
    for key in '^M' '^J' '^I' '^[' '^[[B' '^[OB' '^[[A' '^[OA'; do
      # A plugin may have rebound a key during selection. Restore only our own binding.
      _th_binding_widget menuselect "$key" || continue
      [[ "$REPLY" == "${expected[$key]}" ]] || continue
      binding=( ${(z)"$(bindkey -M _th_user_menu -L "$key")"} )
      if (( ${binding[(Ie)-s]} )); then
        bindkey -M menuselect -s "${(@Q)binding[-2,-1]}"
      else
        bindkey -M menuselect "${(@Q)binding[-2,-1]}"
      fi
    done
    bindkey -D _th_user_menu
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
  zle .accept-line
}

_th_cancel() {
  if (( _TH_CANCELLED )); then _TH_CANCELLED=0; return 0; fi
  if (( _TH_ACTIVE )); then
    BUFFER=$_TH_ORIGINAL
    CURSOR=$_TH_CURSOR
    _TH_ACTIVE=0
    _th_restore_menu
    zle -M ''
  else
    zle send-break
  fi
}

_th_redraw() {
  (( _TH_SELECTING )) && return 0
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
  local map=${WIDGET#_th_return_}
  if (( _TH_ACTIVE || _TH_CANCELLED )); then _th_accept; else zle "_th_original_return_$map"; fi
}

_th_newline() {
  local map=${WIDGET#_th_newline_}
  if (( _TH_ACTIVE || _TH_CANCELLED )); then _th_accept; else zle "_th_original_newline_$map"; fi
}

_th_escape() {
  local map=${WIDGET#_th_escape_}
  if (( _TH_ACTIVE || _TH_CANCELLED )); then _th_cancel; else zle "_th_original_escape_$map"; fi
}

_th_line_finish() { _TH_ACTIVE=0; _TH_CANCELLED=0; _th_restore_menu; }

_th_menu_accept() {
  # A custom menu widget exits selection; never accept/execute the command here.
  (( _TH_ACTIVE || _TH_CANCELLED )) && _th_accept
  return 0
}

# Capture each supported map independently. Macros stay untouched rather than being replayed.
_th_install_bindings() {
  local map kind key REPLY
  local -A names keys
  keys=(tab '^I' return '^M' newline '^J' escape '^[')
  zle -N _th_accept
  zle -N _th_menu_accept
  zle -N _th_cancel
  for map in emacs viins; do
    names=()
    for kind key in "${(@kv)keys}"; do
      if ! _th_binding_widget "$map" "$key"; then
        _TH_MAP_STATUS[$map]="not installed: $kind binding is a macro or unsupported"
        break
      fi
      names[$kind]=$REPLY
    done
    (( ${#names} == 4 )) || continue
    # Never wrap one of our own widgets, even if a user copied a map before re-sourcing.
    if [[ "${names[tab]}" == _th_* ]]; then
      _TH_MAP_STATUS[$map]='not installed: helper binding already present'
      continue
    fi
    for kind key in "${(@kv)keys}"; do
      zle -A "${names[$kind]}" "_th_original_${kind}_$map"
      zle -N "_th_${kind}_$map" "_th_$kind"
      bindkey -M "$map" "$key" "_th_${kind}_$map"
    done
    _TH_TAB_NAMES[$map]=${names[tab]}
    _TH_MAP_STATUS[$map]=integrated
  done
}
_th_install_bindings
unfunction _th_install_bindings
