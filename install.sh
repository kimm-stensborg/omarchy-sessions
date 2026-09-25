#!/bin/bash

# Enable Sessions and bind a key to it.
#
#   ./install.sh                 pick a shortcut interactively
#   ./install.sh --key "SUPER + ALT + S"
#   ./install.sh --no-bind       just enable the plugin
#
# The shortcut proposed first is SUPER + ALT + S, unless Hyprland already has
# that combination, in which case the first free candidate is proposed instead.
# Whatever is proposed can be edited; Enter accepts it.

set -euo pipefail

ID="io.github.kimm-stensborg.sessions"
BINDINGS="$HOME/.config/hypr/bindings.lua"
MARKER="-- Sessions overlay ($ID)"

# S for Sessions. The rest are free on a stock install too, for when the
# first one is not.
CANDIDATES=(
  "SUPER + ALT + S"
  "SUPER + SHIFT + J"
  "SUPER + ALT + J"
  "SUPER + CTRL + J"
)

fail() {
  echo "install.sh: $*" >&2
  exit 1
}

interactive() { [[ -t 0 && -t 1 ]]; }

for tool in jq hyprctl omarchy-shell; do
  command -v "$tool" >/dev/null || fail "$tool is required"
done

key=""
bind=1
while (($# > 0)); do
  case "$1" in
  --key)
    key="${2:-}"
    [[ -n $key ]] || fail "--key requires a shortcut"
    shift 2
    ;;
  --no-bind)
    bind=0
    shift
    ;;
  -h | --help)
    sed -n '3,11p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  *) fail "unknown option: $1" ;;
  esac
done

# "super+alt+s" for any spelling of SUPER + ALT + S, so a combination can be
# compared against what Hyprland reports regardless of order or spacing.
normalize() {
  tr 'a-z' 'A-Z' <<<"$1" |
    tr -d ' ' | tr '+' '\n' |
    sed 's/^MOD$/SUPER/; s/^WIN$/SUPER/; s/^CONTROL$/CTRL/; s/^MOD1$/ALT/' |
    awk '
      /^(SUPER|SHIFT|CTRL|ALT)$/ { mods[$0] = 1; next }
      { key = $0 }
      END {
        split("SUPER SHIFT CTRL ALT", order, " ")
        for (i = 1; i <= 4; i++) if (order[i] in mods) out = out tolower(order[i]) "+"
        print out tolower(key)
      }'
}

# Every bound combination Hyprland currently knows, outside submaps, one per
# line in the same shape as normalize(). Binds carrying a keycode rather than a
# key name are skipped: they cannot collide with a combination typed as text.
bound_combos() {
  hyprctl binds -j | jq -r '
    def mods(m):
      [ if (m / 64 % 2) >= 1 then "super" else empty end,
        if (m % 2) >= 1 then "shift" else empty end,
        if (m / 4 % 2) >= 1 then "ctrl" else empty end,
        if (m / 8 % 2) >= 1 then "alt" else empty end ];
    .[]
    | select(.submap == "" and .key != "")
    | ((mods(.modmask) + [.key | ascii_downcase]) | join("+"))
      + "\t" + (.description // "")
  '
}

# What is bound to a combination, empty when nothing is. Reads the snapshot
# taken once at startup rather than asking Hyprland again per lookup.
describe_conflict() {
  awk -F'\t' -v c="$1" '$1 == c && !found { found = 1; print $2 }' <<<"$TAKEN"
}

is_taken() {
  awk -F'\t' -v c="$1" 'BEGIN { rc = 1 } $1 == c { rc = 0 } END { exit rc }' <<<"$TAKEN"
}

# The first candidate Hyprland has nothing bound to, falling back to the first
# candidate so there is always something to propose.
pick_default() {
  local candidate
  for candidate in "${CANDIDATES[@]}"; do
    is_taken "$(normalize "$candidate")" || {
      printf '%s\n' "$candidate"
      return
    }
  done
  printf '%s\n' "${CANDIDATES[0]}"
}

write_binding() {
  local combo="$1" conflict="$2"
  mkdir -p "$(dirname "$BINDINGS")"
  touch "$BINDINGS"
  cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"

  # Drop a previous run's block so re-running replaces the shortcut rather than
  # stacking a second one.
  local tmp
  tmp=$(mktemp)
  awk -v marker="$MARKER" '
    $0 == marker { skip = 1; next }
    skip && ($0 ~ /^hl\.unbind\(/ || $0 ~ /^o\.bind\(/) { next }
    { skip = 0; lines[++n] = $0 }
    END {
      while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ' "$BINDINGS" >"$tmp"
  mv "$tmp" "$BINDINGS"

  {
    printf '\n%s\n' "$MARKER"
    [[ -z $conflict ]] || printf 'hl.unbind("%s")\n' "$combo"
    printf 'o.bind("%s", "Sessions", "omarchy-shell shell toggle %s '"'"'{}'"'"'")\n' "$combo" "$ID"
  } >>"$BINDINGS"

  hyprctl reload >/dev/null
  local errors
  errors=$(hyprctl configerrors)
  [[ -z ${errors//[[:space:]]/} || $errors == "no errors"* ]] ||
    fail "Hyprland reported config errors:"$'\n'"$errors"
}

# The combination an earlier run of this script bound, so re-running and keeping
# the same shortcut does not look like a collision with itself.
ours() {
  [[ -f $BINDINGS ]] || return 0
  awk -v marker="$MARKER" '
    $0 == marker { found = 1; next }
    found && /^o\.bind\(/ {
      match($0, /"[^"]+"/)
      print substr($0, RSTART + 1, RLENGTH - 2)
      exit
    }
  ' "$BINDINGS"
}

OURS=$(normalize "$(ours)")
TAKEN=$(bound_combos | awk -F'\t' -v ours="$OURS" '$1 != ours')

if [[ $bind == 1 ]]; then
  if [[ -z $key ]]; then
    interactive || fail "no shortcut given; pass --key \"SUPER + ALT + S\" or --no-bind"
    default=$(pick_default)
    if command -v gum >/dev/null; then
      key=$(gum input --header "Shortcut for Sessions (Enter to accept)" --value "$default") ||
        fail "cancelled"
    else
      read -rp "Shortcut for Sessions [$default]: " key
    fi
    key="${key:-$default}"
  fi

  combo=$(normalize "$key")
  [[ $combo == *+* ]] || fail "'$key' has no modifier; use something like SUPER + ALT + S"

  conflict=""
  if is_taken "$combo"; then
    conflict=$(describe_conflict "$combo")
    conflict="${conflict:-an existing binding}"
    echo "$key is already bound to: $conflict"
    if interactive; then
      if command -v gum >/dev/null; then
        gum confirm "Take it over?" || fail "aborted"
      else
        read -rp "Take it over? [y/N] " answer
        [[ $answer == [yY]* ]] || fail "aborted"
      fi
    else
      fail "$key is already bound to: $conflict"
    fi
  fi

  write_binding "$key" "$conflict"
  echo "Bound $key to Sessions in $BINDINGS"
  [[ -z $conflict ]] || echo "It was previously: $conflict"
fi

omarchy plugin enable "$ID"
