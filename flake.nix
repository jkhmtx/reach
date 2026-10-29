{
  description = "Extensible AST traversal tool for building a cross-language dependency graph";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, fenix, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = nixpkgs.legacyPackages.${system};
            fenixPkgs = fenix.packages.${system};
          }
        );
      toolchainFor =
        fenixPkgs:
        fenixPkgs.stable.withComponents [
          "cargo"
          "clippy"
          "rust-src"
          "rustc"
          "rustfmt"
          "rust-analyzer"
        ];
    in
    {
      packages = forAllSystems (
        { pkgs, fenixPkgs }:
        let
          toolchain = toolchainFor fenixPkgs;
          rustPlatform = pkgs.makeRustPlatform {
            cargo = toolchain;
            rustc = toolchain;
          };
        in
        rec {
          reach = rustPlatform.buildRustPackage {
            pname = "reach";
            version = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).workspace.package.version;
            src = ./.;
            cargoLock.lockFile = ./Cargo.lock;
            cargoBuildFlags = [
              "--package"
              "reach"
            ];
            meta = {
              description = "Extensible AST traversal tool for building a cross-language dependency graph";
              license = pkgs.lib.licenses.gpl3Plus;
              mainProgram = "reach";
            };
          };
          default = reach;
        }
      );

      devShells = forAllSystems (
        { pkgs, fenixPkgs }:
        {
          default = pkgs.mkShell {
            packages = [
              (toolchainFor fenixPkgs)
              pkgs.cargo-nextest
            ];
          };
        }
      );

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt-rfc-style);
    };
}
