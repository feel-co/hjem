pkgs:
pkgs.mkShell {
  name = "hjem-rust-";
  packages = with pkgs; [
    rustc
    cargo
    clippy
    (rustfmt.override {asNightly = true;})
  ];
}
