#!/usr/bin/env bash
# Link MenuBar Overload into the Omarchy plugin directory and, with --use,
# make it the active bar. Idempotent. Undo with:  omarchy bar use <previous-bar-id>
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugins="$HOME/.config/omarchy/plugins"
id=nixfred.menubar-overload
mkdir -p "$plugins"

target="$plugins/$id"
if [[ -L $target ]]; then
  [[ $(readlink -f "$target") == "$here/$id" ]] || { echo "refusing: $target links elsewhere ($(readlink "$target"))" >&2; exit 1; }
elif [[ -e $target ]]; then
  echo "refusing: $target exists and is not a symlink" >&2; exit 1
else
  ln -s "$here/$id" "$target"
  echo "linked $target"
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 1
if omarchy plugin list 2>/dev/null | grep -q "^$id "; then
  echo "plugin discovered"
else
  echo "plugin scan did not pick up $id; is the shell running?" >&2; exit 1
fi

if [[ ${1:-} == "--use" ]]; then
  if command -v omarchy-shell-config-edit >/dev/null 2>&1; then
    # A host with the compare-and-set config store rejects direct file
    # writes, so switch the bar through its snapshot/apply path.
    base=$(mktemp); edited=$(mktemp)
    omarchy-shell-config-edit snapshot "$base" >/dev/null
    jq --arg id "$id" '.bar.id = $id' "$base" >"$edited"
    omarchy-shell-config-edit apply --allow-layout-change "$base" "$edited"
    rm -f "$base" "$edited"
  else
    omarchy bar use "$id"
  fi
  echo "MenuBar Overload is the active bar. Try: $here/bin/menubar-overload"
fi
