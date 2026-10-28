return {
  {
    "andy12241025/mdict.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = function()
      require("mdict").setup({
        -- 你的mdx路径
        dicts = {
          "D:/dict mdd/cambridge/cambridge4_2.mdx",
        },
      })

      vim.keymap.set("n", "<leader>d", "<cmd>Mdict<CR>", { desc = "Search dictionary" })
    end,
  },
}
