{ config, lib, shared, ... }:

{
  options.cfg.neovim.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Neovim via nvf";
  };

  config = lib.mkIf config.cfg.neovim.enable {
    home-manager.users.${shared.username} = {
      programs.nvf = {
        enable = true;
        settings = {
          vim.viAlias = true;
          vim.vimAlias = true;

          vim.globals.mapleader = " ";

          vim.theme = {
            enable = true;
            name = "catppuccin";
            style = "mocha";
          };

          vim.statusline.lualine.enable = true;
          vim.tabline.nvimBufferline.enable = true;
          vim.filetree.neo-tree = {
            enable = true;
            setupOpts = {
              window.position = "left";
              window.width = 35;
              filesystem.filtered_items.visible = true;
              filesystem.hijack_netrw_behavior = "open_default";
              close_if_last_window = false;
            };
          };
          vim.telescope.enable = true;
          vim.git.gitsigns.enable = true;
          vim.binds.whichKey.enable = true;
          vim.terminal.toggleterm.enable = true;
          vim.visuals.nvim-web-devicons.enable = true;

          vim.treesitter.enable = true;
          vim.autocomplete.nvim-cmp.enable = true;
          vim.comments.comment-nvim.enable = true;
          vim.visuals.indent-blankline.enable = true;

          vim.keymaps = [
            {
              key = "<leader>e";
              mode = "n";
              silent = true;
              action = "<cmd>Neotree toggle<CR>";
            }
          ];

          vim.lsp = {
            enable = true;
            formatOnSave = true;
          };

          vim.languages = {
            enableFormat = true;
            enableTreesitter = true;
            enableExtraDiagnostics = true;

            nix.enable = true;
            terraform.enable = true;
            python.enable = true;
            rust.enable = true;
            markdown.enable = true;
            yaml.enable = true;
            json.enable = true;
            bash.enable = true;
            lua.enable = true;
            hcl.enable = true;
            html.enable = true;
            css.enable = true;
            typescript.enable = true;
          };
        };
      };
    };
  };
}
