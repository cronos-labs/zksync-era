{
  external-node =
    inputs.std.lib.ops.mkOperable rec
    {
      runtimeInputs = [inputs.nixpkgs.bashInteractive inputs.nixpkgs.coreutils];
      package = cell.en.external-node;
      runtimeScript = ''
        exec ${package}/bin/zksync_external_node "$@"
      '';
    };
}
