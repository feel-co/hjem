inputName: let
  lock = builtins.fromJSON (builtins.readFile ../flake.lock);
  namedNode = lock.nodes.${lock.nodes.root.inputs.${inputName}}.locked;
  githubTarball = fetchTarball {
    url = "https://github.com/${namedNode.owner}/${namedNode.repo}/archive/${namedNode.rev}.tar.gz";
    sha256 = namedNode.narHash;
  };
in
  githubTarball
