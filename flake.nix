{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";

  inputs.zksync-era-mainnet.url = "github:matter-labs/zksync-era/core-v24.23.0";
  inputs.zksync-era-testnet.url = "github:matter-labs/zksync-era/core-v24.23.0";

  inputs.zksync-era-mainnet.flake = false;
  inputs.zksync-era-testnet.flake = false;

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
        rustPlatform-mainnet = makeRustPlatform {
          cargo = rust-bin.fromRustupToolchainFile (inputs.zksync-era-mainnet + /rust-toolchain);
          rustc = rust-bin.fromRustupToolchainFile (inputs.zksync-era-mainnet + /rust-toolchain);
        };
        rustPlatform-testnet = makeRustPlatform {
          cargo = rust-bin.fromRustupToolchainFile (inputs.zksync-era-testnet + /rust-toolchain);
          rustc = rust-bin.fromRustupToolchainFile (inputs.zksync-era-testnet + /rust-toolchain);
        };
        dockerTools' = dockerTools.override {
          skopeo = pkgs.writeScriptBin "skopeo" ''exec ${skopeo}/bin/skopeo "$@" --authfile=/etc/docker/config.json'';
        };
        base-image-mainnet = dockerTools'.pullImage {
          finalImageTag = "mainnet-v24.23.0";
          imageDigest = "sha256:adde524ccb4803843ab8243c85224d05a86b7ba31503d5b895cc7a362fe4f875";
          imageName = "ghcr.io/cronos-labs/zkevm-base-image";
          sha256 = "sha256-BdwoSJbcxefz/IYv/nhskBk/oiwQyFooHSEs9dv5VxA=";
        };
        base-image-testnet = dockerTools'.pullImage {
          finalImageTag = "testnet-v24.23.0";
          imageDigest = "sha256:e7495ec76b812b1fc2aa81e0bca3e6b286debf5a0981ab24ef9209c4180d2e7b";
          imageName = "ghcr.io/cronos-labs/zkevm-base-image";
          sha256 = "sha256-jOpofixUYcp0irE4LaLYx56tiDiAtr1ZB12EiWbPG2I=";
        };
        external-node-mainnet = rustPlatform-mainnet.buildRustPackage.override {stdenv = clangStdenv;} {
          buildInputs = [openssl];
          cargoBuildFlags = "--bin zksync_external_node";
          cargoHash = "sha256-VercmY4EjkkTbcvHV/aH1SRNm84XzAjzgLalT2ESYJo=";
          doCheck = false;
          nativeBuildInputs = [pkg-config rustPlatform.bindgenHook];
          pname = "external-node";
          src = inputs.zksync-era-mainnet + /.;
          version = "dummy";
        };
        external-node-testnet = rustPlatform-testnet.buildRustPackage.override {stdenv = clangStdenv;} {
          buildInputs = [openssl];
          cargoBuildFlags = "--bin zksync_external_node";
          cargoLock = {
            lockFile = inputs.zksync-era-testnet + /Cargo.lock;
            outputHashes = {
              "vm2-0.1.0" = "sha256-FBCleLufoEHMvkCJ3rMudlWKwf7wAcGStSLeWZmcmgc=";
            };
          };
          doCheck = false;
          nativeBuildInputs = [pkg-config rustPlatform.bindgenHook];
          pname = "external-node";
          src = inputs.zksync-era-testnet + /.;
          version = "dummy";
        };
        start = bin:
          writeTextFile {
            destination = "/bin/start.sh";
            executable = true;
            name = "start.sh";
            text = ''
              #!${bash}/bin/bash
              ${sqlx-cli}/bin/sqlx database setup
              exec ${bin}/bin/zksync_external_node "$@"
            '';
          };
        copyToRoot = buildEnv {
          name = "image-root";
          paths = [
            bashInteractive
            coreutils
            dockerTools.caCertificates
          ];
        };
      in {
        packages.mainnet = dockerTools.buildImage {
          name = "mainnet";
          tag = "nix";
          fromImage = base-image-mainnet;
          inherit copyToRoot;
          config.Entrypoint = ["${start external-node-mainnet}/bin/start.sh"];
        };
        packages.testnet = dockerTools.buildImage {
          name = "testnet";
          tag = "nix";
          fromImage = base-image-testnet;
          inherit copyToRoot;
          config.Entrypoint = ["${start external-node-testnet}/bin/start.sh"];
        };
      });
}
