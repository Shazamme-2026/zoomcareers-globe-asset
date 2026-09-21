#!/usr/bin/env bash
# duda-iframe.html is the single source of truth for the embeddable page.
# Every duda-iframe-vN.html is a byte-identical copy of it; the vN suffixes
# exist only to hand Duda/browsers a fresh URL when their cache will not
# release the old markup.
#
# FROZEN is the exception: those are published URLs that must keep serving the
# markup they serve today, so the sync skips them. Only remove one when the
# owner has asked for that URL to be republished.
#
# index.html (local preview) and duda-widget.html (Duda paste fragment) have
# their own page shells, so they cannot be copied wholesale. This script
# instead checks that their copy block still matches the canonical one, which
# is where every drift in this repo has come from.
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")"

SRC=duda-iframe.html
FROZEN=(duda-iframe-v7.html)

# bash 3.2 is still /bin/bash on macOS and treats "${FROZEN[@]}" as unbound
# under `set -u` when the array is empty, so expand it defensively.
is_frozen() {
  local f
  for f in ${FROZEN[@]+"${FROZEN[@]}"}; do
    [ "$1" = "$f" ] && return 0
  done
  return 1
}

for f in duda-iframe-v*.html; do
  if is_frozen "$f"; then
    echo "frozen $f (left as published)"
    continue
  fi
  cp "$SRC" "$f"
  echo "synced $f"
done

block() {
  sed -n '/<div class="globe-copy"/,/^<\/div>$/p' "$1"
}

# Two empty block() results must never compare equal, or a changed anchor
# would turn this guard into a silent pass.
canonical="$(block "$SRC")"
if [ -z "$canonical" ]; then
  echo "FATAL  no copy block found in $SRC (anchor changed?)" >&2
  exit 1
fi

status=0
for f in index.html duda-widget.html; do
  found="$(block "$f")"
  if [ -z "$found" ]; then
    echo "DRIFT  $f has no copy block (anchor missing)" >&2
    status=1
  elif [ "$canonical" = "$found" ]; then
    echo "ok     $f (copy block matches $SRC)"
  else
    echo "DRIFT  $f copy block differs from $SRC" >&2
    status=1
  fi
done

# The .globe-copy rules live in style.css (linked by the iframe variants and
# index.html) and are duplicated into duda-widget.html, which is self-contained
# and links no stylesheet. Without this check a style.css fix would pass the
# markup guard above while never reaching the pasted widget.
css_block() {
  sed -n '/shared rules: START/,/shared rules: END/p' "$1"
}
css_canonical="$(css_block style.css)"
if [ -z "$css_canonical" ]; then
  echo "FATAL  no .globe-copy rules found in style.css (anchor changed?)" >&2
  exit 1
fi
css_found="$(css_block duda-widget.html)"
if [ -z "$css_found" ]; then
  echo "DRIFT  duda-widget.html has no .globe-copy rules" >&2
  status=1
elif [ "$css_canonical" = "$css_found" ]; then
  echo "ok     duda-widget.html (.globe-copy CSS matches style.css)"
else
  echo "DRIFT  duda-widget.html .globe-copy CSS differs from style.css" >&2
  status=1
fi

# The one-line headline is an invariant split across two files: the markup
# carries white-space:nowrap, and the CSS ceiling is only safe because of it.
# Each guard above checks its own file, so nothing ties the two together and a
# later ceiling bump or copy edit would pass both while silently wrapping or
# overflowing. "Connected by Curiosity." measures 13.1x its font-size in
# HappyDisplay SemiBold, so 46px is the largest ceiling a 620px panel allows.
if ! grep -q 'white-space:nowrap">Connected by Curiosity.</h2>' "$SRC"; then
  echo "DRIFT  $SRC h2 lost white-space:nowrap (the CSS ceiling assumes it)" >&2
  status=1
fi
# Checking one known string is not enough: a stale @media override already slipped
# past that once. Assert instead that EVERY font-size declared for the headline is
# container-relative and capped at 46px, whichever rule or breakpoint it sits in.
bad_headline_rules="$(awk '
  /^[^{]*\.globe-copy h[12]/ { headline = 1 }
  headline && /font-size/ {
    if ($0 !~ /7\.2cqw/ || $0 !~ /46px/) { print NR ": " $0 }
  }
  /}/ { headline = 0 }
' style.css)"
if [ -n "$bad_headline_rules" ]; then
  echo "DRIFT  style.css headline font-size must be min(..., 7.2cqw) capped at 46px:" >&2
  echo "$bad_headline_rules" >&2
  status=1
fi

exit "$status"
