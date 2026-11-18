{
  description = "parallel_shelf_core: Logos core module that QFile::reads a path the view already listed.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      # Copy pdftoppm + its dylibs into $out/lib/bin so the lgx extract
      # has variants/<plat>/bin/pdftoppm, never beside the plugin.
      postInstall = builtins.readFile ./nix/stage-pdftoppm.sh;
    };
}
