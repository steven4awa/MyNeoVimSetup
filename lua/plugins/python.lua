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
  -- 用 vim.system 异步跑，输出写进一块只读的 nofile buffer：没有终端模式，
  -- j/k、搜索、ggVG"+y 都是普通 buffer 的行为。窗口关掉内容就没了
  -- （bufhidden=wipe），想留档就在输出窗口里 :w out.txt。
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

          -- 解释器：python_exe() 一般给绝对路径；只剩裸 "python" 时交给 shell 展开
          -- （Windows 的 WindowsApps 别名是 0 字节 ReparsePoint，libuv 直接 spawn 会 E475）
          local exe = python_exe()
          local cmd
          if exe == "python" then
            cmd = vim.fn.has("win32") == 1 and { vim.o.shell, "/c", "python", file }
              or { "sh", "-c", ("python %s"):format(vim.fn.shellescape(file)) }
          else
            cmd = { exe, file }
          end

          -- 同名 buffer 先清掉，避免 E95
          local name = ("python-run://%s"):format(vim.fn.fnamemodify(file, ":t"))
          local old = vim.fn.bufnr(name)
          if old > 0 then
            vim.api.nvim_buf_delete(old, { force = true })
          end

          local buf = vim.api.nvim_create_buf(false, true)
          vim.bo[buf].buftype = "nofile"
          vim.bo[buf].bufhidden = "wipe"
          vim.bo[buf].swapfile = false
          vim.api.nvim_buf_set_name(buf, name)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            ("$ %s %s"):format(exe, file),
            "（运行中…）",
          })

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
              if not vim.api.nvim_buf_is_valid(buf) then
                return
              end
              local lines = vim.split((res.stdout or "") .. (res.stderr or ""), "\n", { plain = true })
              while #lines > 0 and lines[#lines] == "" do
                table.remove(lines)
              end
              table.insert(lines, 1, ("$ %s %s"):format(exe, file))
              table.insert(lines, "")
              table.insert(lines, ("[exit %d]"):format(res.code or -1))
              vim.bo[buf].modifiable = true
              vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
              vim.bo[buf].modifiable = false
            end)
          end)
        end,
        desc = "Run Python File",
        ft = "python",
      },
    },
  },
}
