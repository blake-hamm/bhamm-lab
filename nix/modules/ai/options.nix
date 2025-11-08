{ lib, ... }:

{
  options.cfg.ai = {
    llama-cpp.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the llama-cpp service";
    };
  };
}
