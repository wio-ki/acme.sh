#!/bin/bash
# ===============================================
# 脚本名称：acme_cert_setup.sh
# 脚本功能：使用 acme.sh 自动化申请 SSL 证书
# 版本：2.0
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
    echo -e "${BLUE}"
    echo "=========================================="
    echo "       acme.sh SSL 证书一键申请脚本"
    echo "=========================================="
    echo -e "${NC}"
}

# 检查是否为 root 用户，如果不是则自动切换
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_warning "检测到当前用户不是 root，正在自动切换到 root 用户..."
        
        # 检查是否可以使用 sudo
        if command -v sudo &> /dev/null; then
            print_info "使用 sudo 重新执行脚本..."
            # 重新以 root 权限执行当前脚本，传递所有原始参数
            exec sudo bash "$0" "$@"
        else
            print_error "系统中没有安装 sudo，无法自动切换到 root 用户"
            print_info "请手动切换到 root 用户后重新运行此脚本："
            echo "su -"
            echo "然后运行: bash $0"
            exit 1
        fi
    fi
    print_success "Root 权限检查通过"
}

# 检查系统类型
check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
        print_info "检测到系统：$OS $VERSION"
        
        # 检查是否为 Debian/Ubuntu 系统
        if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
            PACKAGE_MANAGER="apt"
            print_success "系统兼容性检查通过"
        else
            print_warning "检测到非 Debian/Ubuntu 系统，脚本可能需要调整"
            read -p "是否继续执行？(y/N): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                print_info "用户取消执行"
                exit 0
            fi
            PACKAGE_MANAGER="apt"  # 假设仍使用 apt
        fi
    else
        print_warning "无法检测系统类型，假设为 Debian/Ubuntu"
        PACKAGE_MANAGER="apt"
    fi
}

