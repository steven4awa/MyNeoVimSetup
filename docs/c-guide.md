# Neovim 写 C：从开文件到跑起来

> 这份文档针对本机：Windows + Neovim 0.12.4 + LazyVim，编译器是 WinLibs 的 MinGW-w64 gcc 16.2。
> 所有命令都可以直接复制。

---

## 0. 一次性准备（只做一次）

### 0.1 首次启动，等插件装完

直接开 `nvim`。第一次启动时 lazy.nvim 会 clone 新插件（`clangd_extensions.nvim`），
Mason 会自动开始装 `clangd`。左下角有进度，等它跑完再操作。

同时 `lua/plugins/c.lua` 会顺手写好 clangd 的全局配置 `%LOCALAPPDATA%\clangd\config.yaml`，
不用你管（原理见 §4.4）。

如果没自动装，手动来：

```
:MasonInstall clangd
:MasonInstall clang-format
```

`:Mason` 打开面板可以看到装了什么、装到哪（`nvim-data\mason\bin`，这个目录已自动进 PATH）。

### 0.2 补 treesitter 的 cpp 解析器

`.c` 用的 `c` 解析器已经有了，`cpp` 缺一个：

```
:TSInstall cpp
```

### 0.3 验证

```
:checkhealth vim.lsp
```

打开一个 `.c` 文件后再跑一次，`vim.lsp: Active Clients` 一节里应该出现 `clangd`，root_dir 是你的项目目录。

> ⚠️ Neovim 0.12 已经删掉了 `:LspInfo`、`:LspRestart`、`:LspLog` 这三个命令，
> 网上老教程里的它们会直接报 `E492`。看 LSP 状态一律用 `:checkhealth vim.lsp`。
> 想重启某个客户端就重开 nvim，或者：
> ```vim
> :lua vim.lsp.stop_client(vim.lsp.get_clients({ name = "clangd" }))
> ```
> 然后 `:e` 重开当前文件。

---

## 1. 五分钟走通 hello world

### 1.1 建文件

```powershell
mkdir C:\code\cdemo
cd C:\code\cdemo
nvim hello.c
```

按 `i` 进入插入模式，粘贴：

```c
#include <stdio.h>

int main(void)
{
    for (int i = 1; i <= 3; i++) {
        printf("hello, i = %d\n", i);
    }
    return 0;
}
```

按 `Esc`，`:w`。

### 1.2 按 `<F5>`：编译 + 运行

- 下半屏弹出一个终端，直接输出三行 `hello, i = 1/2/3`
- 同时同目录多了一个 `hello.exe`
- 这个终端是真终端，所以 `scanf` 这类要键盘输入的程序也能正常用
- 退出终端窗口：在那个窗口里按 `Ctrl-\ Ctrl-n`，或者 `:q`

### 1.3 只有编译错误会怎样

故意把 `printf` 写成 `printff` 再按 `<F5>`：

- 不会弹终端
- 顶部提示"编译失败，错误在 quickfix"
- 按 `<leader>xQ`（或 `:copen`）打开错误列表，回车直接跳到出错行

关掉列表：`:cclose`。

### 1.4 只想编译不想跑

按 `<F6>`。适合编译通过了但你想先在终端里手动跑、或者要带参数跑的情况。

---

## 2. 快捷键表

| 键 | 作用 |
|---|---|
| `<F5>` | 保存 → `gcc` 编译 → 下方终端运行 |
| `<F6>` | 保存 → 只编译，成功只弹一句提示 |
| `<leader>xQ` | 打开/关闭 quickfix 列表（编译错误在这里） |
| `<leader>xx` | 打开/关闭诊断列表（clangd 报的警告/错误） |
| `<leader>cf` | 用 clang-format 格式化当前文件 |
| `gd` | 跳转到定义 |
| `K` | 悬浮显示文档 / 类型 |
| `<leader>ca` | 代码操作（补 include、clang-tidy 修复等） |
| `<leader>cr` | 重命名符号 |
| `<leader>ch` | 在 `.c` 和 `.h` 之间切换 |
| `<leader>cd` | 当前行的诊断详情 |

`<leader>` 是空格。

---

## 3. 不用快捷键，手动编译运行

`:!` 会把命令交给系统 shell（这里是 cmd.exe）执行。几个实用写法：

```vim
" 编译当前文件，输出同名 exe
:!gcc -g -Wall -Wextra -std=c17 % -o %:r.exe

" 运行生成的 exe
:!%:r.exe
```

其中：

| 占位符 | 展开成 |
|---|---|
| `%` | 当前文件名（`hello.c`） |
| `%:p` | 绝对路径 |
| `%:r` | 去掉扩展名（`hello`） |
| `%:h` | 所在目录 |

一次编译多个源文件：

```vim
:!gcc -g -Wall -std=c17 main.c util.c -o app.exe
:!app.exe
```

带库（比如数学库、Win32 API）：

```vim
:!gcc main.c -o app.exe -lm
:!gcc win.c -o win.exe -luser32
```

> **注意**：程序如果有 `scanf`、需要交互输入，别用 `:!`，用 `<F5>` 的终端。`:!` 抢不到键盘输入，会让你以为程序卡死了。

