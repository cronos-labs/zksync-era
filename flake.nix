{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";

  inputs.zksync-era-mainnet.url = "github:matter-labs/zksync-era/core-v24.9.0";
  inputs.zksync-era-testnet.url = "github:cronos-labs/cronos-zkevm/cronos-v24.23.0";

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
          finalImageTag = "mainnet-v24.9.0";
          imageDigest = "sha256:aeaa2825da75b00fbd63e5f7f9dbd825098b1b068ed7397a479e9860b077af42";
          imageName = "ghcr.io/cronos-labs/zkevm-base-image";
          sha256 = "sha256-GQGaojsWBf0QNRSAj6vQAS+KElIXIRIBQxaxLEszpEs=";
        };
        base-image-testnet = dockerTools'.pullImage {
          finalImageTag = "testnet-v24.23.0";
          imageDigest = "sha256:53ce8dd43a5721ca69b82db43aa2e87b2b7416c25c9fe63161e4435b25f6078f";
          imageName = "ghcr.io/cronos-labs/zkevm-base-image";
          sha256 = "";
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
          cargoHash = "";
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
