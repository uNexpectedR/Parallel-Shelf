{
  description = "Parallel Shelf — a public library in Logos Basecamp.";

  nixConfig = {
    extra-substituters = [ "https://cache.nix.logos.co/public" ];
    extra-trusted-public-keys = [ "public:l4HrXgL4nw246+LBh2SOJyhz64BoGegOYLheT/iIAPU=" ];
  };

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    delivery_module = {
      url = "github:logos-co/logos-delivery-module/v0.3.3";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    storage_module = {
      url = "github:logos-co/logos-storage-module/v3.0.2";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    liblogos_rln_module = {
      url = "git+https://github.com/logos-co/logos-rln-modules?ref=main&rev=a814e7feda974a16eaa5dd50667b8fd843177f0e&dir=logos-rln-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.liblogos_lez_rln_module.url = "git+https://github.com/logos-co/logos-rln-modules?ref=main&rev=a814e7feda974a16eaa5dd50667b8fd843177f0e&dir=logos-lez-rln-module";
      inputs.liblogos_lez_rln_module.inputs.logos-module-builder.follows = "logos-module-builder";
    };
    parallel_shelf_core = {
      url = "path:./core";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    let
      # View: type ui_qml, empty main, no IComponent. Same open path as 0.14.0.
      # Bytes: parallel_shelf_core (type:core) in a Logos host process.
      ui = logos-module-builder.lib.mkLogosQmlModule {
        src = ./.;
        configFile = ./metadata.json;
        flakeInputs = inputs;
      };
      core = logos-module-builder.lib.mkLogosModule {
        src = ./core;
        configFile = ./core/metadata.json;
        flakeInputs = inputs;
        postInstall = builtins.readFile ./core/nix/stage-pdftoppm.sh;
      };
      nixpkgs = logos-module-builder.inputs.nixpkgs;
      inherit (nixpkgs) lib;
      lgxFor = system:
        logos-module-builder.inputs.nix-bundle-lgx.inputs.logos-package.packages.${system}.lgx;
      check = system: sysPkgs:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lgxCli = lgxFor system;
          checkLgx = pkgs.writeText "check-lgx-open.py" ''
            import json, os, tarfile, sys
            path = os.environ["PKG"]
            with tarfile.open(path, "r:gz") as tar:
                names = tar.getnames()
                bad = [n for n in names if n.startswith("./") or n.startswith("/")]
                if bad:
                    raise SystemExit("tar members still have a ./ or absolute prefix: " + repr(bad[:8]))
                native = [
                    n for n in names
                    if n.endswith(".so") or n.endswith(".dylib") or n.endswith(".dll")
                    or "libfilebytesplugin" in n
                    or "parallel_shelf_plugin" in n
                ]
                if native:
                    raise SystemExit("ui_qml package must not ship a native plugin: " + repr(native))
                qml_main = [n for n in names if n.endswith("Main.qml")]
                if not qml_main:
                    raise SystemExit("Main.qml missing from lgx: " + repr(names[:40]))
                plugin_qmldir = []
                for n in names:
                    if not n.endswith("qmldir"):
                        continue
                    raw = tar.extractfile(n).read().decode("utf-8", "replace")
                    for line in raw.splitlines():
                        s = line.strip()
                        if s.startswith("plugin") or s.startswith("optional plugin"):
                            plugin_qmldir.append(n + ": " + line)
                if plugin_qmldir:
                    raise SystemExit("qmldir plugin line would crash-open or block import: " + repr(plugin_qmldir))
                mf = json.load(tar.extractfile("manifest.json"))
                if mf.get("type") != "ui_qml":
                    raise SystemExit("manifest type is %r, want ui_qml" % (mf.get("type"),))
                if mf.get("version") != "0.1.3":
                    raise SystemExit("manifest version is %r, want 0.1.3" % (mf.get("version"),))
                main = mf.get("main")
                if main not in (None, "", {}):
                    raise SystemExit("manifest main must be empty for in-process QML open, got %r" % (main,))
                deps = mf.get("dependencies") or []
                if "parallel_shelf_core" not in deps:
                    raise SystemExit("view must depend on parallel_shelf_core, got %r" % (deps,))
                print("openLgx type=ui_qml version=0.1.3 main=empty native=0 qml=" + qml_main[0], file=sys.stderr)
          '';
          extractVariant = ''
            variant=$(tar -tzf "$work/pkg.lgx" \
              | sed 's|^\./||' \
              | awk -F/ '$1=="variants" && $2!="" {print $2}' \
              | sort -u)
            if [ -z "$variant" ] || [ "$(printf '%s\n' "$variant" | grep -c .)" -ne 1 ]; then
              echo "lgx-check: expected one platform variant, got: ''${variant:-none}" >&2
              tar -tzf "$work/pkg.lgx" >&2
              exit 1
            fi
            case "$variant" in
              linux-amd64|linux-amd64-dev|darwin-arm64|darwin-arm64-dev) ;;
              *) echo "lgx-check: unexpected variant $variant" >&2; exit 1 ;;
            esac
            lgx verify "$work/pkg.lgx"
            lgx extract "$work/pkg.lgx" --variant "$variant" --output "$work/extracted"
            echo "lgx extract --variant $variant ok" >&2
          '';
          verifyLgx = drv:
            pkgs.runCommand "${drv.name}-open-check" {
              nativeBuildInputs = [ pkgs.python3 pkgs.gnutar pkgs.gzip lgxCli ];
            } ''
              set -euo pipefail
              mkdir -p "$out"
              src="${drv}"
              if [ -d "$src" ]; then
                files=( "$src"/*.lgx )
              else
                files=( "$src" )
              fi
              if [ ''${#files[@]} -eq 0 ]; then
                echo "open-check: no .lgx in $src" >&2
                ls -la "$src" >&2 || true
                exit 1
              fi
              for lgxsrc in "''${files[@]}"; do
                PKG="$lgxsrc" python3 ${checkLgx}
                work=$(mktemp -d)
                cp "$lgxsrc" "$work/pkg.lgx"
                ${extractVariant}
                find "$work/extracted" -name 'Main.qml' | grep -q . \
                  || { echo "open-check: Main.qml missing after lgx extract" >&2; find "$work/extracted" >&2; exit 1; }
                natives=$(find "$work/extracted" \( -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) -print || true)
                if [ -n "$natives" ]; then
                  echo "ui_qml extract must not contain a native plugin: $natives" >&2
                  exit 1
                fi
                rm -rf "$work"
                cp "$lgxsrc" "$out/$(basename "$lgxsrc")"
              done
            '';
          verifyCoreLgx = drv:
            pkgs.runCommand "${drv.name}-extract-check" {
              nativeBuildInputs = [ pkgs.python3 pkgs.gnutar pkgs.gzip lgxCli ];
            } ''
              set -euo pipefail
              mkdir -p "$out"
              src="${drv}"
              if [ -d "$src" ]; then
                files=( "$src"/*.lgx )
              else
                files=( "$src" )
              fi
              if [ ''${#files[@]} -eq 0 ]; then
                echo "core-extract: no .lgx in $src" >&2
                ls -la "$src" >&2 || true
                exit 1
              fi
              for lgxsrc in "''${files[@]}"; do
                work=$(mktemp -d)
                cp "$lgxsrc" "$work/pkg.lgx"
                ${extractVariant}
                plugin=$(find "$work/extracted" \( -name 'parallel_shelf_core_plugin.so' -o -name 'parallel_shelf_core_plugin.dylib' \) | head -n1)
                if [ -z "$plugin" ]; then
                  echo "core-extract: parallel_shelf_core_plugin missing after lgx extract --variant $variant" >&2
                  find "$work/extracted" >&2 || true
                  exit 1
                fi
                echo "core-extract plugin=$plugin" >&2
                plugdir=$(dirname "$plugin")
                find "$work/extracted" \( -name pdftoppm -o -name 'libpoppler*' \) >&2 || true
                beside=$(find "$plugdir" -maxdepth 1 \( -name pdftoppm -o -name 'libpoppler*' \) -print)
                if [ -n "$beside" ]; then
                  echo "core-extract: pdftoppm/libpoppler must not sit beside the plugin in $plugdir" >&2
                  echo "$beside" >&2
                  ls -l "$plugdir" >&2 || true
                  exit 1
                fi
                ppm=$(find "$work/extracted" -path '*/bin/pdftoppm' -type f | head -n1)
                if [ -z "$ppm" ]; then
                  echo "core-extract: pdftoppm missing from bin/ after lgx extract --variant $variant" >&2
                  find "$work/extracted" >&2 || true
                  exit 1
                fi
                if head -c 2 "$ppm" | grep -q '^#!'; then
                  echo "core-extract: pdftoppm is still a wrapProgram script: $ppm" >&2
                  exit 1
                fi
                echo "core-extract pdftoppm=$ppm" >&2
                rm -rf "$work"
                cp "$lgxsrc" "$out/$(basename "$lgxsrc")"
              done
            '';
          corePkgs = core.packages.${system} or {};
        in sysPkgs // lib.optionalAttrs (sysPkgs ? lgx) {
          lgx = verifyLgx sysPkgs.lgx;
        } // lib.optionalAttrs (sysPkgs ? lgx-portable) {
          lgx-portable = verifyLgx sysPkgs.lgx-portable;
        } // lib.optionalAttrs (corePkgs ? lgx) {
          core-lgx = verifyCoreLgx corePkgs.lgx;
        } // lib.optionalAttrs (corePkgs ? lgx-portable) {
          core-lgx-portable = verifyCoreLgx corePkgs.lgx-portable;
        };
    in ui // {
      packages = lib.mapAttrs check ui.packages;
    };
}
