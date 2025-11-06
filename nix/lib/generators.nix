{ lib, shared, self, inputs, hosts }:
let
  mkDeployment = hostName: hostAttrs: {
    deployment = {
      inherit (hostAttrs) tags targetHost;
      allowLocalDeployment = hostAttrs.allowLocalDeployment or false;
      targetUser = shared.username;
      targetPort = shared.sshPort;
    };
    imports = hostAttrs.imports;
  };

  generateColmena = lib.mapAttrs mkDeployment hosts;

  mkNixosConfig = hostName: hostAttrs:
    lib.nixosSystem {
      system = shared.system;
      specialArgs = { inherit self inputs shared; host = hostName; };
      modules = hostAttrs.imports;
    };

  generateNixosConfigurations = lib.mapAttrs mkNixosConfig hosts;

  mkNodeSpecialArgs = hostName: hostAttrs: { host = hostName; };

  generateNodeSpecialArgs = lib.mapAttrs mkNodeSpecialArgs hosts;
in
{
  inherit
    generateColmena
    generateNixosConfigurations
    generateNodeSpecialArgs
    ;
}
