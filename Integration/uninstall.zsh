#!/bin/zsh -f
set -eu
umask 077
base="$HOME/Library/Application Support/Terminal Helper"
config="${ZDOTDIR:-$HOME}/.zshrc"
[[ ! -L "$base" && ( ! -e "$base" || ( -d "$base" && -O "$base" ) ) ]] || exit 1
[[ ! -L "$config" && ( ! -e "$config" || ( -f "$config" && -O "$config" ) ) ]] || exit 1
# Disable open shells first. They retain only inert widgets until their next startup.
if [[ -d "$base" ]]; then
  [[ ! -L "$base/state" ]] || exit 1
  print -r -- 'terminal-helper-v1:off' > "$base/.state.$$"
  chmod 600 "$base/.state.$$"
  mv -f "$base/.state.$$" "$base/state"
fi
if [[ -f "$config" ]]; then
  local_start='# >>> Terminal Helper managed integration >>>'
  local_end='# <<< Terminal Helper managed integration <<<'
  starts=0 ends=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$local_start" ]] && (( ++starts ))
    [[ "$line" == "$local_end" ]] && (( ++ends ))
  done < "$config"
  (( starts == ends && starts <= 1 )) || { print -u2 'Incomplete/duplicate managed block: restore backup before uninstall'; exit 1; }
  if (( starts )); then
    cp -p "$config" "$config.terminal-helper-backup.$EPOCHREALTIME.$$"
    temp_config="$config.terminal-helper.$$"
    trap 'rm -f -- "$temp_config"' EXIT
    # awk streams unrelated lines without interpreting shell content.
    /usr/bin/awk '$0 == "# >>> Terminal Helper managed integration >>>" {skip=1; next} $0 == "# <<< Terminal Helper managed integration <<<" {skip=0; next} !skip {print}' "$config" > "$temp_config"
    chmod 600 "$temp_config"
    mv -f "$temp_config" "$config"
  fi
fi
[[ ! -L "$base/integration.zsh" ]] || exit 1
rm -f -- "$base/integration.zsh"
# Retain private Off state while already-open integrated shells may still be alive.
print 'Integration removed. Restart open shells to restore their original keybindings. Private Off state remains safe to delete.'
