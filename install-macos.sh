#!/bin/sh
# install-macos.sh: install the built rhunpad.app into /Applications, falling back to
# ~/Applications when /Applications is not writable (no admin password needed).
set -e
cd "$(dirname "$0")"

app=rhunpad.app
src="build/$app"
if [ ! -d "$src" ]; then
    echo "install-macos.sh: $src not found" >&2
    echo "build it first with:  ./build-macos.sh" >&2
    exit 1
fi

dest=/Applications
if [ ! -w "$dest" ]; then
    dest="$HOME/Applications"
    mkdir -p "$dest"
    echo "/Applications is not writable - installing to $dest instead"
fi
rm -rf "$dest/$app"
cp -R "$src" "$dest/$app"
echo "installed: $dest/$app"
echo "launch it with:  open $dest/$app"
