# 前置条件

## 获得你当前局域网的出口 ip

```
for i in {1..4};do dig +timeout=10 +short myip.opendns.com @resolver$i.opendns.com;done | sort -n | uniq
```

得到 N 个出口 ip

## 预先设置 N 条规则 **非常重要！！！**

把前面得到的 N 个出口 ip，在每个安全组中预先添加 N 条规则。**_以防止脚本执行后安全组中的前 N 条规则会被覆盖_**

# 构建二进制文件

更新 go.mod 和 go.sum 文件

```
go mod tidy
```

移动到 vendor 目录（可选）

```
go mod vendor
```

编译成 Linux 客户端

```
# 方式一：使用 module 依赖（推荐）
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -mod=mod -o modifyingSecurityGroup_linux .

# 方式二：使用 vendor 目录（如需完全离线或固定依赖）
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -mod=vendor -o modifyingSecurityGroup_linux .
```

编译成 Windows 客户端

```
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -mod=mod -o modifyingSecurityGroup.exe .
```

编译成 Mac 客户端

```
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -mod=mod -o modifyingSecurityGroup_mac .
```

# 在 linux 上运行

## 方式1，创建 cron 任务

复制 config.toml 和 modifyingSecurityGroup_linux 到 Linux 服务器上，在 config.toml 中配置适当的认证信息和安全组

```
crontab -e ，然后添加以下内容
# 每1小时执行一次，仅获取IP并写入文件（不更新安全组、不发钉钉）
* */1 * * * cd /root/modifyingSecurityGroup && ./modifyingSecurityGroup_linux --minRequiredIPs 2 --maxRequiredIPs 5 --updateSG=false --notifyDingTalk=false >> /tmp/txmodSecurityGroup.log 2>&1
```

## 手动指定出口 ip(特殊情况下使用)

### 1. 手动将待添加的出口 ip 写入到一个文本文件中，假设是 myips.txt

### 2. 执行以下命令

```
    ./modifyingSecurityGroup_linux -ip myips.txt
```

### 参数说明（获取 IP）

- --ip：指定包含 IP 地址的文件路径。如果提供此参数，程序将从文件中读取 IP 地址，而不是在线获取。
- --maxAttempts：最大尝试次数，用于在线获取 IP 地址时的并发请求数。默认值为 30。
- --minRequiredIPs：所需的唯一 IP 数量。程序将在获取到指定数量的唯一 IP 后停止。默认值为 2。
- --maxRequiredIPs：所需的唯一 IP 数量。程序将在获取到指定数量的唯一 IP 后停止。默认值为 5,此参数不应大于前面的 N 相等。

### 新增命令选项（根据对话修改后的主程序）
- --updateSG：是否执行腾讯云安全组更新。布尔，默认 true。
- --notifyDingTalk：是否发送钉钉通知（仅当有安全组更新时）。布尔，默认 true。
- --externalScript：要执行的外部脚本路径，支持 `.sh`（Linux/macOS）、`.py`（Python脚本）与 `.bat`/`.cmd`（Windows），也可为普通可执行文件。默认空。
- --externalScriptArgs：传给外部脚本的参数字符串，空格分隔。默认空。

### 示例
- 只获取 IP 并写入文件：
  `./modifyingSecurityGroup_linux --minRequiredIPs 2 --maxRequiredIPs 5 --updateSG=false --notifyDingTalk=false`
- 获取 IP 后执行外部脚本（Linux）：
  `./modifyingSecurityGroup_linux --externalScript ./modifyingSG.sh --externalScriptArgs "--minRequiredIPs 1 --maxRequiredIPs 10"`
- 获取 IP 后执行 Python 脚本（Linux/macOS）：
  `./modifyingSecurityGroup_linux --externalScript ./script.py --externalScriptArgs "arg1 arg2"`
- 获取 IP 后执行外部脚本（Windows，在 Windows 上运行）：
  `modifyingSecurityGroup.exe --externalScript "D:\\Program Files\\modifyingSecurityGroup\\modifyingSG.bat" --externalScriptArgs "--minRequiredIPs 2 --maxRequiredIPs 5"`
 - 获取 IP 后执行 Python 脚本（Windows）：
  `modifyingSecurityGroup.exe --externalScript "C:\\path\\to\\script.py" --externalScriptArgs "arg1 arg2"`

### 外部脚本示例：通过 SSH 在远程服务器批量添加 UFW 规则

- 脚本位置：`ufw_update_remote.sh`
- 功能：读取本地 `ips.txt`，使用私钥登录远程服务器，依次执行 `sudo ufw allow from <IP> to any port 6379`
- 环境变量：
  - `REMOTE_HOST` 必填，格式 `user@host`（如 `user@1.2.3.4`）
  - `SSH_KEY` 可选，默认 `~/.ssh/id_myArgosy02`
  - `IPS_FILE` 可选，默认 `ips.txt`

- 赋予执行权限：
  - `chmod +x ./ufw_update_remote.sh`

