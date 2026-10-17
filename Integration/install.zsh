#!/bin/zsh -f
set -eu
umask 077
base="$HOME/Library/Application Support/Terminal Helper"
config="${ZDOTDIR:-$HOME}/.zshrc"
source_file="${0:A:h}/terminal-helper.zsh"
[[ -r "$source_file" ]] || { print -u2 'Bundled integration missing'; exit 1; }
[[ ! -L "$base" && ( ! -e "$base" || ( -d "$base" && -O "$base" ) ) ]] || exit 1
[[ -d "${config:h}" && -O "${config:h}" && ! -L "${config:h}" ]] || exit 1
[[ ! -L "$config" && ( ! -e "$config" || ( -f "$config" && -O "$config" ) ) ]] || exit 1
mkdir -p -m 700 "$base"
chmod 700 "$base"
[[ ! -L "$base/integration.zsh" && ! -L "$base/state" ]] || exit 1
start='# >>> Terminal Helper managed integration >>>'
finish='# <<< Terminal Helper managed integration <<<'
block=$'\n# >>> Terminal Helper managed integration >>>\n[[ -o interactive && -f "$HOME/Library/Application Support/Terminal Helper/integration.zsh" && ! -L "$HOME/Library/Application Support/Terminal Helper/integration.zsh" ]] && source "$HOME/Library/Application Support/Terminal Helper/integration.zsh"\n# <<< Terminal Helper managed integration <<<\n'
if [[ -f "$config" ]]; then
  content=$(<"$config")
  if [[ "$content" == *"$start"* || "$content" == *"$finish"* ]]; then
    [[ "$content" == *"$start"*"$finish"* ]] || { print -u2 'Incomplete managed block: restore backup before reinstall'; exit 1; }
  else
    cp -p "$config" "$config.terminal-helper-backup.$EPOCHREALTIME.$$"
    print -rn -- "$block" >> "$config"
  fi
else
  print -rn -- "$block" > "$config"
fi
tmp="$base/.integration.$$"
trap 'rm -f -- "$tmp"' EXIT
cp "$source_file" "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$base/integration.zsh"
if [[ ! -e "$base/state" ]]; then
  print -r -- 'terminal-helper-v1:off' > "$base/.state.$$"
  chmod 600 "$base/.state.$$"
  mv "$base/.state.$$" "$base/state"
fi
print 'Integration installed. Open a new interactive zsh. Suggestions remain Off until enabled.'
