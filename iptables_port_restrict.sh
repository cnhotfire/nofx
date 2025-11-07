#!/bin/bash

# iptables端口限制脚本
# 限制8080和3000端口，只允许ip.txt中的IP地址访问

# 定义变量
IPTABLES=$(which iptables)
IP_FILE="ip.txt"
PORTS=("8080" "3000")
LOG_PREFIX="PORT_RESTRICT"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查iptables是否可用
check_iptables() {
    if ! command -v iptables &> /dev/null; then
        log_error "iptables未安装或不可用"
        exit 1
    fi
}

# 检查ip.txt文件是否存在
check_ip_file() {
    if [[ ! -f "$IP_FILE" ]]; then
        log_error "IP文件 $IP_FILE 不存在"
        log_info "请创建 $IP_FILE 文件，每行一个IP地址"
        exit 1
    fi
}

# 验证IP地址格式
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# 读取IP地址列表
read_ip_list() {
    local ip_list=()

    while IFS= read -r line; do
        # 去除空行和注释
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^#')

        if [[ -n "$line" ]]; then
            if validate_ip "$line"; then
                ip_list+=("$line")
            else
                log_warn "无效的IP地址: $line"
            fi
        fi
    done < "$IP_FILE"

    echo "${ip_list[@]}"
}

# 备份当前iptables规则
backup_iptables() {
    local backup_file="iptables_backup_$(date +%Y%m%d_%H%M%S).rules"
    if $IPTABLES-save > "$backup_file"; then
        log_info "当前iptables规则已备份到: $backup_file"
    else
        log_warn "备份iptables规则失败"
    fi
}

# 清除现有的端口限制规则
clear_existing_rules() {
    log_info "清除现有的端口限制规则..."

    # 删除INPUT链中相关的规则
    for port in "${PORTS[@]}"; do
        # 删除针对这些端口的现有规则
        $IPTABLES -D INPUT -p tcp --dport "$port" -j DROP 2>/dev/null || true
        $IPTABLES -D INPUT -p tcp --dport "$port" -s 127.0.0.1 -j ACCEPT 2>/dev/null || true

        # 删除自定义链中的规则（如果存在）
        $IPTABLES -F "PORT_${port}_RESTRICT" 2>/dev/null || true
        $IPTABLES -D INPUT -p tcp --dport "$port" -j "PORT_${port}_RESTRICT" 2>/dev/null || true
        $IPTABLES -X "PORT_${port}_RESTRICT" 2>/dev/null || true
    done
}

# 创建端口限制规则
create_port_rules() {
    local ip_list=($@)

    if [[ ${#ip_list[@]} -eq 0 ]]; then
        log_warn "IP列表为空，将拒绝所有访问"
    fi

    for port in "${PORTS[@]}"; do
        log_info "为端口 $port 创建访问规则..."

        # 创建自定义链
        $IPTABLES -N "PORT_${port}_RESTRICT" 2>/dev/null || true

        # 如果IP列表不为空，添加允许规则
        if [[ ${#ip_list[@]} -gt 0 ]]; then
            for ip in "${ip_list[@]}"; do
                log_info "  允许IP: $ip 访问端口 $port"
                $IPTABLES -A "PORT_${port}_RESTRICT" -s "$ip" -j ACCEPT
            done
        fi

        # 始终允许本地访问
        $IPTABLES -A "PORT_${port}_RESTRICT" -s 127.0.0.1 -j ACCEPT

        # 添加日志记录（可选）
        $IPTABLES -A "PORT_${port}_RESTRICT" -j LOG --log-prefix "$LOG_PREFIX: " --log-level 4

        # 拒绝其他所有访问
        $IPTABLES -A "PORT_${port}_RESTRICT" -j DROP

        # 将自定义链插入到INPUT链的合适位置
        # 检查是否已经存在跳转规则
        if ! $IPTABLES -C INPUT -p tcp --dport "$port" -j "PORT_${port}_RESTRICT" 2>/dev/null; then
            $IPTABLES -I INPUT -p tcp --dport "$port" -j "PORT_${port}_RESTRICT"
        fi
    done
}

# 显示当前规则状态
show_rules() {
    log_info "当前iptables规则状态:"
    echo "================================"
    $IPTABLES -L -n | grep -E "(PORT_|8080|3000)" || log_warn "未找到相关规则"
    echo "================================"
}

# 创建IP文件模板
create_ip_template() {
    if [[ ! -f "$IP_FILE" ]]; then
        log_info "创建IP文件模板: $IP_FILE"
        cat > "$IP_FILE" << EOF
# IP地址列表
# 每行一个IP地址，以#开头的行为注释
# 示例:
# 192.168.1.100
# 10.0.0.50
# 172.16.0.0/16

# 本地回环地址始终被允许
127.0.0.1
EOF
        log_info "请编辑 $IP_FILE 文件，添加允许访问的IP地址"
    fi
}

# 主函数
main() {
    log_info "开始配置iptables端口限制规则..."

    # 检查运行环境
    check_root
    check_iptables

    # 创建IP文件模板（如果不存在）
    create_ip_template

    # 检查IP文件
    check_ip_file

    # 读取IP列表
    ip_list=($(read_ip_list))

    if [[ ${#ip_list[@]} -eq 0 ]]; then
        log_warn "未找到有效的IP地址"
    else
        log_info "找到 ${#ip_list[@]} 个有效IP地址: ${ip_list[*]}"
    fi

    # 备份当前规则
    backup_iptables

    # 清除现有规则
    clear_existing_rules

    # 创建新规则
    create_port_rules "${ip_list[@]}"

    # 显示当前规则
    show_rules

    log_info "iptables规则配置完成！"
    log_info "允许的端口: ${PORTS[*]}"
    log_info "允许的IP数量: ${#ip_list[@]}"

    if [[ ${#ip_list[@]} -gt 0 ]]; then
        log_info "允许的IP地址: ${ip_list[*]}"
    fi

    log_warn "注意: 此规则在系统重启后会失效，如需永久保存请使用 iptables-persistent"
}

# 显示使用帮助
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -c, --clear    清除所有端口限制规则"
    echo "  -s, --show     显示当前规则状态"
    echo "  -b, --backup   仅备份当前规则"
    echo ""
    echo "说明:"
    echo "  此脚本会读取 ip.txt 文件中的IP地址列表"
    echo "  只允许这些IP地址访问8080和3000端口"
    echo "  本地回环地址(127.0.0.1)始终被允许"
    echo ""
    echo "ip.txt 文件格式:"
    echo "  每行一个IP地址"
    echo "  以#开头的行为注释"
    echo "  支持IP/掩码格式，如 192.168.1.0/24"
}

# 清除规则函数
clear_all_rules() {
    check_root
    check_iptables
    clear_existing_rules
    log_info "已清除所有端口限制规则"
}

# 处理命令行参数
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -c|--clear)
        clear_all_rules
        exit 0
        ;;
    -s|--show)
        show_rules
        exit 0
        ;;
    -b|--backup)
        check_root
        check_iptables
        backup_iptables
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "未知选项: $1"
        show_help
        exit 1
        ;;
esac