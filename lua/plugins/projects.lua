-- 自定义「项目」列表：<leader>fp（或 :lua Snacks.picker.projects()）
-- 列表 = projects（手写清单）+ recent（最近打开过的文件的 git 根目录）+ dev（用 fd 扫描的目录）
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          projects = {
            -- ① 手写清单：想一直出现在列表里的项目根目录
            projects = {
              "D:/code/obsidian-publish/quartz",
              "C:/Users/hanhu/AppData/Local/nvim",
              -- 想加就在下面照抄一行，路径用 / 或 \\ 都行
              -- "D:/code/你的项目",
            },

            -- ② 自动扫描：这些目录下（最多 2 层）凡是带下方 patterns 标记的文件夹都会自动出现
            --    没有 git 的项目靠这项收录
            -- dev = {
            --   "D:/code",
            -- },
            -- max_depth = 2,

            -- ③ 判断「这个文件夹是项目」的标记（默认值 + 我补的几个）
            patterns = {
              ".git",
              "_darcs",
              ".hg",
              ".bzr",
              ".svn",
              "package.json",
              "Makefile",
              "CMakeLists.txt",
              "Cargo.toml",
              "pyproject.toml",
              "go.mod",
            },

            -- ④ 是否把「最近打开过文件的 git 根目录」也算进来
            --    你现在看到的 quartz 和 AppData/Local/nvim 就是这项带出来的
            --    只想留手写清单的话，改成 false
            recent = true,
          },
        },
      },
    },
  },
}
