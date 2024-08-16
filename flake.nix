{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.n2c.url = "github:nlewo/nix2container";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.std.url = "github:divnix/std";

  inputs.std.inputs.n2c.url = "github:nlewo/nix2container";

  inputs.ml-zksync-24-3-0.url = "github:matter-labs/zksync-era/core-v24.3.0";
  inputs.ml-zksync-24-6-0.url = "github:matter-labs/zksync-era/core-v24.6.0";
  inputs.ml-zksync-24-9-0.url = "github:matter-labs/zksync-era/core-v24.9.0";
  inputs.zkevm-23-0-0.url = "github:cronos-labs/cronos-zkevm/testnet-23.0.0";
  inputs.zkevm-24-0-0.url = "github:cronos-labs/cronos-zkevm/testnet-v24.0.0";
  inputs.zkevm-24-0-0-validium-fix.url = "github:cronos-labs/cronos-zkevm/testnet-v24.0.0-validium-fix";
  inputs.zkevm-24-2-0.url = "github:cronos-labs/cronos-zkevm/testnet-v24.2.0";
  inputs.zkevm-24-9-0-testnet.url = "github:cronos-labs/cronos-zkevm/testnet-v24.9.0";

  inputs.ml-zksync-24-3-0.flake = false;
  inputs.ml-zksync-24-6-0.flake = false;
  inputs.ml-zksync-24-9-0.flake = false;
  inputs.zkevm-23-0-0.flake = false;
  inputs.zkevm-24-0-0.flake = false;
  inputs.zkevm-24-0-0-validium-fix.flake = false;
  inputs.zkevm-24-2-0.flake = false;

  outputs = {
    flake-utils,
    self,
    std,
    ...
  } @ inputs:
    std.growOn {
      inherit inputs;
      cellsFrom = ./nix;
      cellBlocks = with std.blockTypes; [
        (containers "oci-images" {ci.publish = true;})
        (installables "en" {ci.build = false;})
        (installables "prover" {ci.build = false;})
        (installables "server" {ci.build = false;})
        (installables "packages")
        (runnables "operables")
      ];
    } {
      packages = std.harvest self [["local" "en"] ["local" "prover"] ["local" "server"] ["local" "packages"]];
    } (
      flake-utils.lib.eachDefaultSystem (system: let
        pkgs = import inputs.nixpkgs {
          crossSystem = "aarch64-linux";
          inherit system;
          overlays = [(import rust-overlay)];
        };
        en = import ./nix/local/en2.nix {inherit pkgs;};
      in
        with pkgs; {
          packages.docker-aarch64-mainnet = dockerTools.buildImage {
            name = "ghci.io/cronos-labs/external-node";
            tag = "v24.9.0-mainnet";
            copyToRoot = buildEnv {
              name = "image-root";
              paths = [dockerTools.caCertificates bashInteractive coreutils en.en.external_node];
            };
            extraCommands = ''
              mkdir -p /db
              chmod 777 /db
            '';
          };
        })
    );
}
