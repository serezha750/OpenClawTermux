#!/data/data/com.termux/files/usr/bin/bash
# install_openclaw_ubuntu.sh
# 功能：配置 Termux + Ubuntu (proot)、Node.js 22、OpenClaw 及 Node 劫持垫片。
# 最终运行：`openclaw onboard` 然后 `openclaw gateway --verbose`。
# 可安全重复运行；尽量做到幂等。
# 详情：https://www.mobile-hacker.com/2026/02/11/how-to-install-openclaw-on-an-android-phone-and-control-it-via-whatsapp/

set -Eeuo pipefail

# ---------- 辅助函数 ----------
section() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
die() { echo -e "\n[错误] $*" >&2; exit 1; }

# 在 Ubuntu (proot-distro) 内部以 root 身份运行命令
ub() { proot-distro login ubuntu -- bash -lc "$*"; }

export DEBIAN_FRONTEND=noninteractive
TERMUX_HOME="/data/data/com.termux/files/home"

# ---------- Termux 基础设置 ----------
section "请求存储访问权限（设备上可能会弹出提示）"
termux-setup-storage || true

section "更新 Termux 软件包"
yes | pkg update || true
yes | pkg upgrade || true

section "安装 Termux 软件包：proot-distro、termux-api（如果可用）"
pkg install -y proot-distro || die "安装 proot-distro 失败"
# 'termux-api' 可能在某些镜像源中不存在；忽略安装失败
pkg install -y termux-api || true

# ---------- Ubuntu (proot) ----------
section "安装/刷新 Ubuntu proot-distro"
proot-distro install ubuntu || true

section "更新 Ubuntu 基础系统（apt update/upgrade）"
ub "apt update && apt -y upgrade"

section "安装编译和网络工具（curl git build-essential ca-certificates）"
ub "apt install -y curl git build-essential ca-certificates"

# ---------- 通过 NodeSource 安装 Node.js 22 ----------
section "安装 Node.js 22.x（NodeSource）"
ub "curl -fsSL https://deb.nodesource.com/setup_22.x | bash -"
ub "apt install -y nodejs"
ub "node -v && npm -v"

# ---------- OpenClaw ----------
section "安装 OpenClaw（最新版）"
ub "npm install -g openclaw@latest"

# ---------- 劫持垫片 ----------
section "应用 Node.js 网络接口劫持"
# 覆盖 os.networkInterfaces() 使其返回空对象
ub 'cat > /root/hijack.js << "EOF"
const os = require("os");
os.networkInterfaces = () => ({});
EOF'

# 通过 NODE_OPTIONS 预加载垫片，写入 root 的 .bashrc（幂等）
ub 'grep -q "NODE_OPTIONS=.*-r /root/hijack.js" ~/.bashrc || echo '\''export NODE_OPTIONS="-r /root/hijack.js"'\'' >> ~/.bashrc'
ub 'source ~/.bashrc || true'

# ---------- 最终步骤 ----------
section "运行 OpenClaw 初始化向导"
ub "openclaw onboard || true"

section "启动 OpenClaw 网关（详细输出）—— 将持续运行"
# 按要求的最后一条命令：
ub "openclaw gateway --verbose"

# （网关进程将在前台运行，之后不显示额外消息）