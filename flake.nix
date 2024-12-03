{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";

  inputs.zksync-era-mainnet.url = "github:matter-labs/zksync-era/core-v25.0.0";
  inputs.zksync-era-testnet.url = "github:matter-labs/zksync-era/core-v25.0.0";

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
          finalImageTag = "mainnet-v25.0.0";
          imageDigest = "sha256:0dee5f8302fea4517e63e31819db96e8f1382f8e4046a660de975581bf3eeea2";
          imageName = "ghcr.io/cronos-labs/zkevm-base-image";
          sha256 = "sha256-B1KUPH9C4+yx99u7LLR95FYDNn+n5QurGQF61IAb6iA=";
        };
        base-image-testnet = dockerTools'.pullImage {
          finalImageTag = "testnet-v25.0.0";
          imageDigest = "sha256:c7dce7784c80b71219ecfec915faab46f46110d27be6cbe906e4745253e1cd0f";
          imageName = "ghcr.io/cronos-labs/zkevm-base-image";
          sha256 = "sha256-8CShbfqjt9QKuhLXeynDEfYlEluLQo7M+W15Vpq5yz8=";
        };
        external-node-mainnet = rustPlatform-mainnet.buildRustPackage.override {stdenv = clangStdenv;} {
          buildInputs = [openssl];
          cargoBuildFlags = "--bin zksync_external_node";
          cargoLock = {
            lockFile = inputs.zksync-era-mainnet + /Cargo.lock;
            outputHashes = {
              "zksync_vm2-0.2.1" = "sha256-fH8w6MiL11BIW55Hs6kqxWJKDOkr7Skr7wXQCk+x48U=";
            };
          };
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
              "zksync_vm2-0.2.1" = "sha256-fH8w6MiL11BIW55Hs6kqxWJKDOkr7Skr7wXQCk+x48U=";
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
