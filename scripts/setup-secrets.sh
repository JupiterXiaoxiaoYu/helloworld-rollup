#!/bin/bash

# 检查并安装 GitHub CLI
install_gh() {
    echo "Installing GitHub CLI..."
    
    # 检测操作系统
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install gh
        else
            echo "Homebrew is required for installation on macOS. Please install it first:"
            echo "Visit: https://brew.sh/"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux 和 WSL
        # 检测是否在 WSL 环境中
        if grep -qi microsoft /proc/version; then
            echo "WSL detected"
        fi
        
        # 检测发行版
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case $ID in
                "ubuntu"|"debian"|"ubuntu-wsl"|"debian-wsl")
                    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                    sudo apt update
                    sudo apt install gh -y
                    ;;
                "fedora")
                    sudo dnf install gh -y
                    ;;
                "centos"|"rhel")
                    sudo dnf install 'dnf-command(config-manager)'
                    sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
                    sudo dnf install gh -y
                    ;;
                *)
                    echo "Unsupported Linux distribution. Please install GitHub CLI manually:"
                    echo "Visit: https://github.com/cli/cli#installation"
                    exit 1
                    ;;
            esac
        else
            echo "Could not determine Linux distribution. Please install GitHub CLI manually:"
            echo "Visit: https://github.com/cli/cli#installation"
            exit 1
        fi
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        # Windows
        if command -v winget &> /dev/null; then
            echo "Installing using winget..."
            winget install GitHub.cli
        elif command -v choco &> /dev/null; then
            echo "Installing using Chocolatey..."
            choco install gh
        elif command -v scoop &> /dev/null; then
            echo "Installing using Scoop..."
            scoop install gh
        else
            echo "No package manager found. Please install one of the following:"
            echo "1. Windows Package Manager (winget): https://www.microsoft.com/p/app-installer/"
            echo "2. Chocolatey: https://chocolatey.org/"
            echo "3. Scoop: https://scoop.sh/"
            echo "Or download GitHub CLI manually from: https://cli.github.com/"
            exit 1
        fi
    else
        echo "Unsupported operating system. Please install GitHub CLI manually:"
        echo "Visit: https://github.com/cli/cli#installation"
        exit 1
    fi
}

# 检查是否安装了 GitHub CLI
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) is not installed."
    read -p "Would you like to install it now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_gh
    else
        echo "GitHub CLI is required for this script. Please install it manually:"
        echo "Visit: https://cli.github.com/"
        exit 1
    fi
fi

# 检查是否登录
if ! gh auth status &> /dev/null; then
    echo "Please login to GitHub first."
    gh auth login
fi

# 添加重试函数
retry_command() {
    local n=1
    local max=5
    local delay=15
    while true; do
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                echo "Command failed. Attempt $n/$max:"
                sleep $delay;
            else
                echo "The command has failed after $n attempts."
                return 1
            fi
        }
    done
}

# 从 .env 文件读取并设置 secrets
while IFS='=' read -r key value || [ -n "$key" ]; do
    # 跳过空行和注释
    if [ -z "$key" ] || [[ $key == \#* ]]; then
        continue
    fi
    
    # 移除引号
    value=$(echo $value | tr -d '"' | tr -d "'")
    
    # 设置 secret，添加重试和错误处理
    echo "Setting secret: $key with value: $value"
    if ! retry_command gh secret set "$key" <<< "$value"; then
        echo "Failed to set secret: $key"
        exit 1
    fi
done < .env

# 验证设置是否成功
echo "Verifying secrets..."
if gh secret list &> /dev/null; then
    echo "All secrets have been set and verified successfully!"
else
    echo "Failed to verify secrets. Please check your GitHub permissions and connection."
    exit 1
fi 