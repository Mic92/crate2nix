{ pkgs ? import ./nix/nixpkgs.nix { config = {}; }
, lib ? pkgs.lib
, cargo ? pkgs.cargo
, nix ? pkgs.nix
, makeWrapper ? pkgs.makeWrapper
, callPackage ? pkgs.callPackage
, darwin ? pkgs.darwin
, stdenv ? pkgs.stdenv
, defaultCrateOverrides ? pkgs.defaultCrateOverrides
, release ? true
}:
let
  cargoNix = callPackage ./crate2nix/Cargo.nix { inherit release; };
  withoutTemplates = name: type:
    let
      baseName = builtins.baseNameOf (builtins.toString name);
    in
      !(baseName == "templates" && type == "directory");

  crate2nix = cargoNix.rootCrate.build.override {
    testCrateFlags = [
      "--skip nix_integration_tests"
    ];
    crateOverrides = defaultCrateOverrides // {
      crate2nix = { src, ... }: {
        src =
          if release
          then src
          else lib.cleanSourceWith {
            filter = withoutTemplates;
            inherit src;
          };
        dontFixup = !release;
      };
      cssparser-macros = attrs: assert builtins.trace "cssparser" true;{
        buildInputs = stdenv.lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.Security ];
      };
    };
  };
  set_templates = if release then "" else "--set TEMPLATES_DIR ${./crate2nix/templates}";
in
pkgs.symlinkJoin {
  name = crate2nix.name;
  paths = [ crate2nix ];
  buildInputs = [ makeWrapper cargo ];
  postBuild = ''
    # Fallback to built dependencies for cargo and nix-prefetch-url
    wrapProgram $out/bin/crate2nix ${set_templates}\
       --suffix PATH ":" ${lib.makeBinPath [ cargo nix pkgs.nix-prefetch-git ]}
    rm -rf $out/lib $out/bin/crate2nix.d
    mkdir -p \
      $out/share/bash-completion/completions \
      $out/share/zsh/vendor-completions
    $out/bin/crate2nix completions -s 'bash' -o $out/share/bash-completion/completions
    $out/bin/crate2nix completions -s 'zsh' -o $out/share/zsh/vendor-completions
  '';
}
