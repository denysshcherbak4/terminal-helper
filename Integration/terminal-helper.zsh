# Sourced by the explicitly installed interactive zsh integration.
[[ -o interactive ]] || return 0
(( ${+_TH_LOADED} )) && return 0
typeset -gr _TH_INTEGRATION_VERSION=0.4.0
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

  done
  (( ${+functions[_th_python_doctor]} )) && _th_python_doctor
  print -r -- 'Off delegates your original Tab; it disables Terminal Helper corrections.'
  print -r -- 'While On, unsupported input declines native expansion widgets; custom widget behavior remains yours.'
  print -r -- 'To refresh bindings, open a new shell after loading completion plugins.'
  print -r -- 'To remove integration, use Settings > Uninstall shell integration…, then open a new shell.'
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
    # Native expansion widgets can execute command substitutions on Tab.
    # Decline unsupported input while On instead of introducing that side effect.
    case "${_TH_TAB_NAMES[$map]#.}" in
      expand-or-complete|expand-or-complete-prefix|menu-expand-or-complete|expand-word|list-expand)
        zle -M 'Terminal Helper: unsupported input; expanding Tab action declined'
        return 0 ;;
    esac
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

# Explicit, current-directory Python context check. Never executes discovered code.
[[ -o interactive ]] || return 0
(( ${+_TH_PY_LOADED} )) && return 0
typeset -g _TH_PY_LOADED=1 _TH_PY_ACTIVE=0 _TH_PY_HOOKS=0
typeset -g _TH_PY_STATUS=unsupported _TH_PY_MESSAGE='' _TH_PY_SUGGESTION='' _TH_PY_SIGNATURE=''
typeset -g _TH_PY_BUFFER='' _TH_PY_SAVED_SIGNATURE='' _TH_PY_SAVED_SUGGESTION='' _TH_PY_MAP='' _TH_PY_PENDING_MAP=''
typeset -g _TH_PY_CURSOR=0 _TH_PY_HEAD_LENGTH=0 _TH_PY_NEW_HEAD_LENGTH=0 _TH_PY_SHORTCUT_STATUS=''

_th_python_stamp() {
  local -A info
  if [[ "$2" == link ]]; then
    zstat -L -H info -- "$1" 2>/dev/null || return 1
  else
    zstat -H info -- "$1" 2>/dev/null || return 1
  fi
  _TH_PY_PART="${info[device]}:${info[inode]}:${info[mode]}:${info[size]}:${info[mtime]}:${info[ctime]}"
}

