{ pkgs, inputs, system, host, username, ... }:
{
  services.logind.lidSwitch = "ignore";

  # Laptop charger poetry2nix app in packages/laptop-charger
  systemd = {
    services."manage_charger" = {
      path = with pkgs; [
        inputs.manage_charger.packages."${system}".manage_charger
      ];
      script = ''
        manage_charger --plug-alias ${host}
      '';
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = "60s";
        StartLimitBurst = "10";
        StartLimitInterval = "5min";
      };
    };
    timers."manage_charger" = {
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "15m";
        Persistent = true;
        Unit = "manage_charger.service";
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
