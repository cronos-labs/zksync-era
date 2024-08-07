{
  external-node =
    inputs.std.lib.ops.mkOperable rec
    {
      runtimeInputs = [inputs.nixpkgs.bashInteractive inputs.nixpkgs.coreutils];
      package = cell.en.en.external_node;
      runtimeScript = ''
        exec ${package}/bin/zksync_external_node "$@"
      '';
    };
  external-node-testnet =
    inputs.std.lib.ops.mkOperable rec
    {
      runtimeInputs = [inputs.nixpkgs.bashInteractive inputs.nixpkgs.coreutils];
      package = cell.packages.external-node-24-9-0-testnet;
      runtimeScript = ''
        exec ${package}/bin/zksync_external_node "$@"
      '';
    };
}
