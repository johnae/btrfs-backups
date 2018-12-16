with import <nixpkgs> {};

with lib;
with builtins;

let
  setToStringSep = sep: x: fun: concatStringsSep sep (mapAttrsToList fun x);
  toMultiLineString = setToStringSep "\n";
in
  stdenv.mkDerivation {
    name = "btrfs-backups";
    buildInputs = [ docker coreutils gawk ];
  }