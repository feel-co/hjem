pkgs:
pkgs.writeShellApplication {
  name = "nix3-fmt-wrapper";

  runtimeInputs = [
    pkgs.alejandra
    pkgs.fd
  ];

  text = ''
    fd "$@" -t f -e nix -x alejandra -q '{}'
  '';
}
