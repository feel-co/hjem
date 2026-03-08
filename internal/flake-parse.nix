inputName: let
  lock = builtins.fromJSON (builtins.readFile ../flake.lock);
  namedNode = lock.nodes.${lock.nodes.root.inputs.${inputName}};
  namedLockedNode = namedNode.locked;
  githubTarball = fetchTarball {
    url = namedNode.original.url or "https://github.com/${namedLockedNode.owner}/${namedLockedNode.repo}/archive/${namedLockedNode.rev}.tar.gz";
    sha256 = namedLockedNode.narHash;
  };
in
  githubTarball
