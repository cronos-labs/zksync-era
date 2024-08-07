let
  tag = "v24.9.0";
  tag-testnet = "v24.9.0-testnet";
  base-image = inputs.n2c.packages.nix2container.pullImage {
    imageName = "ghcr.io/cronos-labs/zkevm-base-image";
    imageDigest = "sha256:aeaa2825da75b00fbd63e5f7f9dbd825098b1b068ed7397a479e9860b077af42";
    sha256 = "sha256-9XuuqBBgNcRXkB4iJ9oSYzx5wUaMXgVIj602uDvPdcQ=";
  };
  base-image-testnet = inputs.n2c.packages.nix2container.pullImage {
    imageName = "ghcr.io/cronos-labs/zkevm-base-image";
    imageDigest = "sha256:28a7022cda8e5aa6abffd296213b9d01261846a9557d66f86dcdf6720600dbec";
    sha256 = "sha256-L1kADXnCMZeyXPihtGGFCrB/9b/N3RWW9NCLyrjclKE=";
  };
  db = inputs.nixpkgs.runCommand "db" {} ''
    mkdir -p $out/db
  '';
in {
  gh-external-node = inputs.std.lib.ops.mkStandardOCI {
    inherit tag;

    name = "ghcr.io/cronos-labs/external-node";
    setup = [db];
    perms = [
      {
        path = db;
        regex = ".*";
        mode = "0777";
      }
    ];
    operable = cell.operables.external-node;
    options.fromImage = base-image;
  };
  gh-external-node-testnet = inputs.std.lib.ops.mkStandardOCI {
    tag = tag-testnet;

    name = "ghcr.io/cronos-labs/external-node";
    setup = [db];
    perms = [
      {
        path = db;
        regex = ".*";
        mode = "0777";
      }
    ];
    operable = cell.operables.external-node-testnet;
    options.fromImage = base-image-testnet;
  };
}
