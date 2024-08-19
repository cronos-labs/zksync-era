{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";

  inputs.zksync-era.url = "github:matter-labs/zksync-era/core-v24.9.0";

  inputs.zksync-era.flake = false;

  outputs = {
    flake-utils,
    nixpkgs,
    rust-overlay,
    self,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [(import rust-overlay)];
      };
    in
      with pkgs; let
        rustPlatform' = makeRustPlatform {
          cargo = rust-bin.fromRustupToolchainFile (inputs.zksync-era + /rust-toolchain);
          rustc = rust-bin.fromRustupToolchainFile (inputs.zksync-era + /rust-toolchain);
        };
        base-image-mainnet = dockerTools.pullImage {
          finalImageTag = "mainnet-v24.9.0";
          imageDigest = "sha256:aeaa2825da75b00fbd63e5f7f9dbd825098b1b068ed7397a479e9860b077af42";
          imageName = "ghcr.io/cronos-labs/zkevm-base-image";
          sha256 = "sha256-9XuuqBBgNcRXkB4iJ9oSYzx5wUaMXgVIj602uDvPdcQ=";
        };
        external-node = rustPlatform'.buildRustPackage.override {stdenv = clangStdenv;} {
          buildInputs = [openssl];
          cargoBuildFlags = "--bin zksync_external_node";
          cargoHash = "sha256-VercmY4EjkkTbcvHV/aH1SRNm84XzAjzgLalT2ESYJo=";
          doCheck = false;
          nativeBuildInputs = [pkg-config rustPlatform.bindgenHook];
          pname = "external-node";
          src = inputs.zksync-era + /.;
          version = "dummy";
        };
      in {
        packages.mainnet = dockerTools.buildImage {
          name = "mainnet";
          tag = "nix";
          fromImage = base-image-mainnet;
          copyToRoot = buildEnv {
            name = "image-root";
            paths = [
              bashInteractive
              coreutils
              dockerTools.caCertificates
            ];
          };
          config.Cmd = pkgs.writeScript "cmd" ''
            #!${bash}/bin/bash
            ${sqlx-cli}/bin/sqlx database setup
            exec ${external-node}/bin/zksync_external_node "$@"
          '';
        };
      });
}
