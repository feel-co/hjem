{
  hjemModule,
  nixpkgs,
  pkgs,
}: let
  docs = pkgs.callPackage ../docs/package.nix {inherit hjemModule nixpkgs;};
in {
  hjem = pkgs.callPackage ../cli/package.nix {};

  # Hjem documentation. 'docs-html' contains the HTML document created by ndg,
  # 'docs-man' contains the generated manpage, and docs-json contains a
  # standalone 'options.json' that is also fed to ndg for third party
  # consumption.
  docs-html = docs.html;
  docs-man = docs.man;
  docs-json = docs.options.json;
}
