{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";

  inputs.cronos-zkevm-mainnet.url = "github:cronos-labs/cronos-zkevm/cronos_core-v25.0.0";
  inputs.cronos-zkevm-testnet.url = "github:cronos-labs/cronos-zkevm/cronos_core-v25.0.0";

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
        external-node-mainnet = inputs.cronos-zkevm-mainnet.packages.${system}.zksync.external_node;
        external-node-testnet = inputs.cronos-zkevm-testnet.packages.${system}.zksync.external_node;
        entrypoint = bin:
          writeTextFile {
            destination = "/usr/bin/entrypoint.sh";
            executable = true;
            name = "entrypoint.sh";
            text = ''
              #!${bash}/bin/bash
              ${sqlx-cli}/bin/sqlx database setup
              exec ${bin}/bin/zksync_external_node "$@"
            '';
          };
        generateSecrets = bin:
          writeTextFile {
            destination = "/configs/generate_secrets.sh";
            executable = true;
            name = "generate_secrets.sh";
            text = ''
              #!${bash}/bin/bash
              if [ ! -s $1 ]; then
                 ${bin}/bin/zksync_external_node generate-secrets > $1
              fi
            '';
          };
      in {
        packages.external-node-mainnet = external-node-mainnet;
        packages.external-node-testnet = external-node-testnet;
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
              "${entrypoint external-node-mainnet}"
              "${generateSecrets external-node-mainnet}"
            ];
          };
          config.Entrypoint = ["/usr/bin/entrypoint.sh"];
        };
        packages.testnet = dockerTools.buildImage {
          name = "testnet";
          tag = "nix";
          fromImage = base-image-testnet;
          copyToRoot = buildEnv {
            name = "image-root";
            paths = [
              bashInteractive
              coreutils
              dockerTools.caCertificates
              "${entrypoint external-node-testnet}"
              "${generateSecrets external-node-testnet}"
            ];
          };
          config.Entrypoint = ["/usr/bin/entrypoint.sh"];
        };
      });
}
