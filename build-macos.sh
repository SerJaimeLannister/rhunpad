#!/bin/sh
# build-macos.sh: build the production rhunpad app for macOS (Apple silicon).
# Produces build/rhunpad (the executable) and build/rhunpad.app (the app bundle).
set -e
cd "$(dirname "$0")"

miss=
for t in clang as python3 sed strip codesign sysctl; do
    command -v "$t" >/dev/null 2>&1 || miss="$miss $t"
done
if [ -n "$miss" ]; then
    echo "build-macos.sh: missing build tools:$miss" >&2
    echo "install them with:  xcode-select --install   (Xcode Command Line Tools)" >&2
    exit 1
fi

tools/build-mac.sh release

exe=build/rhunpad.app/Contents/MacOS/rhunpad
[ -x "$exe" ] || { echo "build-macos.sh: build finished but $exe is missing" >&2; exit 1; }
echo "built: $(pwd)/build/rhunpad.app"
echo "install it with:  ./install-macos.sh"
