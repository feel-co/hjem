{
  lib,
  rustPlatform,
  enableMulticall ? true,
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
        (s + /crates)
        (s + /Cargo.lock)
        (s + /Cargo.toml)
      ];
    };

  cargoLock.lockFile = "${finalAttrs.src}/Cargo.lock";
  cargoBuildFlags = ["-p" "hjem"];
  cargoCheckFlags = ["-p" "hjem"];

  postInstall = lib.optionalString enableMulticall ''
    for name in "hjem-standalone" "hjem-internal"; do
      ln -s "$out/bin/hjem" "$out/bin/$name"
    done
  '';

  meta = {
    description = "Hjem standalone CLI";
    license = lib.licenses.mpl20;
    mainProgram = "hjem";
    maintainers = [lib.teams.feel-co];
    platforms = lib.platforms.unix;
  };
})
