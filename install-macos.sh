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

# the `rhunpad` command: a wrapper in ~/.local/bin (the .app alone is not on the PATH)
bindir="$HOME/.local/bin"
mkdir -p "$bindir"
printf '#!/bin/sh\nexec "%s/%s/Contents/MacOS/rhunpad" "$@"\n' "$dest" "$app" > "$bindir/rhunpad"
chmod 755 "$bindir/rhunpad"
echo "command:   $bindir/rhunpad"
case ":$PATH:" in
    *":$bindir:"*) ;;
    *)
        echo "note: $bindir is not on your PATH - add it once:"
        echo "  fish: fish_add_path ~/.local/bin"
        echo "  zsh:  echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.zshrc && exec \$SHELL"
        ;;
esac
echo "launch the app with:  open $dest/$app"
