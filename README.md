# 华为云安全组自动更新工具

本工具用于自动检测本地公网 IP 变化，并自动更新华为云安全组规则。它特别适用于动态公网 IP 环境（如家庭宽带、办公室网络），确保只有当前的公网 IP 可以访问特定的华为云资源。

## 功能特性

*   **自动获取公网 IP**：通过多个在线服务获取当前网络的公网出口 IP。
*   **智能去重与校验**：多次获取 IP 并进行比对，确保 IP 准确性。
*   **华为云安全组同步**：
    *   **自动清理**：根据配置文件中的 `description` 字段，自动删除旧的、不再匹配当前 IP 的安全组规则。
    *   **自动添加**：将新的公网 IP 添加到指定的安全组规则中。
    *   **支持多种端口配置**：支持指定单个端口、多个端口（逗号分隔）或所有端口 (`ALL`)。
*   **钉钉通知**：当 IP 发生变化并更新安全组后，自动发送钉钉通知。

## 前置条件

1.  **华为云账号**：需要获取 API 访问密钥（Access Key ID 和 Secret Access Key）。
2.  **Go 环境**：用于编译源代码（推荐 Go 1.18+）。

# 编译项目

```bash
go mod tidy
go build -o modifyingSecurityGroupForHuaweicloud
```

# 配置文件 (config.toml)

在程序运行目录下创建 `config.toml` 文件，参照以下格式进行配置：

```toml
# 钉钉机器人 Webhook (可选)
[dingtalk]
webhook = "https://oapi.dingtalk.com/robot/send?access_token=YOUR_ACCESS_TOKEN"

# 华为云账号配置 (支持多账号)
[[creds]]
SecretID = "YOUR_HUAWEI_CLOUD_ACCESS_KEY_ID"      # 华为云 AK
SecretKey = "YOUR_HUAWEI_CLOUD_SECRET_ACCESS_KEY" # 华为云 SK
SecurityGroups = ["sg-xxxxxx", "sg-yyyyyy"]       # 该账号下要管理的安全组ID列表

# 安全组规则详细配置
[[securityGroups]]
id = "sg-xxxxxx"              # 安全组 ID
region = "ap-guangzhou"       # 区域代码 (如 cn-north-4, ap-guangzhou)
ports = "22,80,443"           # 端口列表 (逗号分隔) 或 "ALL"
protocol = "tcp"              # 协议 (tcp, udp, icmp 等)
action = "allow"              # 动作 (目前仅支持 allow 逻辑)
description = "Office_Auto_Update" # 关键字段：用于标识由本工具管理的规则。工具会删除包含此描述的旧规则。

[[securityGroups]]
id = "sg-yyyyyy"
region = "cn-north-4"
ports = "ALL"
protocol = "tcp"
action = "allow"
description = "Home_Auto_Update"
```

**注意：** `description` 字段非常重要！程序会根据这个字段来识别并删除旧的规则。请确保不要手动修改包含此描述的规则，以免被误删或导致更新失败。

# 运行程序

### 在 linux 上运行

#### 方式1，创建 cron 任务

复制 config.toml 和 modifyingSecurityGroup_linux 到 Linux 服务器上，在 config.toml 中配置适当的认证信息和安全组

```
crontab -e ，然后添加以下内容
# 每1小时执行一次，仅获取IP并写入文件（不更新安全组、不发钉钉）
* */1 * * * cd /root/modifyingSecurityGroupForHuaweicloud && ./modifyingSecurityGroupForHuaweicloud --minRequiredIPs 2 --maxRequiredIPs 5 --updateSG=false --notifyDingTalk=false >> /tmp/txmodSecurityGroup.log 2>&1
```

#### 手动指定出口 ip(特殊情况下使用)

* 1. 手动将待添加的出口 ip 写入到一个文本文件中，假设是 myips.txt

* 2. 执行以下命令

```
    ./modifyingSecurityGroupForHuaweicloud -ip myips.txt
```

#### 参数说明（获取 IP）

- --ip：指定包含 IP 地址的文件路径。如果提供此参数，程序将从文件中读取 IP 地址，而不是在线获取。
- --maxAttempts：最大尝试次数，用于在线获取 IP 地址时的并发请求数。默认值为 30。
- --minRequiredIPs：所需的唯一 IP 数量。程序将在获取到指定数量的唯一 IP 后停止。默认值为 2。
- --maxRequiredIPs：所需的唯一 IP 数量。程序将在获取到指定数量的唯一 IP 后停止。默认值为 5,此参数不应大于前面的 N 相等。

### 新增命令选项（根据对话修改后的主程序）
- --updateSG：是否执行华为云安全组更新。布尔，默认 true。
- --notifyDingTalk：是否发送钉钉通知（仅当有安全组更新时）。布尔，默认 true。
- --externalScript：要执行的外部脚本路径，支持 `.sh`（Linux/macOS）、`.py`（Python脚本）与 `.bat`/`.cmd`（Windows），也可为普通可执行文件。默认空。
- --externalScriptArgs：传给外部脚本的参数字符串，空格分隔。默认空。

#### 示例
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


### 方式2，创建 cron 任务（分成两段）
```
#更新华为云安全组
0 0,2,4,6,8 * * * /data/workspace/projects-code/modifyingSecurityGroupForHuaweicloud/modifyingSG.sh 
*/5 9-22 * * * /data/workspace/projects-code/modifyingSecurityGroupForHuaweicloud/modifyingSG.sh
```

### 在 Windows 上运行

#### 创建计划任务

以管理员权限运行 CMD，然后执行以下命令

- 创建非高峰时段任务（00:00-08:59，每 2 小时）

```cmd
schtasks /create /tn "modifyingSecurityGroup_OffPeak" /tr "\"D:\Program Files\modifyingSecurityGroup\modifyingSG.bat\"" /sc DAILY /st 00:00 /ri 120 /du 08:59 /ed 9999/12/31 /ru "SYSTEM" /rl HIGHEST /f
```

- 创建高峰时段任务（09:00-22:00，每 5 分钟）

```cmd
schtasks /create /tn "modifyingSecurityGroup_Peak" /tr "\"D:\Program Files\modifyingSecurityGroup\modifyingSG.bat\"" /sc DAILY /st 09:00 /ri 5 /du 13:00 /ed 9999/12/31 /ru "SYSTEM" /rl HIGHEST /f
```

#### 参数说明

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

#### 查看计划任务

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

#### 删除计划任务

```cmd
schtasks /delete /tn "modifyingSecurityGroup_OffPeak" /f
```

```cmd
schtasks /delete /tn "modifyingSecurityGroup_Peak" /f
```

## 注意事项

1.  **区域代码**：请确保 `config.toml` 中的 `region` 填写正确（例如 `cn-north-1`, `ap-southeast-1` 等），否则 API 调用会失败。
2.  **API 权限**：提供的 AK/SK 需要具有对应区域的 VPC 和安全组管理权限。
3.  **规则覆盖**：程序采用“先删后加”的逻辑。它会查找所有描述中包含配置文件里 `description` 的规则并删除，然后添加新 IP 的规则。请确保不同环境/用途的规则使用不同的 `description` 以免冲突。
