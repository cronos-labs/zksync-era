{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.std.url = "github:divnix/std";

  inputs.ml-zksync-24-3-0.url = "github:matter-labs/zksync-era/core-v24.3.0";
  inputs.ml-zksync-24-6-0.url = "github:matter-labs/zksync-era/core-v24.6.0";
  inputs.zkevm-23-0-0.url = "github:cronos-labs/cronos-zkevm/testnet-23.0.0";
  inputs.zkevm-24-0-0.url = "github:cronos-labs/cronos-zkevm/testnet-v24.0.0";
  inputs.zkevm-24-0-0-validium-fix.url = "github:cronos-labs/cronos-zkevm/testnet-v24.0.0-validium-fix";
  inputs.zkevm-24-2-0.url = "github:cronos-labs/cronos-zkevm/testnet-v24.2.0";
  inputs.zkevm-24-2-0-add-log-seal-criteria.url = "github:cronos-labs/cronos-zkevm/thomas/add-log-seal-criteria";

  inputs.ml-zksync-24-3-0.flake = false;
  inputs.ml-zksync-24-6-0.flake = false;
  inputs.zkevm-23-0-0.flake = false;
  inputs.zkevm-24-0-0.flake = false;
  inputs.zkevm-24-0-0-validium-fix.flake = false;
  inputs.zkevm-24-2-0.flake = false;
  inputs.zkevm-24-2-0-add-log-seal-criteria.flake = false;

  outputs = {
    self,
    std,
    ...
  } @ inputs:
    std.growOn {
      inherit inputs;
      cellsFrom = ./nix;
      cellBlocks = with std.blockTypes; [
        (installables "en" {ci.build = false;})
        (installables "prover" {ci.build = false;})
        (installables "server" {ci.build = false;})
      ];
    } {
      packages = std.harvest self [["local" "en"] ["local" "prover"] ["local" "server"]];
    };
}
