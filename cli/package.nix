{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "hjem-cli";
  version = "0.1.0";

  src = let
    fs = lib.fileset;
    s = ./.;
  in
    fs.toSource {
      root = s;
      fileset = fs.unions [
        (s + /src)
        (s + /Cargo.lock)
        (s + /Cargo.toml)
      ];
    };

  cargoLock.lockFile = "${finalAttrs.src}/Cargo.lock";

  meta = {
    description = "Hjem standalone CLI";
    mainProgram = "hjem";
    license = lib.licenses.mpl20;
    platforms = lib.platforms.unix;
  };
})
