# ansible-dotfiles

这是一个基于 Ansible 的本地开发环境初始化项目。

项目入口是 `setup.sh`：它先完成 Ansible 运行前的引导工作，再调用 `playbook.yml` 统一执行环境初始化。换句话说，`setup.sh` 负责把机器带到“可以跑 Ansible”的状态，`playbook.yml` 负责真正的环境配置和工具安装。

## 项目结构

- `setup.sh`
  - 用于引导安装 Ansible，并处理执行 playbook 前的准备工作。
- `playbook.yml`
  - 用于执行具体的系统初始化、工具安装和 shell 配置。
- `inventory.ini`
  - 本地 inventory，默认通过 `localhost ansible_connection=local` 执行。
- `files/`
  - 存放要部署到系统中的 fish 配置文件和工具配置文件。

## 使用方式

在目标 Ubuntu 环境中执行：

```bash
chmod +x setup.sh
./setup.sh
```

脚本会先询问代理和 APT 镜像源配置，然后安装 Ansible，最后执行：

```bash
ansible-playbook -i inventory.ini playbook.yml
```

执行完成后，脚本会自动切换进入 `fish`。

## setup.sh 做了什么

`setup.sh` 是 bootstrap 脚本，目标是让一台还没准备好的机器也能顺利进入 Ansible 初始化流程。当前它除了安装 Ansible，还做了下面这些工作：

1. 启用 Bash 严格模式。
   - 通过 `set -euo pipefail` 尽早暴露脚本执行过程中的错误。

2. 切换到脚本所在目录。
   - 避免从其他路径执行时找不到 `inventory.ini` 和 `playbook.yml`。

3. 处理代理配置。
   - 支持交互式选择 HTTP 代理。
   - 内置了 NAT 虚拟机代理和 WSL 代理两个常用选项。
   - 也支持手动输入自定义代理地址。
   - 配置后的代理变量会透传给 `sudo`、`apt` 和 `ansible-playbook`。

4. 处理 APT 镜像源配置。
   - 支持交互式选择是否修改 APT 镜像源。
   - 内置了阿里云镜像和内网镜像两个常用选项。
   - 也支持手动输入自定义镜像源。
   - 会兼容修改 `/etc/apt/sources.list` 和 `/etc/apt/sources.list.d/ubuntu.sources`。
   - 首次修改前会自动备份原始 sources 文件，方便回退。

5. 配置当前用户免密 sudo。
   - 如果 `/etc/sudoers.d/<当前用户名>` 不存在，就自动写入免密 sudo 规则。
   - 这样后续 Ansible 本地执行时不会频繁要求输入 sudo 密码。

6. 安装 Ansible。
   - 在系统级执行 `apt update` 和 `apt install -y ansible`。

7. 调用 Ansible 剧本。
   - 使用本地 inventory 执行 `playbook.yml`。

8. 初始化完成后切换到 fish。
   - 使用 `exec fish` 直接进入配置完成后的 shell。

## playbook.yml 做了什么

`playbook.yml` 负责真正的初始化工作。当前主要包含以下内容：

### 1. 安装 Fish

- 安装 `software-properties-common`
- 添加 `ppa:fish-shell/release-4`
- 更新 apt 缓存
- 安装 `fish`

### 2. 安装基础软件

通过 `apt` 安装常用基础工具：

- `git`
- `direnv`
- `curl`
- `jq`
- `yq`
- `zoxide`
- `bat`
- `eza`
- `fd-find`
- `python3-pexpect`

### 3. 安装 lsd

- 优先通过 `apt` 安装 `lsd`
- 如果安装失败，则进入 `rescue`
- 对旧版 Ubuntu 走 GitHub 官方 `.deb` 包回退安装
- 对不支持的系统版本或架构给出明确报错

### 4. 安装 fzf

- 从 GitHub Releases 下载 `fzf` 官方二进制压缩包
- 解压到 `/usr/local/bin`
- 赋予可执行权限

### 5. 安装 Lazygit

- 按系统架构下载 Lazygit 官方二进制包
- 安装到 `/usr/local/bin/lazygit`
- 创建 `~/.config/lazygit`
- 部署项目内置的 Lazygit 配置文件

### 6. 配置 Fish Shell 初始化环境

部署以下配置到 `/etc/fish/conf.d`：

- `zoxide.fish`
- `alias.fish`
- `fzf.fish`
- `direnv.fish`

这些配置主要用于：

- 初始化 `zoxide`
- 配置常用命令别名
- 初始化 `fzf` 及其样式
- 初始化 `direnv`

### 7. 安装 Neovim 和 NvChad

- 安装 Neovim 运行依赖
- 下载并安装官方 Neovim 二进制包到 `/opt/nvim`
- 创建 `/usr/local/bin/nvim` 软链接
- 克隆 `NvChad/starter` 到 `~/.config/nvim`
- 删除 starter 的 `.git` 元数据
- 首次执行 `nvim --headless "+Lazy! sync" +qa` 同步插件
- 提示后续可手动执行 `:MasonInstallAll` 和 `:TSInstallAll`

### 8. 将默认 shell 改为 Fish

- 将当前用户的 login shell 修改为 `/usr/bin/fish`

### 9. 创建常用命令软链接

为了兼容 Ubuntu 包名与常用命令名不一致的问题，创建了以下软链接：

- `python -> /usr/bin/python3`
- `bat -> /usr/bin/batcat`
- `fd -> /usr/bin/fdfind`

## 适用场景

这个项目更适合以下场景：

- 新装 Ubuntu 后快速拉起一套常用开发环境
- 内网或特殊网络环境下，需要额外处理代理和镜像源
- 希望通过 Ansible 固化个人 shell、编辑器和常用 CLI 工具配置

## 备注

- 当前 inventory 默认只针对本机执行。
- 项目默认面向 Ubuntu 环境，尤其是 Fish、APT 源和部分回退安装逻辑都按 Ubuntu 设计。
- 如果需要扩展到更多发行版，建议先把与 Ubuntu 强耦合的安装逻辑拆分出来。
