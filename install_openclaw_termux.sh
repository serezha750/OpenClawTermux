#!/data/data/com.termux/files/usr/bin/bash
# install_openclaw_debian.sh
# 功能：配置 Termux + Debian 12 (bookworm, 最小化)、Node.js 22、OpenClaw 及 Node 劫持垫片。
# 最终运行：`openclaw onboard` 然后 `openclaw gateway --verbose`。
# 安全重复运行，已安装的组件会自动跳过。

set -Eeuo pipefail

# ---------- 辅助函数 ----------
section() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
die() { echo -e "\n[错误] $*" >&2; exit 1; }

# 在 Debian (proot-distro) 内部以 root 身份运行命令
deb() { proot-distro login debian -- bash -lc "$*"; }

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
pkg install -y termux-api || true

# ---------- Debian (proot, 最小化) ----------
section "检查 Debian proot-distro 是否已安装"
if proot-distro list | grep -q "^debian"; then
    echo "Debian 已安装，跳过安装步骤。"
else
    section "安装 Debian proot-distro（最小化基础系统）"
    proot-distro install debian || die "Debian 安装失败"
fi

# ---------- 强制配置 Debian 12 (bookworm) 清华源（覆盖任何已有配置，防止混源） ----------
section "强制配置 Debian 12 (bookworm) 清华源（清除可能存在的 testing/unstable 源）"
deb "cat > /etc/apt/sources.list << 'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware
EOF"

# ---------- 修复可能的依赖损坏，并确保所有包来自 bookworm ----------
section "修复 Debian 包依赖冲突（如有）"
deb "apt --fix-broken install -y || true"
deb "apt dist-upgrade -y --allow-downgrades"

section "更新 Debian 软件源并升级所有包"
deb "apt update"
deb "apt -y upgrade"

# ---------- 安装基础工具（拆分为两步，避免元包依赖冲突） ----------
section "安装基础网络工具（curl git ca-certificates）"
deb "apt install -y --no-install-recommends curl git ca-certificates"

section "安装构建工具（gcc, g++, make, libc6-dev）"
deb "apt install -y --no-install-recommends gcc g++ make libc6-dev"

# ---------- 通过 NodeSource 安装 Node.js 22 ----------
section "检查 Node.js 是否已安装且版本为 22.x"
if deb "command -v node >/dev/null 2>&1 && node -v 2>/dev/null | grep -q '^v22'"; then
    NODE_VERSION=$(deb "node -v 2>/dev/null" || echo "未知")
    echo "Node.js 已安装且版本为 $NODE_VERSION，跳过安装。"
else
    section "安装 Node.js 22.x（NodeSource）"
    deb "curl -fsSL https://deb.nodesource.com/setup_22.x | bash -"
    deb "apt install -y --no-install-recommends nodejs"
    deb "node -v && npm -v"
fi

# ---------- OpenClaw ----------
section "检查 OpenClaw 是否已全局安装"
if deb "command -v openclaw >/dev/null 2>&1"; then
    echo "OpenClaw 已安装，跳过全局安装。"
else
    section "安装 OpenClaw（最新版）"
    deb "npm install -g openclaw@latest"
fi

# ---------- 劫持垫片 ----------
section "检查 Node.js 劫持垫片是否已配置"
HIJACK_JS_EXISTS=false
if deb "[ -f /root/hijack.js ]"; then
    HIJACK_JS_EXISTS=true
fi
BASHRC_HAS_NODE_OPTIONS=false
if deb "grep -q 'NODE_OPTIONS=.*-r /root/hijack.js' ~/.bashrc 2>/dev/null"; then
    BASHRC_HAS_NODE_OPTIONS=true
fi

if [ "$HIJACK_JS_EXISTS" = true ] && [ "$BASHRC_HAS_NODE_OPTIONS" = true ]; then
    echo "劫持垫片已配置，跳过写入。"
else
    section "应用 Node.js 网络接口劫持"
    if [ "$HIJACK_JS_EXISTS" = false ]; then
        deb 'cat > /root/hijack.js << "EOF"
const os = require("os");
os.networkInterfaces = () => ({});
EOF'
    fi
    if [ "$BASHRC_HAS_NODE_OPTIONS" = false ]; then
        deb 'grep -q "NODE_OPTIONS=.*-r /root/hijack.js" ~/.bashrc || echo '\''export NODE_OPTIONS="-r /root/hijack.js"'\'' >> ~/.bashrc'
        deb 'source ~/.bashrc || true'
    fi
fi

# ---------- 最终步骤 ----------
section "运行 OpenClaw 初始化向导"
deb "openclaw onboard || true"

section "启动 OpenClaw 网关（详细输出）—— 将持续运行"
deb "openclaw gateway --verbose"
