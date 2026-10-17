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

source_file="${0:A:h}/terminal-helper.zsh"
[[ -r "$source_file" ]] || { print -u2 'Bundled integration missing'; exit 1; }
mkdir -p -m 700 "$base"
chmod 700 "$base"
[[ ! -L "$base/integration.zsh" && ! -L "$base/state" ]] || exit 1
if [[ "$content" != *"$block"* ]]; then
  if [[ -f "$config" ]]; then
    backup=$(/usr/bin/mktemp "$config.terminal-helper-backup.XXXXXX")
    cp -p "$config" "$backup"
  fi
  temp_config=$(/usr/bin/mktemp "$config.terminal-helper.XXXXXX")
  print -rn -- "$content$block" > "$temp_config"
  [[ ! -f "$config" ]] || chmod "$(/usr/bin/stat -f %Lp "$config")" "$temp_config"
  mv -f "$temp_config" "$config"
fi
tmp=$(/usr/bin/mktemp "$base/.integration.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
cp "$source_file" "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$base/integration.zsh"
if [[ ! -e "$base/state" ]]; then
  tmp=$(/usr/bin/mktemp "$base/.state.XXXXXX")
  print -r -- 'terminal-helper-v1:off' > "$tmp"
  mv "$tmp" "$base/state"
fi
print 'Integration installed. Open a new interactive zsh. Suggestions remain Off until enabled.'
