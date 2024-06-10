return {
  "mfussenegger/nvim-jdtls",
  dependencies = { "folke/which-key.nvim" },
  ft = { "java" },
  opts = function()
    return {
      root_dir = require("lspconfig.server_configurations.jdtls").default_config.root_dir,
      project_name = function(root_dir)
        return root_dir and vim.fs.basename(root_dir)
      end,
      jdtls_config_dir = function(project_name)
        return vim.fn.stdpath("cache") .. "/jdtls/" .. project_name .. "/config"
      end,
      jdtls_workspace_dir = function(project_name)
        return vim.fn.stdpath("cache") .. "/jdtls/" .. project_name .. "/workspace"
      end,
      cmd = { vim.fn.exepath("jdtls") },
      full_cmd = function(opts)
        local fname = vim.api.nvim_buf_get_name(0)
        local root_dir = opts.root_dir(fname)
        local project_name = opts.project_name(root_dir)
        local cmd = vim.deepcopy(opts.cmd)
        if project_name then
          vim.list_extend(cmd, {
            "-configuration",
            opts.jdtls_config_dir(project_name),
            "-data",
            opts.jdtls_workspace_dir(project_name),
          })
        end
        return cmd
      end,
      dap = { hotcodereplace = "auto", config_overrides = {} },
      dap_main = {},
      test = true,
      settings = {
        java = {
          inlayHints = {
            parameterNames = {
              enabled = "all",
            },
          },
        },
      },
    }
  end,
  config = function(_, opts)
    local mason_registry = require("mason-registry")
    local bundles = {}
    if opts.dap and require("lazyvim.util").has("nvim-dap") and mason_registry.is_installed("java-debug-adapter") then
      local java_dbg_pkg = mason_registry.get_package("java-debug-adapter")
      local java_dbg_path = java_dbg_pkg:get_install_path()
      local jar_patterns = {
        java_dbg_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar",
      }
      if opts.test and mason_registry.is_installed("java-test") then
        local java_test_pkg = mason_registry.get_package("java-test")
        local java_test_path = java_test_pkg:get_install_path()
        vim.list_extend(jar_patterns, {
          java_test_path .. "/extension/server/*.jar",
        })
      end
      for _, jar_pattern in ipairs(jar_patterns) do
        for _, bundle in ipairs(vim.split(vim.fn.glob(jar_pattern), "\n")) do
          table.insert(bundles, bundle)
        end
      end
    end

    -- Função para criar arquivo de teste
    local function create_test_file()
      local fname = vim.api.nvim_buf_get_name(0)
      local root_dir = opts.root_dir(fname)
      local relative_path = fname:sub(#root_dir + 2)
      local test_path = "src/test/java/" .. relative_path:gsub("src/main/java/", ""):gsub(".java$", "Test.java")

      -- Cria diretórios se não existirem
      vim.fn.mkdir(vim.fn.fnamemodify(test_path, ":h"), "p")

      -- Verifica se o arquivo de teste já existe
      if vim.fn.filereadable(test_path) == 0 then
        local class_name = relative_path:match("([^/]+)%.java$")
        local test_class_name = class_name .. "Test"
        local package_name = relative_path:match("^(.+)/[^/]+%.java$"):gsub("/", ".")

        -- Obtém a lista de métodos públicos da classe
        local methods = {}
        for line in io.lines(fname) do
          local method = line:match("public%s+[%w<>%[%]]+%s+([%w_]+)%s*%(")
          if method then
            table.insert(methods, method)
          end
        end

        -- Solicita ao usuário para selecionar os métodos a serem testados
        local selected_methods = {}
        for _, method in ipairs(methods) do
          local input = vim.fn.input("Testar método " .. method .. "? (s/n): ")
          if input:lower() == "s" then
            table.insert(selected_methods, method)
          end
        end

        -- Escreve o esqueleto do arquivo de teste
        local lines = {
          "package " .. package_name .. ";",
          "",
          "import org.junit.jupiter.api.Test;",
          "import static org.junit.jupiter.api.Assertions.*;",
          "",
          "public class " .. test_class_name .. " {",
          "",
        }
        for _, method in ipairs(selected_methods) do
          table.insert(lines, "    @Test")
          table.insert(lines, "    public void test" .. method .. "() {")
          table.insert(lines, "        // TODO: Add test logic for " .. method)
          table.insert(lines, "    }")
          table.insert(lines, "")
        end
        table.insert(lines, "}")
        vim.fn.writefile(lines, test_path)
      end

      -- Abre o arquivo de teste
      vim.cmd("edit " .. test_path)
    end

    local function attach_jdtls()
      local fname = vim.api.nvim_buf_get_name(0)
      local config = vim.tbl_deep_extend("force", {
        cmd = opts.full_cmd(opts),
        root_dir = opts.root_dir(fname),
        init_options = {
          bundles = bundles,
        },
        settings = opts.settings,
        capabilities = require("cmp_nvim_lsp").default_capabilities(),
      }, opts.jdtls or {})

      require("jdtls").start_or_attach(config)
    end

    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "java" },
      callback = attach_jdtls,
    })

    vim.api.nvim_create_autocmd("LspAttach", {
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and client.name == "jdtls" then
          local wk = require("which-key")
          wk.register({
            ["<leader>cx"] = { name = "+extract" },
            ["<leader>cxv"] = { require("jdtls").extract_variable_all, "Extract Variable" },
            ["<leader>cxc"] = { require("jdtls").extract_constant, "Extract Constant" },
            ["gs"] = { require("jdtls").super_implementation, "Goto Super" },
            ["gS"] = { require("jdtls.tests").goto_subjects, "Goto Subjects" },
            ["<leader>co"] = { require("jdtls").organize_imports, "Organize Imports" },
          }, { mode = "n", buffer = args.buf })
          wk.register({
            ["<leader>c"] = { name = "+code" },
            ["<leader>cx"] = { name = "+extract" },
            ["<leader>cxm"] = {
              [[<ESC><CMD>lua require('jdtls').extract_method(true)<CR>]],
              "Extract Method",
            },
            ["<leader>cxv"] = {
              [[<ESC><CMD>lua require('jdtls').extract_variable_all(true)<CR>]],
              "Extract Variable",
            },
            ["<leader>cxc"] = {
              [[<ESC><CMD>lua require('jdtls').extract_constant(true)<CR>]],
              "Extract Constant",
            },
          }, { mode = "v", buffer = args.buf })

          if
            opts.dap
            and require("lazyvim.util").has("nvim-dap")
            and mason_registry.is_installed("java-debug-adapter")
          then
            require("jdtls").setup_dap(opts.dap)
            require("jdtls.dap").setup_dap_main_class_configs(opts.dap_main)

            if opts.test and mason_registry.is_installed("java-test") then
              wk.register({
                ["<leader>t"] = { name = "+test" },
                ["<leader>tt"] = { require("jdtls.dap").test_class, "Run All Test" },
                ["<leader>tr"] = { require("jdtls.dap").test_nearest_method, "Run Nearest Test" },
                ["<leader>tT"] = { require("jdtls.dap").pick_test, "Run Test" },
                ["<leader>ta"] = { create_test_file, "Create Test File" }, -- Registrar o novo atalho
              }, { mode = "n", buffer = args.buf })
            end
          end

          if opts.on_attach then
            opts.on_attach(args)
          end
        end
      end,
    })

    attach_jdtls()
  end,
}