- 直接执行脚本：
  - `REMOTE_HOST=user@1.2.3.4 SSH_KEY=~/.ssh/id_myArgosy02 IPS_FILE=ips.txt ./ufw_update_remote.sh`

- 由主程序调用（仅执行外部脚本，不更新安全组、不发钉钉）：
  - `REMOTE_HOST=user@1.2.3.4 SSH_KEY=~/.ssh/id_myArgosy02 IPS_FILE=ips.txt ./modifyingSecurityGroup_linux --externalScript ./ufw_update_remote.sh --updateSG=false --notifyDingTalk=false`

- 由主程序调用（先更新安全组，再执行外部脚本）：
  - `REMOTE_HOST=user@1.2.3.4 SSH_KEY=~/.ssh/id_myArgosy02 IPS_FILE=ips.txt ./modifyingSecurityGroup_linux --externalScript ./ufw_update_remote.sh --minRequiredIPs 1 --maxRequiredIPs 5`

- Cron 示例（每小时执行一次）：
  - `* */1 * * * cd /data/workspace/projects-code/modifyingSecurityGroup && ./modifyingSecurityGroup_linux --externalScript ./ufw_update_remote.sh --externalScriptArgs '--host root@45.32.61.224 --key /home/adminer/.ssh/id_myArgosy02 --file ./ips.txt --comment "Redis whitelist for myPC_ubuntu"' --updateSG=false --notifyDingTalk=true --minRequiredIPs 1 --maxRequiredIPs 1 >> /tmp/txmodSecurityGroup.log 2>&1`

- 注意：
  - 远程服务器需已安装并启用 `ufw`，当前用户具备执行 `sudo ufw ...` 的权限。
  - 若远程 `sudo` 需要密码，因脚本使用 `BatchMode=yes` 会失败；如需无密码自动化，请在远程配置合适的 `sudoers` 规则。
  - `ips.txt` 为本地文件路径，外部脚本在本机读取后逐条在远程添加规则。

## 方式2，创建 cron 任务（分成两段）
```
#更新腾讯云安全组
0 0,2,4,6,8 * * * /data/workspace/projects-code/modifyingSecurityGroup/modifyingSG.sh 
*/5 9-22 * * * /data/workspace/projects-code/modifyingSecurityGroup/modifyingSG.sh
```

# 在 Windows 上运行

## 创建计划任务

以管理员权限运行 CMD，然后执行以下命令

- 创建非高峰时段任务（00:00-08:59，每 2 小时）

```cmd
schtasks /create /tn "modifyingSecurityGroup_OffPeak" /tr "\"D:\Program Files\modifyingSecurityGroup\modifyingSG.bat\"" /sc DAILY /st 00:00 /ri 120 /du 08:59 /ed 9999/12/31 /ru "SYSTEM" /rl HIGHEST /f
```

- 创建高峰时段任务（09:00-22:00，每 5 分钟）

```cmd
schtasks /create /tn "modifyingSecurityGroup_Peak" /tr "\"D:\Program Files\modifyingSecurityGroup\modifyingSG.bat\"" /sc DAILY /st 09:00 /ri 5 /du 13:00 /ed 9999/12/31 /ru "SYSTEM" /rl HIGHEST /f
```

### 参数说明

- `/tn` 指定任务名称
- `/tr` 指定任务执行的程序路径
- `/sc` 指定任务的触发方式，DAILY：任务每日触发
- `/st` 指定任务的开始时间，00:00：每日开始时间为 00:00
- `/ri` 指定任务的重复间隔，5：重复间隔 5 分钟
- `/du` 指定任务的持续时间，23:59：持续 23:59
- `/ed` 指定任务的结束时间，9999/12/31：任务永久有效
- `/ru` 指定任务的运行用户，SYSTEM：以系统用户运行
- `/rl` 指定任务的运行权限，HIGHEST：最高权限
- `/f` 强制创建任务

## 查看计划任务

通过 schtasks /query 输出任务列表，并用 findstr 进行模糊匹配：

```cmd
schtasks /query /fo TABLE | findstr /i "modify"
```

查看特定计划任务详细信息：

```cmd
schtasks /query /tn  "modifyingSecurityGroup_OffPeak" /fo LIST /v
```

```cmd
schtasks /query /tn  "modifyingSecurityGroup_Peak" /fo LIST /v
```

## 删除计划任务

```cmd
schtasks /delete /tn "modifyingSecurityGroup_OffPeak" /f
```

```cmd
schtasks /delete /tn "modifyingSecurityGroup_Peak" /f
```

# 注意

0. 暂时仅支持腾讯云
1. 支持 Windows、Linux 和 macOS 平台
2. 暂时仅支持 IPv4 地址
3. 如使用 `--externalScript`：
   - Windows：支持 `.bat/.cmd`、`.py`，以及在系统具备 Bash 的情况下执行 `.sh`；
   - Linux/macOS：支持 `.sh`、`.py`，禁止 `.bat/.cmd`；
   - 其它扩展名按可执行文件处理，需要可执行权限与正确的 shebang。