---

## 4. 多文件项目：用 CMake 生成 compile_commands.json

文件一多，手敲 gcc 就不现实了，而且 clangd 需要知道每个文件的 `-I` / `-D`，
否则补全和跳转会退化。标准做法是 CMake 导出 `compile_commands.json`。

### 4.1 项目结构

```
C:\code\myproj\
├── CMakeLists.txt
├── include\
│   └── util.h
└── src\
    ├── main.c
    └── util.c
```

### 4.2 CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.20)
project(myproj C)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)   # 关键：给 clangd 用

add_executable(myproj src/main.c src/util.c)
target_include_directories(myproj PRIVATE include)
target_compile_options(myproj PRIVATE -Wall -Wextra -g)
```

### 4.3 配置 + 构建

在项目根目录：

```powershell
cmake -S . -B build -G "MinGW Makefiles"
cmake --build build
```

- `build\myproj.exe` 就是产物
- `build\compile_commands.json` 生成后，**重开 nvim**，clangd 会自动在 `build\` 下找到它
- 之后 `#include "util.h"`、`gd` 跳转、补全就都正常了

日常改完代码只要：

```powershell
cmake --build build
```

想直接在 nvim 里构建，`:!cmake --build build` 即可。

### 4.4 没有 CMake 的小项目

**不用做任何事**。clangd 的编译器已经写在全局配置里了：

```
C:\Users\hanhu\AppData\Local\clangd\config.yaml
```

内容就四行（由 `lua/plugins/c.lua` 在每次启动时自动维护，见 §8）：

```yaml
CompileFlags:
  Compiler: C:/Users/hanhu/.../mingw64/bin/gcc.exe
```

有了它，随便哪个目录下的 `hello.c` 都能正常解析 `#include <stdio.h>`。

需要额外的 `-I` / `-D` 时，在项目根放一个 `compile_flags.txt`，一行一个：

```
-std=c17
-Wall
-Iinclude
```

填完重开 nvim 生效。

> 想给某个项目换编译器（比如别的项目用 MSVC），在项目根放一个 `.clangd` 覆盖即可，
> 项目级配置优先于全局：
> ```yaml
> CompileFlags:
>   Compiler: C:/path/to/cl.exe
> ```

#### 为什么光有 `--query-driver` 不够

这是这次踩的坑，值得记一下：

1. 项目里没有 `compile_commands.json` 时，clangd **自己合成**一条编译命令，默认驱动写死是 `clang`；
2. 你机器上没有 `clang.exe`，clangd 于是谁也不问，退回内置的 MSVC include 路径（`VS 8/9/10` 那些根本不存在的目录）；
3. 所以哪怕 `--query-driver` 里写着 gcc，clangd 也根本不会去执行它 —— 白名单里没有 `clang` 这个驱动。

在用户配置里写 `Compiler: gcc.exe` 之后，第 1 步合成的驱动就变成 gcc，第 3 步才轮得到 `--query-driver` 放行。

---

## 5. 编辑器能力怎么用

- **补全**：输入 `pri` 会自动出 `printf`，`Ctrl-n` / `Ctrl-p` 选择，回车确认
- **跳转**：`gd` 跳到定义，`Ctrl-o` 跳回来；`gd` 跳到别的文件后 `<leader>ch` 可在 `.c/.h` 间来回
- **诊断**：存盘后行尾出现 `E`/`W` 标记，`<leader>cd` 看这一行的完整解释
- **补 include**：光标在 `printf` 上按 `<leader>ca`，有 "Add #include <stdio.h>" 之类的操作
- **clang-tidy 修复**：同样走 `<leader>ca`
- **格式化**：`<leader>cf`，格式规则放在项目根的 `.clang-format`（没有就按 LLVM 风格）
- **clangd_extensions 的命令**：装好后它会注册一批 `:Clangd*` 命令，具体名单随版本变，自己看：

```vim
:command Clangd
```

比如 `:ClangdAST` 看一眼当前函数的语法树，对理解 `for` 循环/表达式挺直观。

想要"保存即格式化"，在 `lua/plugins/c.lua` 里的 conform 表加一行
`format_on_save = { timeout_ms = 500 }`（默认没有开，怕影响你现有习惯）。

---

## 6. 断点调试（可选，现在还没开）

现在只装了编译器，没装 debugger 前端。要用图形化断点：

1. `:LazyExtras`，勾上 `dap.core`，重启
2. `:MasonInstall codelldb`
3. 在代码行按 `<leader>db` 打断点，再按 `<leader>dc`（或 `<F5>`）启动

⚠️ **冲突提醒**：`dap.core` 会把 `<F5>` 占成"继续/启动调试"。
如果你开了 dap，就把 `lua/config/keymaps.lua` 里的 `"<F5>"` 改成 `"<F7>"`，
免得"编译运行"和"启动调试"抢同一个键。

不想折腾调试器的话，命令行用 gdb 也行（PATH 里已有）：

```powershell
gdb .\hello.exe
```

---

## 7. 常见报错对照表

