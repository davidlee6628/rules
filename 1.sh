#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 基础配置
INSTALL_DIR="/root/drpy-node"
LOG_FILE="/tmp/drpy_install.log"
MIRROR_LIST=(
  "https://ghproxy.com/https://github.com/hjdhnx/drpy-node.git"
  "https://hub.fgit.ml/hjdhnx/drpy-node.git"
  "https://gitclone.com/github.com/hjdhnx/drpy-node.git"
  "https://ghps.cc/https://github.com/hjdhnx/drpy-node.git"
  "https://gh.ddlc.top/https://github.com/hjdhnx/drpy-node.git"
  "https://gh-proxy.com/https://github.com/hjdhnx/drpy-node.git"
)

# 初始化日志
init_log() {
  > "$LOG_FILE"
  exec 3>&1 4>&2
  exec 1>>"$LOG_FILE" 2>&1
  trap 'exec 1>&3 2>&4' EXIT
}

# 网络诊断
network_diagnosis() {
  echo -e "\n${YELLOW}=== 网络诊断开始 ===${NC}"
  
  # 基础连通性测试
  ping_test() {
    local targets=(114.114.114.114 github.com ghproxy.com)
    for t in "${targets[@]}"; do
      if ping -c 2 -W 1 "$t" &>/dev/null; then
        echo -e "${GREEN}✔ 可达 - $t${NC}"
      else
        echo -e "${RED}✘ 不可达 - $t${NC}"
      fi
    done
  }
  
  # HTTP测试
  http_test() {
    local urls=("https://github.com" "https://ghproxy.com")
    for url in "${urls[@]}"; do
      local code=$(curl -o /dev/null -s -w "%{http_code}" --connect-timeout 5 "$url")
      [ "$code" == "200" ] || [ "$code" == "301" ] || [ "$code" == "302" ] && \
        echo -e "${GREEN}✔ 可达 - $url (HTTP $code)${NC}" || \
        echo -e "${RED}✘ 不可达 - $url${NC}"
    done
  }
  
  # DNS解析测试
  dns_test() {
    local domains=(github.com ghproxy.com)
    for domain in "${domains[@]}"; do
      if nslookup "$domain" &>/dev/null; then
        echo -e "${GREEN}✔ 解析成功 - $domain${NC}"
      else
        echo -e "${RED}✘ 解析失败 - $domain${NC}"
      fi
    done
  }

  ping_test
  http_test
  dns_test
  echo -e "${YELLOW}=== 网络诊断结束 ===${NC}\n"
}

# 镜像源测速
mirror_speed_test() {
  declare -A speed_results
  local timeout=3
  
  echo -e "${YELLOW}▶ 镜像源测速中...${NC}"
  for mirror in "${MIRROR_LIST[@]}"; do
    # 提取域名用于显示
    local domain=$(echo "$mirror" | awk -F/ '{print $3}')
    
    # 速度测试（下载100KB测试文件）
    local speed=$(curl -o /dev/null \
      -sL \
      -w "%{speed_download}" \
      --connect-timeout $timeout \
      "${mirror//.git/\/archive/refs/heads/main.zip}" \
      -H 'Range: bytes=0-102400' 2>/dev/null)
    
    if [ -n "$speed" ]; then
      speed=$(awk "BEGIN {printf \"%.2f\", $speed/1024}")
      speed_results["$mirror"]=$speed
      echo -e "${BLUE}鈼� ${domain} ${speed}KB/s${NC}"
    else
      speed_results["$mirror"]="fail"
      echo -e "${RED}✘ ${domain} 测速失败${NC}"
    fi
  done

  # 选择最佳镜像
  local selected=""
  local max_speed=0
  for mirror in "${!speed_results[@]}"; do
    if [[ "${speed_results[$mirror]}" =~ ^[0-9.]+$ ]]; then
      if awk "BEGIN {exit !(${speed_results[$mirror]} > $max_speed)}"; then
        max_speed=${speed_results[$mirror]}
        selected=$mirror
      fi
    fi
  done

  [ -n "$selected" ] && echo "$selected" || return 1
}

