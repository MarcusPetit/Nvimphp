return {
  {
    "scottmckendry/cyberdream.nvim",
    lazy = true,
    priority = 1000,
    opts = function()
      return {
        transparent_background = true, -- Ativar fundo transparente
        terminal_colors = true, -- Usar cores do terminalS
        transparent = true,
      }
    end,
  },
}
