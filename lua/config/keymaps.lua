-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

--------------------------------------------------------------------------------
-- C 语言：一键编译 / 运行
--------------------------------------------------------------------------------

--- 编译当前 C 文件，成功返回 exe 路径，失败返回 nil（错误进 quickfix）
---@return string?
local function c_compile()
  if vim.bo.filetype ~= "c" then
    vim.notify("当前 buffer 不是 C 文件", vim.log.levels.WARN)
    return nil
  end

  if vim.fn.executable("gcc") == 0 then
    vim.notify("PATH 里找不到 gcc，先把它加进 PATH 或改 keymaps.lua 里的编译器", vim.log.levels.ERROR)
    return nil
  end

  vim.cmd("write")
  local src = vim.fn.expand("%:p")
  local exe = vim.fn.expand("%:p:r") .. ".exe"
  local out = vim.fn.system({ "gcc", "-g", "-Wall", "-Wextra", "-std=c17", src, "-o", exe })

  if vim.v.shell_error ~= 0 then
    vim.fn.setqflist({}, "r", {
      title = "gcc",
      lines = vim.split(out, "\n"),
      efm = "%f:%l:%c: %t%*[^:]: %m,%f:%l:%c: %m",
    })
    vim.notify("编译失败，错误在 quickfix：<leader>xQ 或 :copen", vim.log.levels.ERROR)
    return nil
  end

  -- 成功但有警告时也提示一下
  if out ~= "" then
    vim.notify(out, vim.log.levels.WARN)
  end
  return exe
end

-- <F5> 编译并运行
vim.keymap.set("n", "<F5>", function()
  local exe = c_compile()
  if not exe then
    return
  end
  vim.cmd("botright split")
  vim.cmd("terminal " .. vim.fn.shellescape(exe))
  vim.cmd("startinsert")
end, { desc = "C: 编译并运行" })

-- <F6> 只编译，不运行
vim.keymap.set("n", "<F6>", function()
  if c_compile() then
    vim.notify("编译成功", vim.log.levels.INFO)
  end
end, { desc = "C: 只编译" })
