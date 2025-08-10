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
    echo -e "${BLUE}=========================================="
    echo "         acme.sh SSL 证书一键申请脚本"
    echo "==========================================${NC}"
}

# (其余代码省略，与你提供的相同)

# 显示完成信息
show_completion_info() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "            🎉 SSL 证书申请完成！"
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

# (主函数及其他代码省略，与你提供的相同)
