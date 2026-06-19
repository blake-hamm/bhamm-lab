{ config, lib, shared, pkgs, ... }:

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
          vim.telescope = {
            enable = true;
            setupOpts.pickers.find_files.find_command = [
              "${pkgs.fd}/bin/fd"
              "--type=file"
              "--hidden"
              "--no-ignore"
            ];
          };
          vim.git.gitsigns.enable = true;
          vim.git.gitsigns.codeActions.enable = true;

          vim.extraPlugins = {
            diffview = {
              package = pkgs.vimPlugins.diffview-nvim;
              setup = ''
                require('diffview').setup {
                  keymaps = {
                    disable_defaults = false,
                    view = {
                      { "n", "<leader>gq", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                    },
                    file_panel = {
                      { "n", "<leader>gq", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                      { "n", "q",          "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                    },
                    file_history_panel = {
                      { "n", "<leader>gq", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                      { "n", "q",          "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                    },
                  },
                }
              '';
            };
          };

          vim.binds.whichKey.enable = true;
          vim.terminal.toggleterm.enable = true;
          vim.visuals.nvim-web-devicons.enable = true;

          vim.clipboard = {
            enable = true;
            registers = "unnamedplus";
            providers.wl-copy.enable = true;
          };

          vim.treesitter.enable = true;
          vim.autocomplete.nvim-cmp.enable = true;
          vim.comments.comment-nvim.enable = true;
          vim.visuals.indent-blankline.enable = true;

          vim.keymaps = [
            {
              key = "<leader>gd";
              mode = "n";
              silent = true;
              action = "<cmd>DiffviewOpen<CR>";
              desc = "Open diffview (all changes)";
            }
            {
              key = "<leader>gh";
              mode = "n";
              silent = true;
              action = "<cmd>DiffviewFileHistory %<CR>";
              desc = "File git history";
            }
            {
              key = "<leader>gq";
              mode = "n";
              silent = true;
              action = "<cmd>DiffviewClose<CR>";
              desc = "Close diffview";
            }
            {
              key = "<leader>e";
              mode = "n";
              silent = true;
              action = "<cmd>Neotree toggle<CR>";
            }
          ];

          vim.autocmds = [
            {
              event = [ "BufRead" "BufNewFile" ];
              pattern = [ "*.env" ".env.*" ];
              desc = "Set env files to conf filetype to avoid sh tooling";
              command = "setfiletype conf";
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
