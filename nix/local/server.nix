let
  zkevm = inputs.zkevm-24-2-0-fix-eth-sender;

  cargoHash = "sha256-rqz3WEDf/4MMroCKIR1rx0L1J1KuqZ/o/bh0PRns4bY=";

  pkgs = import inputs.nixpkgs {
    inherit (inputs.nixpkgs) system;
    overlays = [inputs.rust-overlay.overlays.default];
  };

  # patched version of cargo to support `cargo vendor` for vendoring dependencies
  # see https://github.com/matter-labs/zksync-era/issues/1086
  # used as `cargo vendor --no-merge-sources`
  cargo-vendor = pkgs.rustPlatform.buildRustPackage rec {
    pname = "cargo-vendor";
    version = "0.78.0";
    src = pkgs.fetchFromGitHub {
      owner = "haraldh";
      repo = "cargo";
      rev = "3ee1557d2bd95ca9d0224c5dbf1d1e2d67186455";
      hash = "sha256-A8xrOG+NmF8dQ7tA9I2vJSNHlYxsH44ZRXdptLblCXk=";
    };
    doCheck = false;
    cargoHash = "sha256-LtuNtdoX+FF/bG5LQc+L2HkFmgCtw5xM/m0/0ShlX2s=";
    nativeBuildInputs = [
      pkgs.pkg-config
      pkgs.rustPlatform.bindgenHook
    ];
    buildInputs = [
      pkgs.openssl
    ];
  };

  # custom import-cargo-lock to import Cargo.lock file and vendor dependencies
  # see https://github.com/matter-labs/zksync-era/issues/1086
  import-cargo-lock = {
    lib,
    cacert,
    runCommand,
  }: {
    src,
    cargoHash ? null,
  } @ args:
    runCommand "import-cargo-lock"
    {
      inherit src;
      nativeBuildInputs = [cargo-vendor cacert];
      preferLocalBuild = true;
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash =
        if cargoHash != null
        then cargoHash
        else lib.fakeSha256;
    }
    ''
      mkdir -p $out/.cargo
      mkdir -p $out/cargo-vendor-dir

      HOME=$(pwd)
      pushd ${src}
      HOME=$HOME cargo vendor --no-merge-sources $out/cargo-vendor-dir > $out/.cargo/config
      sed -i -e "s#$out#import-cargo-lock#g" $out/.cargo/config
      cp $(pwd)/Cargo.lock $out/Cargo.lock
      popd
    '';
  cargoDeps = pkgs.buildPackages.callPackage import-cargo-lock {} {
    inherit src;
    inherit cargoHash;
  };

  rustVersion = pkgs.rust-bin.fromRustupToolchainFile (zkevm + /rust-toolchain);

  stdenv = pkgs.stdenvAdapters.useMoldLinker pkgs.clangStdenv;

  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustVersion;
    rustc = rustVersion;
    inherit stdenv;
  };

  hardeningEnable = ["fortify3" "pie" "relro"];

  src = with pkgs.lib.fileset;
    toSource rec {
      root = /. + "/nix/store" + builtins.elemAt (builtins.split "/nix/store" zkevm.outPath) 2;
      fileset = unions [
        (root + /Cargo.lock)
        (root + /Cargo.toml)
        (root + /core)
        (root + /prover)
        (root + /.github/release-please/manifest.json)
      ];
    };

  server = with pkgs;
    stdenv.mkDerivation {
      pname = "server";
      version = "1.0.0";

      updateAutotoolsGnuConfigScriptsPhase = ":";

      nativeBuildInputs = [
        pkg-config
        rustPlatform.bindgenHook
        rustPlatform.cargoSetupHook
        rustPlatform.cargoBuildHook
        rustPlatform.cargoInstallHook
      ];

      buildInputs = [
        libclang
        openssl
        snappy.dev
        lz4.dev
        bzip2.dev
      ];

      inherit src;
      cargoBuildFlags = "--all";
      cargoBuildType = "release";
      inherit cargoDeps;

      inherit hardeningEnable;

      outputs = [
        "out"
        "contract_verifier"
        "external_node"
        "server"
        "snapshots_creator"
        "block_reverter"
      ];

      postInstall = ''
        for i in $outputs; do
          [[ $i == "out" ]] && continue
          mkdir -p "''${!i}/bin"
          if [[ -e "$out/bin/zksync_$i" ]]; then
            mv "$out/bin/zksync_$i" "''${!i}/bin"
          else
            mv "$out/bin/$i" "''${!i}/bin"
          fi
        done
      '';
    };
in {
  inherit server;
}
