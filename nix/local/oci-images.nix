let
  tag = "v24.9.0";
  base-image = inputs.n2c.packages.nix2container.pullImage {
    imageName = "ghcr.io/cronos-labs/zkevm-base-image";
    imageDigest = "sha256:aeaa2825da75b00fbd63e5f7f9dbd825098b1b068ed7397a479e9860b077af42";
    sha256 = "sha256-9XuuqBBgNcRXkB4iJ9oSYzx5wUaMXgVIj602uDvPdcQ=";
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
}