# 智能克隆
smart_clone() {
  local retries=3
  local delay=2
  
  # 自动选择镜像
  local best_mirror=$(mirror_speed_test)
  if [ -z "$best_mirror" ]; then
    echo -e "${RED}✘ 所有镜像测速失败，尝试交互选择${NC}"
    best_mirror=$(manual_mirror_select)
  fi

  # 克隆主逻辑
  for ((i=1; i<=retries; i++)); do
    echo -e "${YELLOW}▶ 尝试克隆 (第 $i 次) [源: ${best_mirror//*\/\//}]${NC}"
    
    # 使用深度克隆优化大仓库
    if git clone --depth 1 "$best_mirror" "$INSTALL_DIR"; then
      return 0
    else
      # 清理失败目录
      rm -rf "$INSTALL_DIR"
      echo -e "${RED}✘ 克隆失败，等待 ${delay}秒...${NC}"
      sleep $delay
    fi
  done
  
  return 1
}

# 手动镜像选择
manual_mirror_select() {
  echo -e "\n${YELLOW}? 请手动选择镜像源：${NC}"
  select mirror in "${MIRROR_LIST[@]}" "自定义源"; do
    if [ "$REPLY" -le "${#MIRROR_LIST[@]}" ]; then
      echo "${MIRROR_LIST[$((REPLY-1))]}"
      return
    elif [ "$REPLY" -eq "$(( ${#MIRROR_LIST[@]}+1 ))" ]; then
      read -p "请输入完整镜像URL: " custom_mirror
      echo "$custom_mirror"
      return
    fi
  done
}

# 离线应急方案
offline_install() {
  echo -e "${YELLOW}▶ 启用离线安装模式${NC}"
  
  # 检测本地备份
  local backup_dirs=("/mnt/usb/drpy-backup" "/root/drpy-backup")
  for dir in "${backup_dirs[@]}"; do
    if [ -f "$dir/drpy-main.zip" ]; then
      echo -e "${BLUE}鈼� 发现本地备份于 $dir${NC}"
      unzip -q "$dir/drpy-main.zip" -d "$INSTALL_DIR"
      return $?
    fi
  done

  # 下载应急包
  local emergency_url="https://gd.bmp.ovh/imgs/2024/06/14/drpy-emergency.zip"
  if curl -L "$emergency_url" -o /tmp/drpy-emergency.zip; then
    unzip -q /tmp/drpy-emergency.zip -d "$INSTALL_DIR"
    return $?
  fi
  
  return 1
}

# 主安装流程
main_install() {
  # 准备环境
  mkdir -p "$(dirname "$INSTALL_DIR")"
  rm -rf "$INSTALL_DIR"
  
  # 网络诊断
  network_diagnosis
  
  # 尝试智能克隆
  if ! smart_clone; then
    echo -e "${RED}✘ 智能克隆失败，尝试离线安装${NC}"
    if ! offline_install; then
      echo -e "${RED}✘ 所有安装方式均失败，请检查："
      echo -e "1. 网络连接状态"
      echo -e "2. 防火墙设置"
      echo -e "3. 磁盘空间 (剩余空间需大于500MB)"
      echo -e "4. 详细日志请查看: $LOG_FILE${NC}"
      exit 1
    fi
  fi
  
  # 后续安装步骤
  echo -e "${GREEN}✔ 克隆成功，开始部署...${NC}"
  cd "$INSTALL_DIR"
  npm install --registry=https://registry.npmmirror.com
  pm2 start index.js --name drpy-node
}

# 执行主程序
init_log
echo -e "\n${BLUE}=== drpy-node 安装程序开始 ===${NC}"
main_install
echo -e "${GREEN}✅ 安装完成！访问地址：http://$(curl -s icanhazip.com):5757${NC}"
echo -e "${YELLOW}ⓘ 详细日志: $LOG_FILE${NC}"