# 验证域名格式
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# 验证邮箱格式
validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取用户输入
get_user_input() {
    echo ""
    print_info "请输入以下信息："
    echo ""
    
    # 获取域名
    while true; do
        read -p "请输入你的域名（例如：example.com）：" DOMAIN
        if [ -z "$DOMAIN" ]; then
            print_error "域名不能为空"
            continue
        fi
        if validate_domain "$DOMAIN"; then
            break
        else
            print_error "域名格式不正确，请重新输入"
        fi
    done
    
    # 获取邮箱
    while true; do
        read -p "请输入你的电子邮件地址：" EMAIL
        if [ -z "$EMAIL" ]; then
            print_error "邮箱不能为空"
            continue
        fi
        if validate_email "$EMAIL"; then
            break
        else
            print_error "邮箱格式不正确，请重新输入"
        fi
    done
    
    # 获取 Cloudflare API Token
    while true; do
        read -s -p "请输入你的 Cloudflare API Token：" CF_TOKEN
        echo ""
        if [ -z "$CF_TOKEN" ]; then
            print_error "Cloudflare API Token 不能为空"
            continue
        fi
        if [ ${#CF_TOKEN} -lt 20 ]; then
            print_error "API Token 长度似乎不正确，请检查后重新输入"
            continue
        fi
        break
    done
    
    # 获取 Cloudflare Account ID
    while true; do
        read -p "请输入你的 Cloudflare 账户 ID：" CF_ACCOUNT_ID
        if [ -z "$CF_ACCOUNT_ID" ]; then
            print_error "Cloudflare 账户 ID 不能为空"
            continue
        fi
        if [ ${#CF_ACCOUNT_ID} -ne 32 ]; then
            print_error "账户 ID 长度应为32位，请检查后重新输入"
            continue
        fi
        break
    done
    
    # 确认信息
    echo ""
    print_info "请确认输入的信息："
    echo "域名：$DOMAIN"
    echo "邮箱：$EMAIL"
    echo "Cloudflare API Token：${CF_TOKEN:0:10}...（已隐藏部分内容）"
    echo "Cloudflare 账户 ID：$CF_ACCOUNT_ID"
    echo ""
    
    read -p "信息是否正确？(Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_info "请重新输入信息"
        get_user_input
    fi
}

# 检查网络连接
check_network() {
    print_info "检查网络连接..."
    if ping -c 1 google.com &> /dev/null || ping -c 1 baidu.com &> /dev/null; then
        print_success "网络连接正常"
    else
        print_error "网络连接异常，请检查网络设置"
        exit 1
    fi
}

# 更新软件包列表
update_packages() {
    print_info "更新软件包列表..."
    if apt update -y > /dev/null 2>&1; then
        print_success "软件包列表更新完成"
    else
        print_error "软件包列表更新失败"
        exit 1
    fi
}

# 安装 Nginx
install_nginx() {
    print_info "检查 Nginx 安装状态..."
    if command -v nginx &> /dev/null; then
        print_warning "Nginx 已安装，跳过安装步骤"
        return 0
    fi
    
    print_info "安装 Nginx..."
    if apt install nginx -y > /dev/null 2>&1; then
        print_success "Nginx 安装完成"
        
        # 启动并启用 Nginx 服务
        systemctl start nginx
        systemctl enable nginx
        
        if systemctl is-active --quiet nginx; then
            print_success "Nginx 服务已启动"
        else
            print_warning "Nginx 安装完成但服务启动失败"
        fi
    else
        print_error "Nginx 安装失败"
        exit 1
    fi
}

# 安装必要的依赖
install_dependencies() {
    print_info "安装必要的依赖包..."
    local deps="curl wget cron socat"
    
    for dep in $deps; do
        if ! command -v $dep &> /dev/null; then
            print_info "安装 $dep..."
            apt install $dep -y > /dev/null 2>&1
        fi
    done
    print_success "依赖包检查完成"
}

# 安装 acme.sh
install_acme() {
    print_info "检查 acme.sh 安装状态..."
    
    if [ -f "/root/.acme.sh/acme.sh" ]; then
        print_warning "acme.sh 已安装，跳过安装步骤"
        return 0
    fi
    
    print_info "安装 acme.sh..."
    if curl -s https://get.acme.sh | sh -s email="$EMAIL" > /dev/null 2>&1; then
        print_success "acme.sh 安装完成"
        
        # 重新加载环境变量
        source ~/.bashrc 2>/dev/null || true
        
        # 验证安装
        if [ -f "/root/.acme.sh/acme.sh" ]; then
            print_success "acme.sh 安装验证成功"
        else
            print_error "acme.sh 安装验证失败"
            exit 1
        fi
    else
        print_error "acme.sh 安装失败"
        print_info "请检查网络连接或稍后重试"
        exit 1
    fi
}

# 申请证书
request_certificate() {
    print_info "配置 Cloudflare 环境变量并申请证书..."
    
    # 导出环境变量
    export CF_Token="$CF_TOKEN"
    export CF_Account_ID="$CF_ACCOUNT_ID"
    
    print_info "开始申请域名 $DOMAIN 的 SSL 证书..."
    
    if /root/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" --debug 2>/dev/null; then
        print_success "证书申请成功"
    else
        print_error "证书申请失败"
        print_info "可能的原因："
        echo "  1. Cloudflare API Token 权限不足"
        echo "  2. 域名未托管在 Cloudflare"
        echo "  3. API Token 或 Account ID 错误"
        echo "  4. 网络连接问题"
        echo ""
        print_info "请检查以上问题后重新运行脚本"
        exit 1
    fi
}

# 创建证书存储目录
create_ssl_directory() {
    print_info "创建证书存储目录..."
    
    if mkdir -p /etc/nginx/ssl/; then
        chown root:root /etc/nginx/ssl/
        chmod 755 /etc/nginx/ssl/
        print_success "证书存储目录创建完成"
    else
        print_error "证书存储目录创建失败"
        exit 1
    fi
}

# 安装证书
install_certificate() {
    print_info "安装证书到 Nginx 目录..."
    
    if /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file /etc/nginx/ssl/"$DOMAIN".key \
        --fullchain-file /etc/nginx/ssl/"$DOMAIN".pem \
        --reloadcmd "systemctl reload nginx" > /dev/null 2>&1; then
        print_success "证书安装完成"
        
        # 验证证书文件
        if [ -f "/etc/nginx/ssl/$DOMAIN.key" ] && [ -f "/etc/nginx/ssl/$DOMAIN.pem" ]; then
            print_success "证书文件验证成功"
        else
            print_warning "证书文件可能未正确创建"
        fi
    else
        print_error "证书安装失败"
        exit 1
    fi
}

# 查看证书信息
show_certificate_info() {
    print_info "查看已安装证书信息..."
    echo ""
    /root/.acme.sh/acme.sh --info -d "$DOMAIN" 2>/dev/null || print_warning "无法获取证书信息"
    echo ""
}

# 配置自动升级
setup_auto_upgrade() {
    print_info "配置 acme.sh 自动升级..."
    
    if /root/.acme.sh/acme.sh --upgrade --auto-upgrade > /dev/null 2>&1; then
        print_success "acme.sh 自动升级配置完成"
    else
        print_warning "acme.sh 自动升级配置失败，但不影响证书使用"
    fi
}

# 显示完成信息
show_completion_info() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "         🎉 SSL 证书申请完成！"
    echo "==========================================${NC}"
    echo ""
    print_success "证书文件位置："
    echo "  • 私钥文件: /etc/nginx/ssl/$DOMAIN.key"
    echo "  • 证书文件: /etc/nginx/ssl/$DOMAIN.pem"
    echo ""
    print_info "下一步操作："
    echo "  1. 配置 Nginx 以使用 SSL 证书"
    echo "  2. 测试网站 HTTPS 访问"
    echo "  3. 证书将自动续期，无需手动操作"
    echo ""
    print_info "Nginx SSL 配置示例："
    echo "  server {"
    echo "    listen 443 ssl;"
    echo "    server_name $DOMAIN;"
    echo "    ssl_certificate /etc/nginx/ssl/$DOMAIN.pem;"
    echo "    ssl_certificate_key /etc/nginx/ssl/$DOMAIN.key;"
    echo "    # ... 其他配置"
    echo "  }"
    echo ""
    echo -e "${BLUE}=========================================="
    echo "            脚本执行完成"
    echo "==========================================${NC}"
    echo ""
}

# 清理函数
cleanup_on_error() {
    print_error "脚本执行过程中发生错误，正在清理..."
    # 这里可以添加清理逻辑
    exit 1
}

# 设置错误处理
trap cleanup_on_error ERR

# 主函数
main() {
    show_banner
    
    # 基础检查
    check_root
    check_system
    check_network
    
    # 获取用户输入
    get_user_input
    
    # 系统准备
    update_packages
    install_dependencies
    install_nginx
    
    # acme.sh 安装和配置
    install_acme
    
    # 证书申请和安装
    request_certificate
    create_ssl_directory
    install_certificate
    
    # 后续配置
    show_certificate_info
    setup_auto_upgrade
    
    # 显示完成信息
    show_completion_info
}

# 执行主函数
main "$@"
