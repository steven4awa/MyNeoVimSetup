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

--- 组一条能直接交给 vim.system 的命令；返回 解释器路径, 命令表
---@param file string 要执行的 .py 文件
---@return string, string[]
local function python_cmd(file)
  local exe = python_exe()
  if exe == "python" then
    -- 只有彻底找不到解释器才会走到这里：交给 shell 去展开别名
    if vim.fn.has("win32") == 1 then
      return exe, { vim.o.shell, "/c", "python", file }
    end
    return exe, { "sh", "-c", ("python %s"):format(vim.fn.shellescape(file)) }
  end
  return exe, { exe, file }
end

--- 把一条命令跑起来，stdout + stderr 写进底部只读 buffer。
--- 没有终端模式：j/k、搜索、ggVG"+y 都是普通 buffer 的行为。
---@param name string buffer 名（同名会先删掉，避免 E95）
---@param display string 显示在首行的命令
---@param cmd string[]
---@param cleanup? fun() 进程结束后执行（用来删临时文件）
local function run_in_buffer(name, display, cmd, cleanup)
  local old = vim.fn.bufnr(name)
  if old > 0 then
    vim.api.nvim_buf_delete(old, { force = true })
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$ " .. display, "（运行中…）" })

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_height(0, 15)

  -- 只在这块输出 buffer 里生效
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, desc = "关闭输出窗口" })
  vim.keymap.set("n", "<C-y>", function()
    vim.fn.setreg("+", table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
    vim.notify("[python] 已复制全部输出到剪贴板")
  end, { buffer = buf, desc = "复制全部输出" })

  vim.system(cmd, { cwd = vim.fn.getcwd(), text = true }, function(res)
    vim.schedule(function()
      if cleanup then
        pcall(cleanup)
      end
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local lines = vim.split((res.stdout or "") .. (res.stderr or ""), "\n", { plain = true })
      while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
      end
      table.insert(lines, 1, "$ " .. display)
      table.insert(lines, "")
      table.insert(lines, ("[exit %d]"):format(res.code or -1))
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
    end)
  end)
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

  -- 跑代码：输出进只读 buffer
  --   <leader>rr      普通模式 = 整个文件（先存盘）
  --   <leader>rr      可视模式 = 只跑选中的那几行（写到临时文件再跑）
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
          local exe, cmd = python_cmd(file)
          run_in_buffer(
            ("python-run://%s"):format(vim.fn.fnamemodify(file, ":t")),
            ("%s %s"):format(exe, file),
            cmd
          )
        end,
        desc = "Run Python File",
        ft = "python",
      },

      {
        "<leader>rr",
        function()
          -- 先离开可视模式，'< 和 '> 才会被置上
          vim.cmd("normal! \27")
          local s = vim.fn.line("'<")
          local e = vim.fn.line("'>")
          if s <= 0 or e <= 0 then
            return vim.notify("[python] 没有选中任何行", vim.log.levels.WARN)
          end
          if s > e then
            s, e = e, s
          end
          local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
          if #lines == 0 then
            return vim.notify("[python] 选中的范围是空的", vim.log.levels.WARN)
          end

          local tmp = vim.fn.tempname() .. ".py"
          vim.fn.writefile(lines, tmp)
          local exe, cmd = python_cmd(tmp)
          run_in_buffer(
            "python-run://selection.py",
            ("%s <选中 %s 第 %d-%d 行>"):format(exe, vim.fn.expand("%:t"), s, e),
            cmd,
            function()
              vim.fn.delete(tmp)
            end
          )
        end,
        desc = "Run Python Selection",
        ft = "python",
        mode = "x",
      },
    },
  },
}
