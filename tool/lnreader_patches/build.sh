#!/bin/sh
# Rebuilds assets/lnreader/patches/ from upstream LNReader plugins with
# plugins.patch applied. plugins.txt pins the upstream commit and
# names the file upstream's build writes each patched plugin to.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out="$here/../../assets/lnreader/patches"
commit=$(sed -n 's/^commit //p' "$here/plugins.txt")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git clone -q --filter=blob:none https://github.com/LNReader/lnreader-plugins.git "$work"
git -C "$work" checkout -q "$commit"
git -C "$work" apply "$here/plugins.patch"
cd "$work"
npm install --no-save --ignore-scripts typescript@5.7 terser@5 >/dev/null
node plugins/multisrc/generate-multisrc-plugins.js >/dev/null
npx tsc --project tsconfig.production.json
grep -v '^commit \|^#\|^$' "$here/plugins.txt" | while read -r id file; do
  npx terser ".js/plugins/$file" --compress arrows=false --mangle --ecma 5 \
    --module --toplevel -o "$out/$id.js"
done
