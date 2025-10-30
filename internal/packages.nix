{
  hjemModule,
  ndg,
  nixpkgs,
  pkgs,
  smfh,
}: let
  docs = pkgs.callPackage ../docs/package.nix {inherit hjemModule ndg nixpkgs;};
in {
  # Expose the 'smfh' instance used by Hjem as a package.
  # This allows consuming the exact copy of smfh used by Hjem.
  inherit smfh;

  # Hjem documentation. 'docs-html' contains the HTML document created by ndg
  # and docs-json contains a standalone 'options.json' that is also fed to ndg
  # for third party consumption.
  docs-html = docs.html;
  docs-json = docs.options.json;
}
