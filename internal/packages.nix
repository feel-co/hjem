{
  hjemModule,
  nixpkgs,
  pkgs,
}: let
  docs = pkgs.callPackage ../docs/package.nix {inherit hjemModule nixpkgs;};
in {
  hjem = pkgs.callPackage ../cli/package.nix {};

  # Hjem documentation. 'docs-html' contains the HTML document created by ndg
  # and docs-json contains a standalone 'options.json' that is also fed to ndg
  # for third party consumption.
  docs-html = docs.html;
  docs-json = docs.options.json;
}
