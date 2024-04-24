{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.std.url = "github:divnix/std";

  inputs.zkevm-23-0-0.url = "github:cronos-labs/cronos-zkevm/testnet-23.0.0";

  inputs.zkevm-23-0-0.flake = false;

  outputs = {
    self,
    std,
    ...
  } @ inputs:
    std.growOn {
      inherit inputs;
      cellsFrom = ./nix;
      cellBlocks = with std.blockTypes; [
        (installables "prover" {ci.build = false;})
        (installables "server" {ci.build = false;})
      ];
    } {
      packages = std.harvest self [["local" "prover"] ["local" "server"]];
    };
}
