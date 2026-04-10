#!/bin/bash
# 启用 Bash 严格模式：
# -e 表示命令失败时立即退出，-u 表示使用未定义变量时报错，-o pipefail 表示管道中任一命令失败都算失败。
# 这样可以尽早暴露安装过程中的错误，避免脚本在异常状态下继续执行。
set -euo pipefail

# 进入脚本所在目录。
# 这样无论你从哪里执行 `./setup.sh`，后面读取 inventory.ini 和 playbook.yml 都不会找错位置。
cd "$(dirname "$0")"

# 这是默认的 HTTP 代理地址。
# 如果你所在网络环境不需要代理，后面可以直接选择“不使用代理”。
DEFAULT_HTTP_PROXY="http://192.168.17.1:10809"
WSL_HTTP_PROXY="http://172.29.48.1:10809"

# 这是默认的 APT 镜像源。
# 如果你选择修改系统源，直接回车就会使用这个地址。
DEFAULT_APT_MIRROR="http://rdsource.tp-link.com.cn/ubuntu/"
ALIYUN_APT_MIRROR="https://mirrors.aliyun.com/ubuntu/"

# 用高亮色强调交互提示中的默认选项，避免用户只靠大小写判断。
COLOR_HIGHLIGHT=$'\033[1;33m'
COLOR_PROMPT=$'\033[1;36m'
COLOR_RESET=$'\033[0m'

print_section() {
    printf '\n%s%s%s\n\n' "$COLOR_HIGHLIGHT" "========================================" "$COLOR_RESET"
}

print_prompt() {
    printf '%b' "${COLOR_PROMPT}$1${COLOR_RESET}"
}

# 这个函数的作用是：
# 当你启用了代理时，让 sudo 执行的命令也能拿到代理环境变量；
# 当你没启用代理时，就像平时一样直接执行 sudo。
run_sudo() {
    if [ -n "${http_proxy:-}" ]; then
        sudo env \
            http_proxy="$http_proxy" \
            https_proxy="$https_proxy" \
            HTTP_PROXY="$HTTP_PROXY" \
            HTTPS_PROXY="$HTTPS_PROXY" \
            "$@"
    else
        sudo "$@"
    fi
}

# 统一把用户输入的镜像源整理成以 / 结尾。
# 这样后面替换 sources 时，URL 形式会保持一致。
normalize_url() {
    printf '%s/\n' "${1%/}"
}

# 按当前系统实际使用的 APT 配置格式修改镜像源。
# Ubuntu 既可能使用传统的 /etc/apt/sources.list，
# 也可能使用 deb822 格式的 /etc/apt/sources.list.d/ubuntu.sources。
# 这里会在首次修改前各自备份一份原文件，避免后续不好回退。
configure_apt_mirror_sources() {
    local mirror_url="$1"

    if [ -f "/etc/apt/sources.list" ]; then
        if [ ! -f "/etc/apt/sources.list.bak.ansible-dotfiles" ]; then
            run_sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak.ansible-dotfiles
        fi
        run_sudo sed -Ei "s#https?://[^ ]+/ubuntu/?#${mirror_url}#g" /etc/apt/sources.list
    fi

    if [ -f "/etc/apt/sources.list.d/ubuntu.sources" ]; then
        if [ ! -f "/etc/apt/sources.list.d/ubuntu.sources.bak.ansible-dotfiles" ]; then
            run_sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak.ansible-dotfiles
        fi
        run_sudo sed -Ei "s#^URIs: .*#URIs: ${mirror_url}#g" /etc/apt/sources.list.d/ubuntu.sources
    fi
}

configure_proxy=""
proxy_value="$DEFAULT_HTTP_PROXY"
configure_apt_mirror=""
apt_mirror_value="$DEFAULT_APT_MIRROR"

# 先问你是否要使用 HTTP 代理。
# 输入 y 或直接回车表示使用代理；输入其他内容表示不使用。
print_section
read -r -p "$(print_prompt "是否配置 HTTP 代理？[${COLOR_HIGHLIGHT}Y${COLOR_PROMPT}/n]: ")" configure_proxy || true
case "$configure_proxy" in
    ""|[yY]|[yY][eE][sS])
        # 如果你选择使用代理，这里会让你在常用场景中直接选择，
        # 同时保留手动输入自定义地址的能力。
        echo
        echo "请选择 HTTP 代理配置："
        echo "  1) NAT 网络虚拟机代理 [${DEFAULT_HTTP_PROXY}]"
        echo "  2) WSL 代理 [${WSL_HTTP_PROXY}]"
        echo "  3) 自定义代理地址"
        echo
        read -r -p "$(print_prompt "> 请输入选项 [default is ${COLOR_HIGHLIGHT}1${COLOR_PROMPT}]: ")" proxy_option || true
        case "$proxy_option" in
            ""|1)
                proxy_value="$DEFAULT_HTTP_PROXY"
                ;;
            2)
                proxy_value="$WSL_HTTP_PROXY"
                ;;
            3)
                echo
                read -r -p "$(print_prompt "请输入自定义 HTTP 代理地址: ")" user_proxy || true
                if [ -n "${user_proxy:-}" ]; then
                    proxy_value="$user_proxy"
                else
                    echo "未输入代理地址，继续使用默认值: $DEFAULT_HTTP_PROXY"
                    proxy_value="$DEFAULT_HTTP_PROXY"
                fi
                ;;
            *)
                echo "未识别的选项，继续使用默认值: $DEFAULT_HTTP_PROXY"
                proxy_value="$DEFAULT_HTTP_PROXY"
                ;;
        esac

        # 导出代理环境变量。
        # 这样 apt、ansible-playbook 以及后面 Ansible 中需要联网的任务都可以走代理。
        export http_proxy="$proxy_value"
        export https_proxy="$proxy_value"
        export HTTP_PROXY="$proxy_value"
        export HTTPS_PROXY="$proxy_value"
        echo "🌐 已启用 HTTP 代理: $proxy_value"
        ;;
    *)
        # 明确清理可能存在的代理变量，避免继承到旧环境里的配置。
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY || true
        echo "🌐 跳过 HTTP 代理配置。"
        ;;
