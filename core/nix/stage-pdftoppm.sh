# Isolate pdftoppm and the shared libraries it needs in $out/lib/bin.
# logos-module-builder packs $out/lib into the lgx variant root, so a file
# in $out/lib sits BESIDE the plugin. Mac 0.43.0 crash-opened because
# logoscore dlopened libpoppler next to parallel_shelf_core_plugin.dylib.
# metadata include copies pdftoppm into $out/lib; this hook moves it under
# bin/ with its dylibs, then deletes the copy next to the plugin.
echo "Staging pdftoppm into lib/bin (not beside the plugin)..."
src=""
for cand in \
    "$out/lib/bin/pdftoppm" \
    "$out/lib/pdftoppm" \
    "$out/bin/pdftoppm" \
    "$(command -v pdftoppm || true)"; do
  if [ -n "$cand" ] && [ -e "$cand" ]; then
    src="$cand"
    break
  fi
done
if [ -z "$src" ]; then
  echo "stage-pdftoppm: pdftoppm not found (poppler_utils runtime + include)" >&2
  exit 1
fi
if [ -f "$src" ] && [ "$(head -c 2 "$src" 2>/dev/null || true)" = "#!" ]; then
  wrapped=$(grep -oE '/nix/store/[^[:space:]"]+/(\.pdftoppm-wrapped|pdftoppm)' "$src" | tail -n1 || true)
  if [ -z "$wrapped" ] || [ ! -e "$wrapped" ]; then
    echo "stage-pdftoppm: wrapProgram script but no wrapped binary in $src" >&2
    exit 1
  fi
  src="$wrapped"
fi
mkdir -p "$out/lib/bin"
if [ "$(readlink -f "$src")" != "$(readlink -f "$out/lib/bin/pdftoppm" 2>/dev/null || true)" ]; then
  cp -Lf "$src" "$out/lib/bin/pdftoppm"
fi
chmod u+w "$out/lib/bin/pdftoppm"
chmod +x "$out/lib/bin/pdftoppm"
# Never leave pdftoppm beside the plugin.
rm -f "$out/lib/pdftoppm"

copy_one_lib() {
  local lib="$1"
  [ -f "$lib" ] || return 0
  local name
  name=$(basename "$lib")
  case "$name" in
    ld-linux*|ld-musl*|libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|libgcc_s.so*|libstdc++.so*)
      return 0
      ;;
  esac
  # Only next to pdftoppm in bin/, never $out/lib (plugin load path).
  if [ ! -e "$out/lib/bin/$name" ]; then
    cp -Lf "$lib" "$out/lib/bin/$name" || true
  fi
  chmod u+w "$out/lib/bin/$name" 2>/dev/null || true
}

if command -v ldd >/dev/null 2>&1 && ldd "$out/lib/bin/pdftoppm" >/dev/null 2>&1; then
  pass=0
  while [ "$pass" -lt 6 ]; do
    pass=$((pass + 1))
    for so in "$out/lib/bin/pdftoppm" "$out/lib/bin/"*.so*; do
      [ -f "$so" ] || continue
      ldd "$so" 2>/dev/null | awk '/=> \// {print $3} /^\// {print $1}' | while read -r lib; do
        case "$lib" in
          /lib/*|/lib64/*|/usr/lib/*|*/ld-linux*) continue ;;
        esac
        copy_one_lib "$lib"
      done
    done
  done
  if command -v patchelf >/dev/null 2>&1; then
    patchelf --set-rpath '$ORIGIN' "$out/lib/bin/pdftoppm" || true
    for so in "$out/lib/bin/"*.so*; do
      [ -f "$so" ] || continue
      patchelf --set-rpath '$ORIGIN' "$so" || true
    done
  fi
elif command -v otool >/dev/null 2>&1; then
  pass=0
  while [ "$pass" -lt 6 ]; do
    pass=$((pass + 1))
    for bin in "$out/lib/bin/pdftoppm" "$out/lib/bin/"*.dylib; do
      [ -f "$bin" ] || continue
      otool -L "$bin" 2>/dev/null | awk '/compatibility/ {print $1}' | while read -r lib; do
        case "$lib" in
          /usr/lib/*|/System/*|@*|lib*) continue ;;
        esac
        [ -f "$lib" ] || continue
        copy_one_lib "$lib"
        name=$(basename "$lib")
        install_name_tool -change "$lib" "@loader_path/$name" "$bin" 2>/dev/null || true
      done
    done
  done
  for dylib in "$out/lib/bin/"*.dylib; do
    [ -f "$dylib" ] || continue
    name=$(basename "$dylib")
    install_name_tool -id "@loader_path/$name" "$dylib" 2>/dev/null || true
  done
  install_name_tool -add_rpath "@loader_path" "$out/lib/bin/pdftoppm" 2>/dev/null || true
fi
rm -f "$out/lib/pdftoppm"
find "$out/lib" -maxdepth 1 -name 'libpoppler*' -delete 2>/dev/null || true
if [ -e "$out/lib/pdftoppm" ]; then
  echo "stage-pdftoppm: pdftoppm still beside the plugin in $out/lib" >&2
  exit 1
fi
beside=$(find "$out/lib" -maxdepth 1 \( -name pdftoppm -o -name 'libpoppler*' \) -print)
if [ -n "$beside" ]; then
  echo "stage-pdftoppm: poppler still beside the plugin in $out/lib:" >&2
  echo "$beside" >&2
  ls -l "$out/lib" >&2 || true
  exit 1
fi
if [ ! -x "$out/lib/bin/pdftoppm" ]; then
  echo "stage-pdftoppm: failed to install $out/lib/bin/pdftoppm" >&2
  exit 1
fi
echo "stage-pdftoppm: bin=$out/lib/bin/pdftoppm"
ls -l "$out/lib/bin/pdftoppm" >&2 || true
file "$out/lib/bin/pdftoppm" >&2 || true
ls "$out/lib/bin" >&2 || true