_th_python_read_cfg() {
  local cfg_file=$1 cfg_fd cfg_count cfg_text cfg_line cfg_key cfg_value no_lines before
  local -A info after fields
  # sysopen can reject multibyte absolute filenames on the supported zsh.
  # Open only this fixed ASCII relative candidate; fd/path identity is checked below.
  [[ "$cfg_file" == "${PWD:a}/.venv/pyvenv.cfg" ]] || return 1
  sysopen -r -o cloexec,nofollow,nonblock -u cfg_fd ./.venv/pyvenv.cfg 2>/dev/null || return 1
  {
    zstat -H info -f "$cfg_fd" 2>/dev/null || return 1
    (( (info[mode] & 8#170000) == 8#100000 && info[size] > 0 && info[size] <= 4096 )) || return 1
    before="${info[device]}:${info[inode]}:${info[size]}:${info[mtime]}:${info[ctime]}"
    sysread -i "$cfg_fd" -s 4097 -c cfg_count cfg_text 2>/dev/null || return 1
    (( cfg_count == info[size] && cfg_count <= 4096 )) || return 1
    zstat -H after -f "$cfg_fd" 2>/dev/null || return 1
    [[ "$before" == "${after[device]}:${after[inode]}:${after[size]}:${after[mtime]}:${after[ctime]}" ]] || return 1
    no_lines=${cfg_text//$'\n'/}
    [[ "$no_lines" != *[[:cntrl:]]* ]] || return 1
    for cfg_line in "${(@f)cfg_text}"; do
      cfg_line=${cfg_line##[ ]#}; cfg_line=${cfg_line%%[ ]#}
      [[ -z "$cfg_line" || "$cfg_line" == \#* ]] && continue
      [[ "$cfg_line" == *=* ]] || return 1
      cfg_key=${cfg_line%%=*}; cfg_key=${cfg_key%%[ ]#}
      cfg_value=${cfg_line#*=}; cfg_value=${cfg_value##[ ]#}
      [[ "$cfg_key" == [a-z][a-z0-9_-]# && -n "$cfg_value" && "$cfg_value" != *[^[:print:]]* ]] || return 1
      (( ! ${+fields[$cfg_key]} )) || return 1
      fields[$cfg_key]=$cfg_value
    done
    [[ "${fields[home]-}" == /* && "${fields[version]-}" == <1->.<0->.<0-> &&
       ( "${fields[include-system-site-packages]-}" == true || "${fields[include-system-site-packages]-}" == false ) ]] || return 1
    # Bind the read bytes to the still-current non-symlink path as well as the open fd.
    [[ ! -L "$cfg_file" ]] || return 1
    zstat -H after -- "$cfg_file" 2>/dev/null || return 1
    [[ "$before" == "${after[device]}:${after[inode]}:${after[size]}:${after[mtime]}:${after[ctime]}" ]] || return 1
    _TH_PY_CFG_SIGNATURE="$before:$cfg_text"
  } always {
    exec {cfg_fd}<&-
  }
}

_th_python_inspect() {
  emulate -L zsh
  setopt extendedglob
  local raw=$1 ch quote_mode=plain escaped=0 index forbidden cmd prefix_count rest leading token decoded option blocked kind resolved env_dir interpreter sibling
  local -a tokens
  _TH_PY_STATUS=unsupported _TH_PY_MESSAGE='Only simple pip install or python -m pip install input is supported; unchanged.'
  _TH_PY_SUGGESTION='' _TH_PY_SIGNATURE='' _TH_PY_CFG_SIGNATURE=''
  _th_enabled || { _TH_PY_MESSAGE='Suggestions are Off; Python context was not inspected.'; return 0; }
  (( ${#raw} > 0 && ${#raw} <= 4096 )) || return 0
  [[ "$raw" != *[[:cntrl:]]* && "$PWD" != *[[:cntrl:]]* && ${#PWD} -le 512 ]] || return 0
  for forbidden in '$' '`' '*' '?' '[' ']' '{' '}' ';' '|' '&' '<' '>' '(' ')' '!'; do
    [[ "$raw" != *"$forbidden"* ]] || return 0
  done
  # Only balance quotes/escapes here; zsh, not a shell parser, owns tokenization.
  for (( index=1; index <= ${#raw}; index++ )); do
    ch=$raw[index]
    if (( escaped )); then escaped=0; continue; fi
    if [[ "$quote_mode" != single && "$ch" == $'\\' ]]; then escaped=1; continue; fi
    if [[ "$quote_mode" == single ]]; then
      [[ "$ch" == "'" ]] && quote_mode=plain
    elif [[ "$quote_mode" == double ]]; then
      [[ "$ch" == '"' ]] && quote_mode=plain
    else
      [[ "$ch" == "'" ]] && quote_mode=single
      [[ "$ch" == '"' ]] && quote_mode=double
    fi
  done
  [[ "$quote_mode" == plain && "$escaped" == 0 ]] || return 0
  tokens=( "${(@z)raw}" )
  (( ${#tokens} >= 3 && ${#tokens} <= 128 )) || return 0
  cmd=$tokens[1]
  if [[ ( "$cmd" == pip || "$cmd" == pip3 ) && "$tokens[2]" == install ]]; then
    prefix_count=2
  elif [[ ( "$cmd" == python || "$cmd" == python3 ) && "$tokens[2]" == -m && "$tokens[3]" == pip && "$tokens[4]" == install && ${#tokens} -ge 5 ]]; then
    prefix_count=4
  else
    return 0
  fi
  for token in "${tokens[@]:$prefix_count}"; do
    decoded=${(Q)token}
    # pip accepts abbreviated long options and clustered short options. Decline
    # these targeting spellings conservatively instead of reproducing its parser.
    if [[ "$decoded" == --?* ]]; then
      option=${decoded%%=*}
      for blocked in --target --prefix --root --python --user --platform --python-version --implementation --abi; do
        if [[ "$blocked" == "$option"* ]]; then
          _TH_PY_MESSAGE='A pip target/runtime option or abbreviation is present; unchanged.'; return 0
        fi
      done
    elif [[ "$decoded" == -[^-]?* ]]; then
      _TH_PY_MESSAGE='Clustered short options or attached option values are unsupported; unchanged.'; return 0
    fi
    case "$decoded" in
      --target|--target=*|-t|-t?*|--prefix|--prefix=*|--root|--root=*|--python|--python=*|--user|--platform|--platform=*|--python-version|--python-version=*|--implementation|--implementation=*|--abi|--abi=*)
        _TH_PY_MESSAGE='Explicit pip target/runtime options are present; context is not inferred.'; return 0 ;;
    esac
  done
  if [[ -n ${SSH_CONNECTION-}${SSH_CLIENT-}${SSH_TTY-}${REMOTE_CONTAINERS-}${DEVCONTAINER-}${CODESPACES-}${VSCODE_REMOTE_NAME-}${CONTAINER-}${container-}${KUBERNETES_SERVICE_HOST-}${WSL_DISTRO_NAME-} ]]; then
    _TH_PY_MESSAGE='A remote/container context marker is present; local metadata is insufficient.'; return 0
  fi
  if [[ -n ${PIP_TARGET-}${PIP_PREFIX-}${PIP_ROOT-}${PIP_USER-}${PIP_CONFIG_FILE-}${PIP_PYTHON-}${PIP_REQUIRE_VIRTUALENV-}${PYTHONHOME-}${PYTHONPATH-} ]]; then
    _TH_PY_MESSAGE='A pip/Python environment override is present; no context rewrite is proposed.'; return 0
  fi
  env_dir="${PWD:a}/.venv"
  if [[ -n ${CONDA_PREFIX-}${CONDA_DEFAULT_ENV-} || ( -n ${VIRTUAL_ENV-} && "${VIRTUAL_ENV:a}" != "$env_dir" ) ]]; then
    _TH_PY_STATUS=ambiguous _TH_PY_MESSAGE='Another environment is active; no environment is chosen.'; return 0
  fi
  for sibling in venv env; do
    if [[ -L "$PWD/$sibling" || -f "$PWD/$sibling/pyvenv.cfg" || -x "$PWD/$sibling/bin/python" ]]; then
      _TH_PY_STATUS=ambiguous _TH_PY_MESSAGE='Another environment-shaped venv/env entry exists here; choose explicitly.'; return 0
    fi
  done
  [[ ! -L "$env_dir" && ! -L "$env_dir/bin" ]] || { _TH_PY_STATUS=invalid _TH_PY_MESSAGE='The project environment directory is a symlink; not inspected.'; return 0; }
  [[ -d "$env_dir" && -e "$env_dir/pyvenv.cfg" ]] || { _TH_PY_STATUS=missing _TH_PY_MESSAGE='No supported .venv metadata exists in the current directory; no upward search was made.'; return 0; }
  zmodload zsh/stat zsh/system || { _TH_PY_MESSAGE='Required native zsh modules are unavailable; unchanged.'; return 0; }
  _th_python_read_cfg "$env_dir/pyvenv.cfg" || { _TH_PY_STATUS=invalid _TH_PY_MESSAGE='Project pyvenv.cfg is unsafe, malformed, changed, or larger than 4096 bytes.'; return 0; }
  interpreter="$env_dir/bin/python"
  [[ -f "$interpreter" && -x "$interpreter" ]] || { _TH_PY_STATUS=missing _TH_PY_MESSAGE='The project interpreter entry is missing or not executable; runtime was not tested.'; return 0; }
  kind=$(builtin whence -w -- "$cmd" 2>/dev/null)
  [[ "$kind" == "${cmd}: command" || "$kind" == "${cmd}: hashed" ]] || {
    if [[ "$kind" == "${cmd}: none" || -z "$kind" ]]; then
      _TH_PY_STATUS=missing _TH_PY_MESSAGE='The requested command does not resolve in this shell; unchanged.'
    else
      _TH_PY_MESSAGE='The requested command is an alias, function, builtin, or wrapper prefix; unchanged.'
    fi
    return 0
  }
  resolved=$(builtin whence -- "$cmd" 2>/dev/null)
  [[ -n "$resolved" && ${#resolved} -le 512 && "$resolved" != *[[:cntrl:]]* && -f "$resolved" && -x "$resolved" ]] || return 0
  kind=$(builtin whence -w -- "$interpreter" 2>/dev/null)
  [[ "$kind" == *': command' || "$kind" == *': hashed' ]] || return 0
  _TH_PY_SIGNATURE=$_TH_PY_CFG_SIGNATURE
  for token in "$PWD" "$env_dir" "$interpreter" "$resolved"; do
    _th_python_stamp "$token" link || { _TH_PY_STATUS=invalid; return 0; }
    _TH_PY_SIGNATURE+="|$_TH_PY_PART"
    _th_python_stamp "$token" target || { _TH_PY_STATUS=invalid; return 0; }
    _TH_PY_SIGNATURE+="|$_TH_PY_PART"
  done
  _TH_PY_SIGNATURE+="|${resolved:a}|${PWD:a}"
  if [[ "${resolved:a:h}" == "$env_dir/bin" ]]; then
    _TH_PY_STATUS=match
    _TH_PY_MESSAGE="Shell resolution uses the project .venv entry ${(qq)resolved}. Metadata/runtime health, executable identity and pip configuration are not validated."
    return 0
  fi
  rest=$raw
  leading=${raw%%[^ ]*}
  for (( index=1; index <= prefix_count; index++ )); do
    rest=${rest##[ ]#}
    [[ "$rest" == "$tokens[index]"* ]] || return 0
    rest=${rest#"$tokens[index]"}
  done
  _TH_PY_HEAD_LENGTH=$(( ${#raw} - ${#rest} ))
  _TH_PY_SUGGESTION="$leading${(qq)interpreter} -m pip install$rest"
  _TH_PY_NEW_HEAD_LENGTH=$(( ${#_TH_PY_SUGGESTION} - ${#rest} ))
  _TH_PY_STATUS=suggestion
  if (( ${#_TH_PY_SUGGESTION} > 2048 )); then
    _TH_PY_STATUS=unsupported _TH_PY_SUGGESTION=''
    _TH_PY_MESSAGE='The proposed command is too long for a compact safe preview; unchanged.'; return 0
  fi
  _TH_PY_MESSAGE="Resolved: $cmd -> ${(qq)resolved}"$'\n'"Project candidate: ${(qq)env_dir} (pyvenv.cfg + executable entry)"$'\n''Mismatch: shell resolution is outside the project candidate.'$'\n''Interpreter selection only; runtime health, executable identity and pip configuration are not validated.'
}

_th_python_restore() {
  local saved=$_TH_PY_MAP pending=$_TH_PY_PENDING_MAP
  _TH_PY_ACTIVE=0 _TH_PY_PENDING_MAP='' _TH_PY_MAP=''
  [[ -n "$saved" ]] && { zle -K "$saved" 2>/dev/null || zle -K main 2>/dev/null; }
  [[ -n "$pending" ]] && bindkey -D "$pending" 2>/dev/null
  _TH_PY_SAVED_SIGNATURE='' _TH_PY_SAVED_SUGGESTION=''
}

_th_python_check() {
  emulate -L zsh
  (( _TH_PY_ACTIVE )) && { _th_python_dismiss; return 0; }
  _th_enabled || { zle -M 'Terminal Helper: Off; Python context was not inspected.'; return 0; }
  if (( ${_TH_ACTIVE:-0} || ${_TH_SELECTING:-0} )) || [[ "$KEYMAP" == menuselect ]]; then
    zle -M 'Dismiss the completion menu before checking Python context.'; return 0
  fi
  _th_python_inspect "$BUFFER"
  if [[ "$_TH_PY_STATUS" != suggestion ]]; then zle -M "$_TH_PY_MESSAGE"; return 0; fi
  if (( ! _TH_PY_HOOKS )); then
    autoload -Uz add-zle-hook-widget
    add-zle-hook-widget line-pre-redraw _th_python_redraw
    add-zle-hook-widget line-finish _th_python_line_finish
    _TH_PY_HOOKS=1
  fi
  _TH_PY_BUFFER=$BUFFER _TH_PY_CURSOR=$CURSOR _TH_PY_MAP=$KEYMAP
  _TH_PY_SAVED_SIGNATURE=$_TH_PY_SIGNATURE _TH_PY_SAVED_SUGGESTION=$_TH_PY_SUGGESTION
  _TH_PY_PENDING_MAP="_th_python_pending_$$_$RANDOM"
  if bindkey -M "$_TH_PY_PENDING_MAP" >/dev/null 2>&1 || ! bindkey -N "$_TH_PY_PENDING_MAP" "$_TH_PY_MAP"; then
    _TH_PY_PENDING_MAP='' _TH_PY_MAP=''; zle -M 'Temporary keymap is unavailable; input unchanged.'; return 0
  fi
  bindkey -M "$_TH_PY_PENDING_MAP" '^M' _th_python_insert
  bindkey -M "$_TH_PY_PENDING_MAP" '^J' _th_python_insert
  bindkey -M "$_TH_PY_PENDING_MAP" '^[' _th_python_dismiss
  bindkey -M "$_TH_PY_PENDING_MAP" '^I' _th_python_delegate_tab
  _TH_PY_ACTIVE=1
  zle -K "$_TH_PY_PENDING_MAP"
  zle -M "$_TH_PY_MESSAGE"$'\n'"Proposed: $_TH_PY_SUGGESTION"$'\n''Enter: Insert text | Escape: Dismiss'
}

_th_python_insert() {
  emulate -L zsh
  local original=$_TH_PY_BUFFER original_cursor=$_TH_PY_CURSOR signature=$_TH_PY_SAVED_SIGNATURE proposal=$_TH_PY_SAVED_SUGGESTION next_cursor
  (( _TH_PY_ACTIVE )) || return 0
  if [[ "$BUFFER" != "$original" || "$CURSOR" != "$original_cursor" ]]; then _th_python_restore; zle -M ''; return 0; fi
  if ! _th_enabled; then _th_python_restore; zle -M 'Terminal Helper: Off; input unchanged.'; return 0; fi
  _th_python_inspect "$original"
  if [[ "$_TH_PY_STATUS" != suggestion || "$_TH_PY_SIGNATURE" != "$signature" || "$_TH_PY_SUGGESTION" != "$proposal" ]]; then
    _th_python_restore; zle -M 'Python context changed; check again. Input unchanged.'; return 0
  fi
  if (( original_cursor >= _TH_PY_HEAD_LENGTH )); then
    next_cursor=$(( original_cursor + _TH_PY_NEW_HEAD_LENGTH - _TH_PY_HEAD_LENGTH ))
  else
    next_cursor=$_TH_PY_NEW_HEAD_LENGTH
  fi
  _th_python_restore
  BUFFER=$proposal CURSOR=$next_cursor
  zle -M 'Inserted only. Review the command; execution requires another deliberate Enter.'
}

_th_python_dismiss() {
  local original=$_TH_PY_BUFFER original_cursor=$_TH_PY_CURSOR
  (( _TH_PY_ACTIVE )) || return 0
  _th_python_restore
  BUFFER=$original CURSOR=$original_cursor
  zle -M ''
}

_th_python_delegate_tab() {
  local -a binding
  binding=( ${(z)"$(bindkey -M "$_TH_PY_MAP" -L '^I')"} )
  _th_python_restore
  if (( ${binding[(Ie)-s]} )); then
    zle -U "${(Q)binding[-1]}"
  elif (( ${+widgets[${(Q)binding[-1]}]} )); then
    zle "${(Q)binding[-1]}"
  fi
}

_th_python_redraw() {
  (( _TH_PY_ACTIVE )) || return 0
  if [[ "$BUFFER" != "$_TH_PY_BUFFER" || "$CURSOR" != "$_TH_PY_CURSOR" ]] || ! _th_enabled; then
    _th_python_restore
    zle -M ''
  fi
}
_th_python_line_finish() { (( _TH_PY_ACTIVE )) && _th_python_restore; return 0; }

# Read bindings only; never include arbitrary macro payloads in diagnostics.
_th_python_shortcut_status() {
  emulate -L zsh
  local map=$1 entry part kind conflict=0
  local -a binding fields
  REPLY=unavailable
  bindkey -M "$map" >/dev/null 2>&1 || return 0
  binding=( ${(z)"$(bindkey -M "$map" -L '^X^P')"} )
  kind=${(Q)binding[-1]}
  (( ${binding[(Ie)-s]} )) && conflict=1
  [[ "$kind" == undefined-key || "$kind" == _th_python_check ]] || conflict=1
  binding=( ${(z)"$(bindkey -M "$map" -L '^X')"} )
  (( ${binding[(Ie)-s]} )) && conflict=1
  [[ "${(Q)binding[-1]}" == undefined-key ]] || conflict=1
  for entry in "${(@f)$(bindkey -M "$map" -L)}"; do
    fields=( ${(z)entry} )
    for part in "${(@Q)fields}"; do
      [[ "$part" == '^X^P'?* ]] && conflict=1
    done
  done
  if (( conflict )); then REPLY=conflict
  elif [[ "$kind" == _th_python_check ]]; then REPLY=installed
  else REPLY=available
  fi
}

_th_python_register_shortcut() {
  emulate -L zsh
  local map REPLY
  _TH_PY_SHORTCUT_STATUS=''
  for map in emacs viins; do
    _th_python_shortcut_status "$map"
    if [[ "$REPLY" == available ]]; then
      bindkey -M "$map" '^X^P' _th_python_check
      REPLY=installed
    fi
    _TH_PY_SHORTCUT_STATUS+="$map:$REPLY "
  done
}

_th_python_doctor() {
  emulate -L zsh
  local map REPLY
  for map in emacs viins; do
    _th_python_shortcut_status "$map"
    case "$REPLY" in
      installed) print -r -- "Python check Ctrl-X Ctrl-P ($map): installed" ;;
      conflict) print -r -- "Python check Ctrl-X Ctrl-P ($map): binding/prefix conflict; user bindings left untouched" ;;
      available) print -r -- "Python check Ctrl-X Ctrl-P ($map): not installed; currently free" ;;
      *) print -r -- "Python check Ctrl-X Ctrl-P ($map): keymap unavailable" ;;
    esac
  done
}
zle -N _th_python_check
zle -N _th_python_insert
zle -N _th_python_dismiss
zle -N _th_python_delegate_tab
_th_python_register_shortcut
