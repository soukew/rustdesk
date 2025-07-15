#!/bin/bash
set -e

# 配置环境变量
export FLATPAK_SYSTEM_HELPER_ON_SESSION=1
export OSTREE_REPO_PULL_DISABLE_CACHE=1

# 创建必要的目录
mkdir -p ~/.local/share/flatpak/repo
mkdir -p ~/.var/app/org.flatpak.Builder/cache/

echo "开始配置 Flatpak 环境..."

# 函数：添加 flathub 远程仓库
add_flathub_remote() {
    local attempt=1
    local max_attempts=5
    
    while [ $attempt -le $max_attempts ]; do
        echo "尝试添加 flathub 远程仓库 (第 $attempt 次尝试)..."
        
        # 首先尝试标准方法
        if flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null; then
            echo "✓ 成功添加 flathub 远程仓库"
            return 0
        fi
        
        # 如果失败，尝试不验证 GPG
        echo "标准方法失败，尝试不验证 GPG..."
        if flatpak --user remote-add --if-not-exists --no-gpg-verify flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null; then
            echo "✓ 成功添加 flathub 远程仓库 (无 GPG 验证)"
            return 0
        fi
        
        # 如果还是失败，尝试清理并重试
        echo "清理可能损坏的远程仓库..."
        flatpak --user remote-delete flathub 2>/dev/null || true
        
        echo "等待 10 秒后重试..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "❌ 添加 flathub 远程仓库失败"
    return 1
}

# 函数：验证远程仓库
verify_remote() {
    echo "验证远程仓库..."
    if flatpak --user remote-list | grep -q flathub; then
        echo "✓ flathub 远程仓库已正确配置"
        return 0
    else
        echo "❌ flathub 远程仓库未找到"
        return 1
    fi
}

# 函数：构建 flatpak 包
build_flatpak() {
    echo "开始构建 flatpak 包..."
    
    # 克隆共享模块
    if [ ! -d "shared-modules" ]; then
        echo "克隆共享模块..."
        git clone https://github.com/flathub/shared-modules.git --depth=1
    fi
    
    # 构建包，设置超时时间为 30 分钟
    echo "执行 flatpak-builder..."
    timeout 1800 flatpak-builder \
        --user \
        --install-deps-from=flathub \
        --force-clean \
        --repo=repo \
        --verbose \
        ./build \
        ./rustdesk.json || {
        echo "❌ flatpak-builder 失败或超时"
        echo "检查构建目录:"
        ls -la ./build/ 2>/dev/null || echo "构建目录不存在"
        return 1
    }
    
    echo "✓ flatpak-builder 完成"
}

# 函数：创建 bundle
create_bundle() {
    local version=${1:-"unknown"}
    local arch=${2:-"x86_64"}
    local suffix=${3:-""}
    
    echo "创建 flatpak bundle..."
    flatpak build-bundle \
        ./repo \
        "rustdesk-${version}-${arch}${suffix}.flatpak" \
        com.rustdesk.RustDesk || {
        echo "❌ 创建 bundle 失败"
        return 1
    }
    
    echo "✓ 成功创建 rustdesk-${version}-${arch}${suffix}.flatpak"
}

# 主执行流程
main() {
    local version=${VERSION:-"unknown"}
    local arch=${1:-"x86_64"}
    local suffix=${2:-""}
    
    echo "开始构建 RustDesk Flatpak 包"
    echo "版本: $version"
    echo "架构: $arch"
    echo "后缀: $suffix"
    
    # 步骤1: 添加远程仓库
    if ! add_flathub_remote; then
        echo "❌ 无法添加 flathub 远程仓库，构建失败"
        exit 1
    fi
    
    # 步骤2: 验证远程仓库
    if ! verify_remote; then
        echo "❌ 远程仓库验证失败，构建失败"
        exit 1
    fi
    
    # 步骤3: 构建 flatpak 包
    if ! build_flatpak; then
        echo "❌ 构建失败"
        exit 1
    fi
    
    # 步骤4: 创建 bundle
    if ! create_bundle "$version" "$arch" "$suffix"; then
        echo "❌ 创建 bundle 失败"
        exit 1
    fi
    
    echo "✅ 所有步骤完成！"
}

# 如果直接运行脚本，执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 