esac

# 询问是否切换 APT 镜像源。
# 输入 y 或直接回车表示切换；输入其他内容表示保持系统当前配置。
print_section
read -r -p "$(print_prompt "是否修改 APT 镜像源？[${COLOR_HIGHLIGHT}Y${COLOR_PROMPT}/n]: ")" configure_apt_mirror || true
case "$configure_apt_mirror" in
    ""|[yY]|[yY][eE][sS])
        # 如果你选择切换镜像源，这里会让你在常用镜像中直接选择，
        # 同时保留手动输入自定义地址的能力。
        echo
        echo "请选择 APT 镜像源："
        echo "  1) 内网镜像 [${DEFAULT_APT_MIRROR}]"
        echo "  2) 阿里云镜像 [${ALIYUN_APT_MIRROR}]"
        echo "  3) 自定义镜像地址"
        echo
        read -r -p "$(print_prompt "> 请输入选项 [default is ${COLOR_HIGHLIGHT}1${COLOR_PROMPT}]: ")" apt_mirror_option || true
        case "$apt_mirror_option" in
            ""|1)
                apt_mirror_value="$DEFAULT_APT_MIRROR"
                ;;
            2)
                apt_mirror_value="$ALIYUN_APT_MIRROR"
                ;;
            3)
                echo
                read -r -p "$(print_prompt "请输入自定义 APT 镜像源: ")" user_apt_mirror || true
                if [ -n "${user_apt_mirror:-}" ]; then
                    apt_mirror_value="$user_apt_mirror"
                else
                    echo "未输入镜像地址，继续使用默认值: $DEFAULT_APT_MIRROR"
                    apt_mirror_value="$DEFAULT_APT_MIRROR"
                fi
                ;;
            *)
                echo "未识别的选项，继续使用默认值: $DEFAULT_APT_MIRROR"
                apt_mirror_value="$DEFAULT_APT_MIRROR"
                ;;
        esac

        # 规范化 URL 后再写入 sources，避免有的地址带 / 有的不带 /。
        apt_mirror_value="$(normalize_url "$apt_mirror_value")"
        echo "📦 将使用 APT 镜像源: $apt_mirror_value"

        # 在安装 Ansible 前就先切源，这样后面的 apt update 和 apt install 也能直接走新源。
        configure_apt_mirror_sources "$apt_mirror_value"
        ;;
    *)
        echo "📦 保持当前 APT 镜像源配置。"
        ;;
esac

# 下面这一步是为了让当前用户后续执行 sudo 时不再反复输密码。
# 做法是：在 /etc/sudoers.d/ 里为当前用户创建一条免密 sudo 规则。
# 如果这条规则已经存在，就直接跳过。
if [ ! -f "/etc/sudoers.d/$(whoami)" ]; then
    echo "🔧 正在配置 sudo 免密权限..."

    # 写入一条 sudo 规则：允许当前用户免密码使用 sudo。
    # 这里用 `sudo tee` 是因为普通重定向没有权限写入 /etc/sudoers.d/。
    echo "$(whoami) ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/$(whoami)" > /dev/null

    # sudoers 规则文件的权限必须是 0440，否则 sudo 会拒绝读取。
    sudo chmod 0440 "/etc/sudoers.d/$(whoami)"
else
    echo "✅ sudo 免密已配置，跳过。"
fi

# 先安装 Ansible。
# 因为真正的软件安装、Shell 配置和 dotfiles 部署，都是在 playbook.yml 里完成的。
echo "📦 正在安装基础依赖 (Ansible)..."
run_sudo apt update
run_sudo apt install -y ansible

# 执行 Ansible 剧本。
# 这一步会安装 fish、zoxide、git 等工具，
# 把默认 shell 改成 fish，并安装配置 fzf。
echo "🚀 开始执行 Ansible 本地配置..."
ansible-playbook -i inventory.ini playbook.yml

# 到这里说明剧本执行成功。
# `exec fish` 会用 fish 替换当前 bash 进程，让你立刻进入新的 shell。
echo "✨ 配置完成，正在切换到 fish..."
exec fish
