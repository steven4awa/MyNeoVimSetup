-- 解释器解析：不要把裸 "python" 直接交给 jobstart
-- Windows 上 %LOCALAPPDATA%\Microsoft\WindowsApps\python.exe 是 0 字节 ReparsePoint（应用执行别名），
-- PowerShell / cmd 能展开它，但 libuv 不认 → E5108 / E475 "... is not executable"
local function python_exe()
  -- 1) venv-selector 激活的环境优先
  local venv = vim.env.VIRTUAL_ENV
  if venv and venv ~= "" then
    local exe = vim.fs.joinpath(venv, "Scripts", "python.exe")
    if vim.uv.fs_stat(exe) then
      return exe
    end
  end
  -- 2) PATH 上真实存在的 python.exe（跳过 0 字节别名）
  for _, name in ipairs({ "python.exe", "python3.exe" }) do
    local p = vim.fn.exepath(name)
    if p ~= "" and not p:lower():find("\\windowsapps\\", 1, true) then
      return p
    end
  end
  -- 3) 本机兜底；以后换 Python 版本改这一行
  local fallback = "C:/Users/hanhu/AppData/Local/Python/pythoncore-3.15-64/python.exe"
  if vim.uv.fs_stat(fallback) then
    return fallback
  end
  -- 4) 实在找不到就把名字交给 shell（下面用字符串命令，shell 认得别名）
  return "python"
end

return {
  -- 想让类型检查更严（默认 standard）
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = { settings = { python = { analysis = { typeCheckingMode = "strict" } } } },
      },
    },
  },

  -- 不想每次激活环境都弹提示
  {
    "linux-cultist/venv-selector.nvim",
    opts = { options = { notify_user_on_venv_activation = false } },
  },

  -- 多扫一个你自己放环境的目录（键名随便起，会合并进默认搜索）
  {
    "linux-cultist/venv-selector.nvim",
    opts = {
      search = {
        mine = { command = "$FD Scripts\\\\python.exe$ D:\\envs --full-path --color never -a" },
      },
    },
  },

  -- 跑当前文件：<leader>rr
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>rr",
        function()
          local file = vim.fn.expand("%:p")
          if file == "" then
            return vim.notify("[python] 当前 buffer 还没存成文件，先 :w 起个名字", vim.log.levels.WARN)
          end
          if vim.bo.modified then
            vim.cmd.write()
          end
          -- 关键：传「字符串」而不是 { "python", ... } 列表。
          -- 字符串会让 jobstart 通过 shell 执行，Windows 的应用别名也能展开；
          -- 传列表则是 libuv 直接 spawn，遇到 0 字节别名就 E475。
          local native = function(p)
            return vim.fn.has("win32") == 1 and (p:gsub("/", "\\")) or p
          end
          local cmd = vim.fn.shellescape(native(python_exe())) .. " " .. vim.fn.shellescape(native(file))
          -- snacks 默认 interactive = true，会连带 auto_close = true：
          -- 进程一退出窗口就关，所以你只看到“闪一下”，输出根本没机会看。
          -- 想改成底部横条而不是浮窗，再加 win = { position = "bottom", height = 15 }
          Snacks.terminal.open(cmd, {
            cwd = vim.fn.getcwd(),
            auto_close = false,
          })
        end,
        desc = "Run Python File",
        ft = "python",
      },
    },
  },
}
