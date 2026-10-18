#!/bin/zsh -f
set -eu
umask 077
zmodload zsh/mapfile
base="$HOME/Library/Application Support/Terminal Helper"
config="${ZDOTDIR:-$HOME}/.zshrc"
[[ ! -L "$base" && ( ! -e "$base" || ( -d "$base" && -O "$base" ) ) ]] || exit 1
[[ -d "${config:h}" && -O "${config:h}" && ! -L "${config:h}" ]] || exit 1
/bin/mkdir -p -m 700 "$base"
/bin/chmod 700 "$base"
lock="$base/.integration-lock"
if ! /bin/mkdir -m 700 "$lock" 2>/dev/null; then
  print -u2 'Another integration operation is in progress. If none is running, remove the stale .integration-lock directory and retry.'
  exit 1
fi
tmp='' temp_config='' remove_empty_base=0
cleanup() {
  [[ -z "$tmp" ]] || /bin/rm -f -- "$tmp" 2>/dev/null || true
  [[ -z "$temp_config" ]] || /bin/rm -f -- "$temp_config" 2>/dev/null || true
  /bin/rmdir -- "$lock" 2>/dev/null || true
  (( ! remove_empty_base )) || /bin/rmdir -- "$base" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
[[ ! -L "$config" && ( ! -e "$config" || ( -f "$config" && -O "$config" ) ) ]] || exit 1
for owned in "$base/integration.zsh" "$base/state"; do
  [[ ! -L "$owned" && ( ! -e "$owned" || ( -f "$owned" && -O "$owned" ) ) ]] || exit 1
done
config_existed=0
[[ ! -f "$config" ]] || config_existed=1
replace_config() {
  local replacement=$1 backup
  if (( config_existed )); then
    [[ -w "$config" ]] || { print -u2 'Shell configuration is read-only; no changes made.'; return 1; }
    backup=$(/usr/bin/mktemp "$config.terminal-helper-backup.XXXXXX")
    /bin/cp -p "$config" "$backup"
  fi
  temp_config=$(/usr/bin/mktemp "$config.terminal-helper.XXXXXX")
  # Preserve existing permissions and ACLs instead of replacing them with temp-file defaults.
  (( ! config_existed )) || /bin/cp -p "$config" "$temp_config"
  print -rn -- "$replacement" > "$temp_config"
  if (( config_existed )); then
    [[ ! -L "$config" && -f "$config" && -O "$config" && "${mapfile[$config]}" == "$content" ]] || { print -u2 'Shell configuration changed during installation; retry.'; return 1; }
  else
    [[ ! -e "$config" && ! -L "$config" ]] || { print -u2 'Shell configuration appeared during installation; retry.'; return 1; }
  fi
  /bin/mv -f "$temp_config" "$config"
  temp_config=''
}
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
[[ -f "$source_file" && -r "$source_file" ]] || { print -u2 'Bundled integration missing'; exit 1; }
if [[ "$content" != *"$block"* ]]; then
  replace_config "$content$block"
fi
tmp=$(/usr/bin/mktemp "$base/.integration.XXXXXX")
/bin/cp "$source_file" "$tmp"
/bin/chmod 600 "$tmp"
/bin/mv -f "$tmp" "$base/integration.zsh"
tmp=''
if [[ ! -e "$base/state" ]]; then
  tmp=$(/usr/bin/mktemp "$base/.state.XXXXXX")
  print -r -- 'terminal-helper-v1:off' > "$tmp"
  /bin/mv "$tmp" "$base/state"
  tmp=''
fi
print 'Integration installed. Open a new interactive zsh. Suggestions remain Off until enabled.'
