{ lib, shared, self, inputs }:
let
  # Discover all potential host directories
  hostEntries = builtins.readDir ../hosts;

  # Filter for actual host directories that have a `deploy` attribute
  deployableHosts =
    lib.filterAttrs (name: value: value != null) (
      lib.mapAttrs
        (hostName: hostType:
          if hostType == "directory" then
            let
              hostModule = import ../hosts/${hostName};
            in
            if hostModule ? "deploy" then hostModule else null
          else
            null
        )
        hostEntries
    );

  # --- Generator Functions ---

  mkDeployment = hostName: hostModule: {
    deployment = {
      inherit (hostModule.deploy) tags targetHost;
      allowLocalDeployment = hostModule.deploy.allowLocalDeployment or false;
      targetUser = shared.username;
      targetPort = shared.sshPort;
    };
    imports = [ (lib.removeAttrs hostModule [ "deploy" ]) ];
  };

  generateColmena = lib.mapAttrs mkDeployment deployableHosts;

  mkNixosConfig = hostName: hostModule:
    lib.nixosSystem {
      system = hostModule.nixpkgs.system;
      specialArgs = { inherit self inputs shared; host = hostName; };
      modules = [ (lib.removeAttrs hostModule [ "deploy" ]) ];
    };

  generateNixosConfigurations = lib.mapAttrs mkNixosConfig deployableHosts;

  mkNodeSpecialArgs = hostName: hostModule: { host = hostName; };

  generateNodeSpecialArgs = lib.mapAttrs mkNodeSpecialArgs deployableHosts;
in
{
  inherit
    generateColmena
    generateNixosConfigurations
    generateNodeSpecialArgs
    ;
}
