#!/bin/bash
# ===============================================
# 脚本名称：acme_cert_setup.sh
# 脚本功能：使用 acme.sh 自动化申请 SSL 证书
# 版本：3.1
# 支持：Cloudflare DNS 验证
# ===============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印彩色信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示脚本标题
show_banner() {
    echo -e "${BLUE}=========================================="
    echo "         acme.sh SSL 证书一键申请脚本"
    echo "==========================================${NC}"
    echo ""
}

# 检查 Nginx 是否安装
check_nginx() {
    print_info "正在检查 Nginx 是否已安装..."
    if ! command -v nginx &> /dev/null; then
        print_error "未找到 Nginx。本脚本依赖 Nginx，请先安装。"
        print_error "例如：apt-get update && apt-get install nginx"
        exit 1
    fi
    print_success "Nginx 已安装。"
}

# 获取用户输入
get_user_input() {
    while true; do
        echo -e "${YELLOW}请提供以下信息以开始证书申请：${NC}"
        read -p "请输入您的域名 (例如: example.com): " DOMAIN
        if [ -z "$DOMAIN" ]; then
            print_error "域名不能为空！"
            continue
        fi

        read -p "请输入您的 Cloudflare 注册邮箱: " EMAIL
        if [ -z "$EMAIL" ]; then
            print_error "Cloudflare 邮箱不能为空！"
            continue
        fi

        read -p "请输入您的 Cloudflare API Token: " CF_Token
        if [ -z "$CF_Token" ]; then
            print_error "Cloudflare API Token 不能为空！"
            continue
        fi

        read -p "请输入您的 Cloudflare Account ID: " CF_Account_ID
        if [ -z "$CF_Account_ID" ]; then
            print_error "Cloudflare Account ID 不能为空！"
            continue
        fi
        echo ""

        echo -e "${YELLOW}请确认以下信息是否正确：${NC}"
        print_info "域名: $DOMAIN"
        print_info "邮箱: $EMAIL"
        print_info "API Token: $CF_Token"
        print_info "Account ID: $CF_Account_ID"
        echo ""
        read -p "信息是否正确？ (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            break
        else
            echo -e "${YELLOW}请重新输入。${NC}"
            echo ""
        fi
    done
    echo ""
}

# 显示完成信息
show_completion_info() {
    print_success "证书文件位置："
    echo "  • 私钥文件: /etc/nginx/ssl/$DOMAIN.key"
    echo "  • 证书文件: /etc/nginx/ssl/$DOMAIN.pem"
    echo ""
}

# 脚本主执行逻辑
main() {
    show_banner
    check_nginx
    get_user_input

    # 安装 acme.sh
    if [ ! -d "$HOME/.acme.sh" ]; then
        print_info "未检测到 acme.sh，正在为你安装..."
        curl https://get.acme.sh | sh -s email="$EMAIL"
        if [ $? -ne 0 ]; then
            print_error "acme.sh 安装失败，请手动尝试。"
            exit 1
        fi
        print_success "acme.sh 安装完成！"
    else
        print_info "acme.sh 已安装，跳过安装步骤。"
    fi
    # 让当前 shell 进程识别 acme.sh 命令
    export PATH="$HOME/.acme.sh:$PATH"

    # 导出 Cloudflare 环境变量，供 acme.sh 使用
    export CF_Token="$CF_Token"
    export CF_Account_ID="$CF_Account_ID"
    
        # 申请证书
    print_info "正在为域名 $DOMAIN 申请 SSL 证书..."
    
    # 先切换到 Let's Encrypt
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    
    ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN"
    if [ $? -ne 0 ]; then
        print_warning "使用 Let's Encrypt 申请失败，尝试切换至 ZeroSSL..."
        /root/.acme.sh/acme.sh --set-default-ca --server zerossl
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN"
        if [ $? -ne 0 ]; then
            print_error "证书申请失败，请检查您的 Cloudflare 配置或稍后再试。"
            exit 1
        fi
    fi
    print_success "证书申请成功！"

    # 新建文件夹，并赋予权限
    CERT_DIR="/etc/nginx/ssl"
    if [ ! -d "$CERT_DIR" ]; then
        print_info "正在创建证书存储目录 $CERT_DIR"
        mkdir -p "$CERT_DIR"
    fi
    chown root:root "$CERT_DIR"
    chmod 755 "$CERT_DIR"
    print_success "证书目录已创建并设置好权限。"

    # 安装证书到 Nginx 指定目录
    print_info "正在安装证书到 $CERT_DIR"
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file "$CERT_DIR/$DOMAIN.key" \
        --fullchain-file "$CERT_DIR/$DOMAIN.pem" \
        --reloadcmd "systemctl reload nginx"

    if [ $? -ne 0 ]; then
        print_error "证书安装失败，请手动检查 Nginx 目录权限或配置。"
        exit 1
    fi
    print_success "证书已成功安装！"

    # 查看已安装证书信息
    print_info "正在查看已安装证书信息..."
    acme.sh --info -d "$DOMAIN"

    # 自动升级 acme.sh
    print_info "正在设置 acme.sh 自动升级..."
    acme.sh --upgrade --auto-upgrade
    
    show_completion_info
}

# 调用主函数
main
