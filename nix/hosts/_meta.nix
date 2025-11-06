{
  framework = {
    imports = [ ./framework ];
    tags = [ "framework" "local" "desktop" ];
    targetHost = "localhost";
    allowLocalDeployment = true;
  };

  tail = {
    imports = [ ./tail ];
    tags = [ "tail" "server" ];
    targetHost = "10.0.30.79";
  };
}
