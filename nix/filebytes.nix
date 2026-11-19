{ stdenv, qt6, cmake }:

# qmltestrunner helper under tests/TestFileBytes. Not packed in the lgx.
stdenv.mkDerivation {
  pname = "filebytesplugin";
  version = "0.1.4";
  src = ../.;

  nativeBuildInputs = [ cmake qt6.qtbase ];
  buildInputs = [ qt6.qtbase qt6.qtdeclarative ];
  dontWrapQtApps = true;

  preConfigure = ''
    cd "$NIX_BUILD_TOP"/source/tests/TestFileBytes
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    found=
    for f in libfilebytesplugin* filebytesplugin.dll; do
      if [ -e "$f" ]; then
        cp -a "$f" $out/lib/
        found=1
      fi
    done
    if [ -z "$found" ]; then
      echo "filebytes plugin not built" >&2
      find . -maxdepth 3 >&2 || true
      exit 1
    fi
    runHook postInstall
  '';
}
