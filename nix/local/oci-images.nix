let
  tag = "v24.2.0";
  base-image = inputs.n2c.packages.nix2container.pullImage {
    imageName = "ghcr.io/cronos-labs/zkevm-base-image";
    imageDigest = "sha256:840122a8d59f0ace77359c2b39b0bd9f2176017b20425b9b6c8ecf77e4bcda1f";
    sha256 = "sha256-whqlf7FEGYqCPkU/bWBQp1+f/7JeljcoJln3ctYK/H0=";
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
