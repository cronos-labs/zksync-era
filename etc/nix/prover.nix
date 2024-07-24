{
  cargoArtifacts,
  commonArgs,
  craneLib,
  versionSuffix,
}:
craneLib.buildPackage (commonArgs
  // rec {
  pname = "prover";
  version = (builtins.fromTOML (builtins.readFile ../../core/bin/zksync_tee_prover/Cargo.toml)).package.version + versionSuffix;
  cargoExtraArgs = "--all";
  
  src' = commonArgs.src;
  sourceRoot = "${src'.name}/prover";

  outputs = [
    "out"
    "witness_generator"
    "prover_fri"
    "witness_vector_generator"
    "prover_fri_gateway"
    "proof_fri_compressor"
  ];

  inherit cargoArtifacts;

  postInstall = ''
    mkdir -p $out/nix-support
    for i in $outputs; do
      [[ $i == "out" ]] && continue
      mkdir -p "''${!i}/bin"
      echo "''${!i}" >> $out/nix-support/propagated-user-env-packages
      if [[ -e "$out/bin/zksync_$i" ]]; then
        mv "$out/bin/zksync_$i" "''${!i}/bin"
      else
        mv "$out/bin/$i" "''${!i}/bin"
      fi
    done
  '';
})
