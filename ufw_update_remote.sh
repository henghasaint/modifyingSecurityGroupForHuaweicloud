#!/usr/bin/env bash

set -euo pipefail

SSH_KEY="$HOME/.ssh/id_myArgosy02"
REMOTE_HOST=""
IPS_FILE="ips.txt"
EXPLICIT_COMMENT=""

usage() {
  echo "用法: $0 --host <user@host> --key <ssh_key_path> --file <ips.txt> --comment <注释>"
  echo "示例: $0 --host root@1.2.3.4 --key ~/.ssh/id_myArgosy02 --file ./ips.txt --comment 'Redis whitelist for myPC_ubuntu'"
}

# 解析显式参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      REMOTE_HOST="$2"; shift 2;;
    --key)
      SSH_KEY="$2"; shift 2;;
    --file)
      IPS_FILE="$2"; shift 2;;
    --comment)
      EXPLICIT_COMMENT="$2"; shift 2;;
    --help|-h)
      usage; exit 0;;
    *)
      echo "未知参数: $1" >&2; usage; exit 1;;
  esac
done

SSH_KEY=${SSH_KEY:-$HOME/.ssh/id_myArgosy02}
IPS_FILE=${IPS_FILE:-ips.txt}

if [[ -z "$REMOTE_HOST" ]]; then
  echo "Error: 请通过参数 --host 指定远程服务器（例如 user@1.2.3.4）" >&2
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "Error: SSH私钥不存在: $SSH_KEY" >&2
  exit 1
fi

if [[ ! -f "$IPS_FILE" ]]; then
  echo "Error: 找不到IP列表文件: $IPS_FILE" >&2
  exit 1
fi

chmod 600 "$SSH_KEY" || true

echo "使用私钥: $SSH_KEY"
echo "目标服务器: $REMOTE_HOST"
echo "读取IP文件: $IPS_FILE"

while IFS= read -r ip; do
  ip_trimmed="$(echo "$ip" | tr -d ' \t\r\n')"
  if [[ -z "$ip_trimmed" ]]; then
    continue
  fi
  echo "检查并添加UFW规则: $ip_trimmed"
  
  # 使用 printf %q 确保注释参数安全地传递给远程 shell
  printf -v COMMENT_ARG "%q" "$EXPLICIT_COMMENT"
  
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes "$REMOTE_HOST" bash -s -- "$ip_trimmed" $COMMENT_ARG <<'REMOTE' || {
set -e
IP="$1"
COMMENT="$2"
echo "IP: $IP"
echo "COMMENT: $COMMENT"

# 定义执行添加规则的函数，使用数组确保空格处理正确
add_rule() {
    local target_ip="$1"
    local comment_txt="$2"
    
    # 基础命令数组
    local cmd=(sudo ufw allow from "$target_ip" to any port 6379)
    
    # 如果有注释，追加到数组
    if [ -n "$comment_txt" ]; then
        cmd+=(comment "$comment_txt")
    fi
    
    # 执行命令（"${cmd[@]}" 会正确展开数组，保留空格）
    echo "执行命令: ${cmd[*]}"
    "${cmd[@]}"
}

if [ -n "$COMMENT" ]; then
  echo "处理带注释的规则，COMMENT: $COMMENT"
  
  # 精确查找带有特定注释的UFW规则
  # 注意：这里awk处理比较复杂，为了稳健性，确保awk内部正确
  LINES=$(sudo ufw status numbered | awk -v want="$COMMENT" '
    {
      # 规范化空格
      $0 = gensub(/[[:space:]]+/, " ", "g", $0);
      
      # 分割行以提取注释部分 " # "
      # ufw output 格式示例: [ 1] 6379 ALLOW IN 1.2.3.4 # my comment
      n = split($0, a, " # ");
      if (n > 1) {
        # 这里的 a[2] 即为注释内容，可能包含后续的 (v6) 等标记，通常注释在 # 后
        # 简单处理：完全匹配
        com = a[2];
        # 去除前后可能的引号或空格
        gsub(/^[" ]+|[" ]+$/, "", com);
        if (com == want) print $0;
      }
    }
  ' || true)
  
  # 如果没有找到匹配特定注释的规则，直接添加新规则
  if [ -z "$LINES" ]; then
    echo "未找到匹配注释的规则，添加新规则"
    add_rule "$IP" "$COMMENT" && echo "UFW规则已添加"
  else
    # 提取第一个匹配规则的IP地址
    OLD_IP=$(echo "$LINES" | head -n 1 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)
    echo "旧IP: $OLD_IP"
    echo "新IP: $IP"
    
    # 比较IP地址是否相同
    if [ "$OLD_IP" = "$IP" ]; then
      echo "UFW规则已存在且IP一致，跳过更新"
    else
      echo "IP地址不同，需要更新规则"
      # 获取所有匹配规则的编号并删除旧规则
      # 注意：删除规则会导致编号变化，必须从大到小删除
      NUMS=$(echo "$LINES" | sed -n -E 's/^\[ *([0-9]+)\].*/\1/p' | sort -rn || true)
      echo "删除旧规则编号: $NUMS"
      for N in $NUMS; do
        yes | sudo ufw delete "$N"
      done
      # 添加新规则
      add_rule "$IP" "$COMMENT" && echo "UFW规则已替换"
    fi
  fi
else
  # 处理不带注释的规则
  echo "处理不带注释的规则"
  if sudo ufw status | sed -E 's/[[:space:]]+/ /g' | grep -E "^6379(/tcp|/udp)? +ALLOW +$IP(/32)?( |$)" >/dev/null; then
    echo "UFW规则已存在"
  else
    sudo ufw allow from "$IP" to any port 6379 && echo "UFW规则已添加"
  fi
fi
REMOTE
    echo "警告: 远程执行失败: $ip_trimmed" >&2
  }
done < "$IPS_FILE"

echo "UFW规则更新完成"