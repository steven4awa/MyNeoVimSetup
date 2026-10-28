-- C / C++ 支持
--
-- clangd 本体、clangd_extensions.nvim（inlay hints、AST、<leader>ch 切头文件）
-- 以及 treesitter 的 cpp 解析器，都由 extra `lazyvim.plugins.extras.lang.clangd`
-- 提供（已写进 lazyvim.json）。这个文件只做 extra 没做的三件事：
--
--   1. 给 clangd 加 --query-driver：允许它执行 gcc，从 gcc 那里拿到 MinGW 的系统头文件路径
--   2. 维护 clangd 的用户级配置 %LOCALAPPDATA%\clangd\config.yaml：把 gcc 告诉 clangd
--      没有这一步，单文件项目（没有 compile_commands.json）的 #include <stdio.h> 会一直标红
--   3. 让 conform 用 clang-format 格式化 C/C++

local gcc = "C:/Users/hanhu/AppData/Local/Microsoft/WinGet/Packages/"
  .. "BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe/mingw64/bin/gcc.exe"

--------------------------------------------------------------------------------
-- 1. clangd 启动参数
--------------------------------------------------------------------------------

local clangd_cmd = {
  "clangd",
  "--background-index",
  "--clang-tidy",
  "--header-insertion=iwyu",
  "--completion-style=detailed",
  "--function-arg-placeholders",
  "--fallback-style=llvm",
}

if vim.uv.fs_stat(gcc) then
  -- 第二个 **/gcc.exe 是宽松匹配，防止 CMake 生成的路径分隔符风格和这里不一致
  table.insert(clangd_cmd, "--query-driver=" .. gcc .. ",**/gcc.exe")
else
  vim.notify("[c.lua] 找不到 gcc：" .. gcc .. "\nclangd 可能报找不到系统头文件", vim.log.levels.WARN)
end

--------------------------------------------------------------------------------
-- 2. 同步 clangd 的用户级配置
--------------------------------------------------------------------------------
-- 原理：没有 compile_commands.json 时，clangd 会自己合成一条编译命令，默认驱动是 `clang`。
-- 你机器上没有 clang，于是它谁也不问，直接用内置的 MSVC 路径去找头文件 → stdio.h 找不到。
-- 在用户配置里写上 Compiler: gcc.exe 之后，合成命令的驱动变成 gcc，
-- 再配合 --query-driver 白名单，clangd 就能执行 gcc 并拿到 MinGW 的真实 include 路径。
--
-- Windows 上 clangd 只认 %LOCALAPPDATA%\clangd\config.yaml（实测不读 XDG_CONFIG_HOME），
-- 而这个路径里的 WinGet 包名带哈希，升级 gcc 后会变，所以每次启动对一下内容。
local function sync_clangd_user_config()
  local localappdata = vim.env.LOCALAPPDATA
  if not localappdata or vim.fn.has("win32") == 0 then
    return
  end

  local dir = vim.fs.joinpath(localappdata, "clangd")
  local file = vim.fs.joinpath(dir, "config.yaml")
  local body = table.concat({
    "# Managed by Neovim plugin spec: lua/plugins/c.lua",
    "# 告诉 clangd 用哪个 gcc，没有 compile_commands.json 的文件也能找到 <stdio.h>",
    "CompileFlags:",
    "  Compiler: " .. gcc,
    "",
  }, "\n")

  local fh = io.open(file, "r")
  if fh then
    local old = fh:read("*a") or ""
    fh:close()
    if old == body then
      return -- 已经是最新，什么都不用做
    end
    if not old:find("Managed by Neovim", 1, true) then
      return -- 用户自己维护的配置，不覆盖
    end
  end

  vim.fn.mkdir(dir, "p")
  local out = io.open(file, "w")
  if out then
    out:write(body)
    out:close()
  end
end

-- 写文件失败（权限之类）不能影响启动
pcall(sync_clangd_user_config)

--------------------------------------------------------------------------------
-- 3. 插件配置
--------------------------------------------------------------------------------

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          cmd = clangd_cmd,
        },
      },
    },
  },

  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        c = { "clang_format" },
        cpp = { "clang_format" },
      },
    },
  },
}