| 现象 | 原因 | 解决 |
|---|---|---|
| `#include <stdio.h>` 一直标红，但 `<F5>` 能编译 | clangd 没拿到 MinGW 的系统头文件路径 | 看 `C:\Users\hanhu\AppData\Local\clangd\config.yaml` 是否存在、里面的 `Compiler:` 是否指向真实存在的 `gcc.exe`；重开 nvim 会自动补写。仍不行就用下面的 `clangd --check` 诊断 |
| `:checkhealth vim.lsp` 里压根没有 clangd | 没装 / 没启用 | `:MasonInstall clangd`，并确认 `lazyvim.json` 里有 `lang.clangd` |
| 提示 `'gcc' 不是内部或外部命令` | PATH 里没有 mingw64\bin | 重开终端；`where gcc` 确认 |
| 中文输出是乱码 | 控制台代码页不是 UTF-8 | 在终端先 `chcp 65001`；源码存成 UTF-8 |
| `undefined reference to 'sqrt'` | 没链接库 | 命令末尾加 `-lm` |
| `undefined reference to 'WinMain'` | 是控制台程序但入口被当成 GUI | 检查是否有 `-mwindows` |
| clangd 一直显示 "indexing" | 首次建索引 | 等一会；索引缓存在 `%LOCALAPPDATA%\clangd\index`，删掉可重建 |
| LSP 日志里抱怨找不到 clang-tidy | Mason 的 clangd 包没带 clang-tidy | 日志在 `C:\Users\hanhu\AppData\Local\nvim-data\lsp.log`，打开确认；真是这个原因就从 `lua/plugins/c.lua` 的 `cmd` 里删掉 `"--clang-tidy"` 那一行 |
| 改了配置没生效 | 插件/extra 改动要重启 | 完全退出 nvim 再进（`:qa` 不够彻底时用 `:qa!`） |

### 7.1 自己诊断 LSP 头文件问题

在放 `.c` 的目录里跑（clangd 路径是本机 Mason 装的，版本号会变）：

```powershell
& "$env:LOCALAPPDATA\nvim-data\mason\packages\clangd\clangd_23.1.0\bin\clangd.exe" `
  --check=hello.c `
  --query-driver="C:/Users/hanhu/AppData/Local/Microsoft/WinGet/Packages/BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe/mingw64/bin/gcc.exe" `
  --log=verbose 2>&1 |
  Select-String "User config file|Generic fallback command|file not found|All checks"
```

看这几行就够：

| 输出 | 含义 |
|---|---|
| `User config file is C:\Users\hanhu\AppData\Local\clangd\config.yaml` | clangd 只认这个位置的全局配置（实测不读 `XDG_CONFIG_HOME`） |
| `Generic fallback command is: ... \gcc.exe ... -isystem ...\mingw64\include ...` | 驱动是 gcc、拿到了 MinGW include → 正常 |
| `Generic fallback command is: ... \clang ...` | 驱动还是 `clang`，说明全局配置没被读到 |
| `All checks completed, 0 errors` | 头文件全部解析成功 |
| `System include extraction: driver clang not found in PATH` | 经典的"白名单里有 gcc、但驱动是 clang"，就是这次踩的坑 |

---

## 8. 这次改了什么 / 怎么改回去

| 文件 | 改动 |
|---|---|
| `lazyvim.json` | `extras` 里加了 `lazyvim.plugins.extras.lang.clangd` |
| `lua/plugins/c.lua` | **新建**：clangd 加 `--query-driver`；启动时自动维护 `%LOCALAPPDATA%\clangd\config.yaml`；conform 加 clang-format |
| `lua/config/keymaps.lua` | 追加 `<F5>` 编译并运行、`<F6>` 只编译 |
| `%LOCALAPPDATA%\clangd\config.yaml` | **新建**（在 nvim 配置目录之外）：告诉 clangd 用哪个 gcc。内容由 `c.lua` 自动维护，带 `Managed by Neovim` 标记才会被覆写 |

想撤销（这个目录是 git 仓库，但 `lazyvim.json` 和 `c.lua` 是未跟踪文件，`git checkout` 救不回来，只能删）：

```powershell
cd C:\Users\hanhu\AppData\Local\nvim

# 1. 删掉新建的插件文件
Remove-Item lua\plugins\c.lua

# 2. keymaps.lua 是跟踪文件，直接还原
git checkout -- lua\config\keymaps.lua

# 3. lazyvim.json 是未跟踪文件，手动编辑：把 extras 数组清空
#    "extras": [
#      "lazyvim.plugins.extras.lang.clangd"
#    ],
# 改成
#    "extras": [],
```

只想去掉编译快捷键、保留 LSP，就只做第 2 步。

### 改编译参数

编译命令在 `lua/config/keymaps.lua` 的 `c_compile()` 里：

```lua
local out = vim.fn.system({ "gcc", "-g", "-Wall", "-Wextra", "-std=c17", src, "-o", exe })
```

- 想用 C23：`-std=c23`
- 想加 include 目录：插 `"-I" .. vim.fn.getcwd() .. "/include"`
- 想换 clang：把 `"gcc"` 换成 `"clang"`（需先装 LLVM）
