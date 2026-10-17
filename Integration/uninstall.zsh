#!/bin/zsh -f
set -eu
umask 077
zmodload zsh/mapfile
base="$HOME/Library/Application Support/Terminal Helper"
config="${ZDOTDIR:-$HOME}/.zshrc"
[[ ! -L "$base" && ( ! -e "$base" || ( -d "$base" && -O "$base" ) ) ]] || exit 1
[[ -d "${config:h}" && -O "${config:h}" && ! -L "${config:h}" ]] || exit 1
[[ ! -L "$config" && ( ! -e "$config" || ( -f "$config" && -O "$config" ) ) ]] || exit 1
start='# >>> Terminal Helper managed integration >>>'
finish='# <<< Terminal Helper managed integration <<<'
block=$'\n# >>> Terminal Helper managed integration >>>\n[[ -o interactive && -f "$HOME/Library/Application Support/Terminal Helper/integration.zsh" && ! -L "$HOME/Library/Application Support/Terminal Helper/integration.zsh" ]] && source "$HOME/Library/Application Support/Terminal Helper/integration.zsh"\n# <<< Terminal Helper managed integration <<<\n'
content=''
[[ ! -f "$config" ]] || content=${mapfile[$config]}
if [[ "$content" == *"$start"* || "$content" == *"$finish"* ]]; then
  [[ "$content" == *"$block"* ]] || { print -u2 'Incomplete managed block: restore backup before continuing'; exit 1; }
  rest=${content//"$block"/}
  [[ "$rest" != *"$start"* && "$rest" != *"$finish"* ]] || { print -u2 'Duplicate managed blocks: restore backup'; exit 1; }
fi

if [[ "$content" == *"$block"* ]]; then
  backup=$(/usr/bin/mktemp "$config.terminal-helper-backup.XXXXXX")
  cp -p "$config" "$backup"
  temp_config=$(/usr/bin/mktemp "$config.terminal-helper.XXXXXX")
  trap 'rm -f -- "$temp_config"' EXIT
  print -rn -- "${content//"$block"/}" > "$temp_config"
  chmod "$(/usr/bin/stat -f %Lp "$config")" "$temp_config"
  mv -f "$temp_config" "$config"
fi
[[ ! -L "$base/integration.zsh" && ! -L "$base/state" ]] || exit 1
rm -f -- "$base/integration.zsh" "$base/state"
# Missing state disables widgets retained in already-open shells.
[[ ! -d "$base" ]] || rmdir "$base" 2>/dev/null || true
print 'Integration removed. Restart open shells to restore their original keybindings.'
