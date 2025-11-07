{ config, lib, shared, ... }:

{
  config = lib.mkIf config.cfg.ai.llama-cpp.enable {
    users.users.${shared.username}.extraGroups = [ "docker" ];
    virtualisation.oci-containers = {
      backend = "docker";
      containers = {
        llama-cpp = {
          image = "kyuz0/amd-strix-halo-toolboxes:vulkan-radv";
          cmd = [
            "llama-server"
            "-hf"
            "bartowski/cerebras_GLM-4.5-Air-REAP-82B-A12B-GGUF"
            "-hff"
            "cerebras_GLM-4.5-Air-REAP-82B-A12B-Q4_K_L/cerebras_GLM-4.5-Air-REAP-82B-A12B-Q4_K_L-00001-of-00002.gguf"
            "--host"
            "0.0.0.0"
            "--metrics"
            "--no-webui"
            "--jinja"
            "-v"
            "--timeout"
            "1800"
            "--no-mmap"
            "--no-warmup"
            "-ngl"
            "999"
            "-fa"
            "on"
            "-ub"
            "512"
            "-b"
            "4096"
            "-c"
            "65536"
            "--parallel"
            "1"
            "--temp"
            "0.6"
            "--top-p"
            "0.95"
            "--top-k"
            "40"
          ];
          ports = [ "8080:8080" ];
          volumes = [ "/var/lib/llama-cpp/models:/models" ];
          environment = {
            "LLAMA_CACHE" = "/models/cache";
            "HF_HOME" = "/models/cache/huggingface";
          };
          extraOptions = [
            "--device=/dev/kfd"
            "--device=/dev/dri"
          ];
        };
      };
    };
  };
}
