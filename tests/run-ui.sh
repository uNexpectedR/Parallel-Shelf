#!/usr/bin/env bash
# Runs the screen tests. Needs Qt 6 with the QtQuick, QtTest,
# Qt.labs.settings QML modules (on Debian or Ubuntu: qml6-module-qtquick,
# qml6-module-qttest, qml6-module-qt-labs-settings, qt6-declarative-dev-tools).
# Qt.labs.folderlistmodel is used on Mac to list files in the view; tests
# fall back to Picker.qml if that module is missing.
# tests/TestFileBytes is a QFile QML plugin for qmltestrunner only (needs
# qt6-base-dev and qt6-declarative-dev). It is not packed in the lgx.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
runner="$(command -v qmltestrunner6 || command -v qmltestrunner || echo /usr/lib/qt6/bin/qmltestrunner)"

export PATH="/usr/lib/qt6/libexec:/usr/lib/qt6/bin:${PATH:-}"

plugin_dir="$repo/tests/TestFileBytes"
(cd "$plugin_dir" && qmake6 FileBytes.pro && make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)")

work=/tmp/parallel-shelf-tests
rm -rf "$work"
mkdir -p "$work/config" "$work/Users/unexpectedr/Downloads"

# Same size as the 2.2 MB proof PDF, with a NUL in the first piece, so Share
# is tested on a real-sized binary file. The package itself stays empty.
proof="/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/internal/farewell-to-westphalia-foss-edition.pdf"
if [ -f "$proof" ]; then
  cp "$proof" "$work/farewell-to-westphalia-foss-edition.pdf"
else
  python3 -c 'p=bytearray(2276462); p[0:5]=b"%PDF-"; p[819]=0; open("/tmp/parallel-shelf-tests/farewell-to-westphalia-foss-edition.pdf","wb").write(p)'
fi
cp "$work/farewell-to-westphalia-foss-edition.pdf" \
   "$work/Users/unexpectedr/Downloads/farewell-to-westphalia-foss-edition.pdf"

g++ -fPIC -o "$work/read_pdf" \
  -I"$repo/core/src" \
  "$here/read_pdf.cpp" \
  $(pkg-config --cflags --libs Qt6Core)
"$work/read_pdf" "$work/Users/unexpectedr/Downloads/farewell-to-westphalia-foss-edition.pdf"
"$work/read_pdf" "/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/internal/farewell-to-westphalia-foss-edition.pdf"

g++ -fPIC -o "$work/fetch_dest" \
  -I"$repo/core/src" \
  "$here/fetch_dest.cpp" \
  $(pkg-config --cflags --libs Qt6Core)
"$work/fetch_dest" mwgvu2lo-9qytof pdf

g++ -fPIC -o "$work/open_bytes" \
  -I"$repo/core/src" \
  "$here/open_bytes.cpp" \
  $(pkg-config --cflags --libs Qt6Core)
"$work/open_bytes" "/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/internal/farewell-to-westphalia-foss-edition.pdf"

g++ -fPIC -o "$work/hold_map" \
  -I"$repo/core/src" \
  "$here/hold_map.cpp" \
  $(pkg-config --cflags --libs Qt6Core)
"$work/hold_map"

g++ -fPIC -o "$work/render_page" \
  -I"$repo/core/src" \
  "$here/render_page.cpp" \
  $(pkg-config --cflags --libs Qt6Core Qt6Gui)
"$work/render_page" "/cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/internal/farewell-to-westphalia-foss-edition.pdf"

export QML2_IMPORT_PATH="$repo/src/qml:$repo/tests${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
# Offscreen Qt multimedia still probes Pulse and can abort at process exit.
export PULSE_SERVER="${PULSE_SERVER:-none}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}"
export QML_IMPORT_PATH="$QML2_IMPORT_PATH"
export QT_QML_IMPORT_PATH="$QML2_IMPORT_PATH"
export XDG_CONFIG_HOME="$work/config"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

# Mac Basecamp: no QML_XHR_ALLOW_FILE_READ, and Storage cannot open Downloads.
# Prove open, FolderListModel size, then Share through parallel_shelf_core
# (view does not import tests/TestFileBytes; FakeBasecamp stands in for the core).
export QML_XHR_ALLOW_FILE_WRITE=1
unset QML_XHR_ALLOW_FILE_READ || true
"$runner" -import "$repo/src/qml" -import "$repo/tests" -input "$here/ui/tst_open_ui_qml.qml"
"$runner" -import "$repo/src/qml" -import "$repo/tests" -input "$here/ui/tst_filebytes_qml.qml"
"$runner" -import "$repo/src/qml" -import "$repo/tests" -input "$here/ui/tst_xhr_hang.qml"
"$runner" -import "$repo/src/qml" -import "$repo/tests" -input "$here/ui/tst_sandbox_bytes.qml"
"$runner" -import "$repo/src/qml" -import "$repo/tests" -input "$here/ui/tst_filebytes.qml"
"$runner" -import "$repo/src/qml" -import "$repo/tests" -input "$here/ui/tst_share_noxhr.qml"
unset QML_XHR_ALLOW_FILE_WRITE || true
"$runner" -import "$repo/src/qml" -import "$repo/tests" -input "$here/ui/tst_open_noxhr.qml"
export QML_XHR_ALLOW_FILE_WRITE=1

export QML_XHR_ALLOW_FILE_READ=1
"$runner" -import "$repo/src/qml" -import "$repo/tests" -input "$here/ui" "$@"
python3 "$here/png_ink.py" \
  /cursor/stores/bc-a13b448c-7ad4-47f5-a01c-a53f4b3ed883/media/open-0.48.0-page12.png
