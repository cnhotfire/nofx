# iptables端口限制脚本使用说明

## 功能描述
此脚本用于限制8080和3000端口的访问权限，只允许`ip.txt`文件中指定的IP地址访问这两个端口。

## 文件说明
- `iptables_port_restrict.sh` - 主要的iptables配置脚本
- `ip.txt` - 允许访问的IP地址列表
- `README_iptables.md` - 使用说明文档

## 使用方法

### 1. 基本使用
```bash
# 需要root权限运行
sudo ./iptables_port_restrict.sh
```

### 2. 命令行选项
```bash
# 显示帮助信息
./iptables_port_restrict.sh -h

# 清除所有端口限制规则
sudo ./iptables_port_restrict.sh -c

# 显示当前规则状态
./iptables_port_restrict.sh -s

# 仅备份当前规则
sudo ./iptables_port_restrict.sh -b
```

### 3. 配置IP白名单
编辑 `ip.txt` 文件，每行一个IP地址：
```
# 注释行以#开头
192.168.1.100
10.0.0.50
172.16.0.0/16
```

## 脚本特性

### 安全特性
- ✅ 自动备份现有iptables规则
- ✅ IP地址格式验证
- ✅ 支持IP/掩码格式（如192.168.1.0/24）
- ✅ 本地回环地址(127.0.0.1)始终被允许
- ✅ 日志记录被拒绝的连接尝试

### 管理特性
- ✅ 支持注释行（#开头）
- ✅ 自动忽略空行
- ✅ 彩色输出，便于阅读
- ✅ 详细的操作日志
- ✅ 规则状态查看

### 技术特性
- ✅ 使用自定义iptables链，便于管理
- ✅ 支持多次执行，自动更新规则
- ✅ 错误处理和回滚机制
- ✅ 规则冲突检测和处理

## 工作原理

1. **读取配置**：从`ip.txt`读取允许的IP地址列表
2. **备份规则**：自动备份当前iptables规则
3. **清理旧规则**：删除现有的端口限制规则
4. **创建新规则**：
   - 为每个端口创建自定义链
   - 添加允许的IP地址规则
   - 添加本地访问规则
   - 添加日志记录和拒绝规则
5. **应用规则**：将自定义链插入到INPUT链中

## 规则结构

脚本会为每个受限制的端口创建独立的自定义链：
- `PORT_8080_RESTRICT` - 8080端口限制链
- `PORT_3000_RESTRICT` - 3000端口限制链

每个链包含以下规则（按顺序）：
1. 允许指定IP地址访问
2. 允许本地回环访问
3. 记录被拒绝的连接尝试
4. 拒绝其他所有访问

## 维护操作

### 更新IP白名单
1. 编辑 `ip.txt` 文件
2. 重新运行脚本：`sudo ./iptables_port_restrict.sh`

### 查看当前规则
```bash
# 查看所有iptables规则
sudo iptables -L -n -v

# 查看特定端口的规则
sudo iptables -L PORT_8080_RESTRICT -n -v
sudo iptables -L PORT_3000_RESTRICT -n -v
```

### 查看连接日志
```bash
# 查看被拒绝的连接尝试
sudo dmesg | grep PORT_RESTRICT

# 或者查看系统日志
sudo journalctl -k | grep PORT_RESTRICT
```

### 清除所有规则
```bash
sudo ./iptables_port_restrict.sh -c
```

## 注意事项

### 权限要求
- 脚本必须以root权限运行
- 确保有足够的权限修改iptables规则

### 持久化
- iptables规则在系统重启后会失效
- 如需永久保存，请安装并配置iptables-persistent：
  ```bash
  # Ubuntu/Debian
  sudo apt-get install iptables-persistent

  # 保存当前规则
  sudo netfilter-persistent save

  # 恢复规则
  sudo netfilter-persistent reload
  ```

### 网络环境
- 确保在配置规则前有其他方式访问服务器（如物理控制台）
- 测试规则前建议先在测试环境验证
- 配置完成后立即测试连接性

### 防火墙冲突
- 如果系统有其他防火墙（如UFW、firewalld），可能需要先禁用
- 确保iptables是主要的防火墙管理工具

## 故障排除

### 常见问题
1. **无法访问端口**：检查IP是否在白名单中
2. **规则不生效**：确认以root权限运行脚本
3. **本地无法访问**：确保127.0.0.1始终被允许

### 调试步骤
1. 查看当前规则：`sudo ./iptables_port_restrict.sh -s`
2. 检查IP文件格式：确保没有语法错误
3. 查看系统日志：检查被拒绝的连接记录
4. 恢复备份规则：使用脚本创建的备份文件

### 紧急恢复
如果配置导致无法访问服务器：
1. 通过物理控制台或SSH密钥登录
2. 清除所有规则：`sudo ./iptables_port_restrict.sh -c`
3. 或者恢复备份规则：`sudo iptables-restore < iptables_backup_*.rules`

## 示例配置

### 允许特定网段
```
# 允许整个内网段
192.168.1.0/24
10.0.0.0/8

# 允许特定IP
203.0.113.10
198.51.100.5
```

### 生产环境建议
- 定期审查IP白名单
- 设置合理的日志轮转
- 监控被拒绝的连接尝试
- 建立紧急访问机制