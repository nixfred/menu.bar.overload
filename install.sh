#!/usr/bin/env bash
# MenuBar Overload installer.
#   install.sh           link the plugin into ~/.config/omarchy/plugins
#   install.sh --use     ...and make it the active bar
#   install.sh --boot    ...and install a login-time safety net (systemd user
#                        unit) that re-links it and re-selects it if either
#                        was lost, so it is always there after a reboot
#   install.sh --ensure  what the safety net runs: quiet, idempotent
# The bar itself needs no daemon: omarchy-shell loads whatever shell.json
# names as the bar at session start. Undo with:  omarchy bar use <previous-id>
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugins="$HOME/.config/omarchy/plugins"
config="$HOME/.config/omarchy/shell.json"
id=nixfred.menubar-overload
mode=${1:-}
quiet=0; [[ $mode == --ensure ]] && quiet=1
say() { (( quiet )) || echo "$*"; }

mkdir -p "$plugins"
target="$plugins/$id"
if [[ -L "$target" ]]; then
  [[ $(readlink -f "$target") == "$(readlink -f "$here/$id")" ]] || { echo "refusing: $target links elsewhere ($(readlink "$target"))" >&2; exit 1; }
elif [[ -e "$target" ]]; then
  echo "refusing: $target exists and is not a symlink" >&2; exit 1
else
  ln -s "$here/$id" "$target"
  say "linked $target"
fi

shell_up() { omarchy-shell shell ping >/dev/null 2>&1; }

select_bar() {
  local current
  if [[ ! -s "$config" ]]; then
    # No user config yet: start from Omarchy's defaults so the shell has a
    # complete file to read.
    local defaults="${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json"
    [[ -s $defaults ]] || { echo "no shell.json and no defaults at $defaults" >&2; exit 1; }
    mkdir -p "$(dirname "$config")"
    cp "$defaults" "$config"
  fi
  current=$(jq -r '.bar.id // ""' "$config" 2>/dev/null) || { echo "$config is not valid JSON; not touching it" >&2; exit 1; }
  [[ $current == "$id" ]] && { say "$id is already the active bar"; return 0; }
  if shell_up && command -v omarchy-shell-config-edit >/dev/null 2>&1; then
    # A host with the compare-and-set config store rejects direct file
    # writes, so switch the bar through its snapshot/apply path.
    local base edited; base=$(mktemp); edited=$(mktemp)
    if ! omarchy-shell-config-edit snapshot "$base" >/dev/null \
       || ! jq --arg id "$id" '.bar.id = $id' "$base" >"$edited" \
       || ! omarchy-shell-config-edit apply --allow-layout-change "$base" "$edited" >/dev/null; then
      rm -f "$base" "$edited"
      echo "could not switch the bar through omarchy shell config-edit" >&2; exit 1
    fi
    rm -f "$base" "$edited"
  elif shell_up; then
    omarchy bar use "$id" >/dev/null || { echo "omarchy bar use failed" >&2; exit 1; }
  else
    # No shell running (login-time): edit the file it will read on start.
    local tmp; tmp=$(mktemp)
    if ! jq --arg id "$id" '.bar.id = $id' "$config" >"$tmp"; then
      rm -f "$tmp"; echo "could not edit $config" >&2; exit 1
    fi
    mv "$tmp" "$config"
  fi
  say "$id is now the active bar"
}

case $mode in
  "")
    if shell_up; then
      omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
      sleep 1
      omarchy plugin list 2>/dev/null | grep -q "^$id " && say "plugin discovered" || say "plugin linked; the shell will discover it on restart"
    fi ;;
  --use)
    select_bar
    say "Try: $here/bin/menubar-overload" ;;
  --ensure)
    select_bar ;;
  --boot)
    select_bar
    unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir"
    cat >"$unit_dir/menubar-overload.service" <<UNIT
[Unit]
Description=MenuBar Overload: keep the carousel bar linked and selected
After=graphical-session.target

[Service]
Type=oneshot
ExecStart="${here//%/%%}/install.sh" --ensure

[Install]
WantedBy=graphical-session.target
UNIT
    systemctl --user daemon-reload
    systemctl --user enable menubar-overload.service >/dev/null 2>&1
    say "installed menubar-overload.service (runs at login; enabled)"
    systemctl --user start menubar-overload.service && say "safety net ran once now: ok" ;;
  *) echo "usage: install.sh [--use|--boot|--ensure]" >&2; exit 2 ;;
esac
