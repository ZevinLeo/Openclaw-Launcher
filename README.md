# ? Clawdbot (Windows) 完整部署与使用指南

## ? 第一部分：核心概念 (必读)

Clawdbot 的架构与普通软件不同，它分为“大脑”和“手脚”。你之前的 `Paired: 0` 问题正是因为只启动了大脑。

1. **Gateway (大脑/网关)**
* **职责**：负责思考（连接 AI 模型）、通讯（WhatsApp/Telegram）、存储记忆。
* **状态**：必须**始终运行**。如果它关了，你的机器人就离线了。


2. **Node (手脚/节点)**
* **职责**：负责执行（在 Windows 上运行 CMD 命令、控制浏览器、管理文件）。
* **状态**：必须**运行并连接到 Gateway**。如果它关了，机器人能聊天，但无法操作电脑。



---

## ? 第二部分：安装与初始化

### 1. 安装命令

在 PowerShell (管理员) 中运行官方脚本：

```powershell
iwr -useb https://clawd.bot/install.ps1 | iex

```

### 2. 验证安装位置

如果你想知道它装哪了，运行：

```powershell
Get-Command clawdbot

```

> **终端解读**：通常位于 `C:\Users\用户名\.clawdbot\bin`。如果显示的是 `npm` 路径，说明你电脑里有两个版本，建议卸载 npm 版以避免冲突。

---

## ? 第三部分：启动流程 (日常操作)

你需要打开 **两个** PowerShell 窗口。

### 窗口 A：启动大脑 (Gateway)

运行命令：

```powershell
clawdbot

```

**终端输出解读：**

```text
Listening on port 18789
Telegram: ok (@ZevinnW_bot)
WhatsApp: linked

```

* `Listening on port 18789`: 网关启动成功，正在等待连接。
* `WhatsApp: linked`: WhatsApp 已连接，随时可以接收消息。
* **注意**：此窗口**不能关闭**。

### 窗口 B：启动手脚 (Node)

运行命令（`127.0.0.1` 代表本机）：

```powershell
clawdbot node run --host 127.0.0.1 --port 18789 --display-name "MyWinPC"

```

**终端输出解读：**

```text
Attempting to connect to gateway...
Connected to gateway at ws://127.0.0.1:18789

```

* `Connected`: 成功连接！现在机器人拥有了操作这台电脑的权限。
* 如果显示 `Paired: 0` 或 `Pending`，请去窗口 A 运行 `clawdbot devices approve <ID>`。

---

## ? 第四部分：WhatsApp 配置 (关键)

针对你使用的“独立小号做机器人，主号做管理员”模式。

### 1. 设置白名单与权限

由于 PowerShell 对引号处理很特殊，**请原封不动复制**以下命令，防止报错 `expected string, received number`：

```powershell
# 1. 开启配对模式（防止陌生人骚扰）
clawdbot config set channels.whatsapp.dmPolicy pairing

# 2. 将你的主号加入白名单（替换 +86... 为你的真实号码）
# 注意单引号和双引号的嵌套结构
clawdbot config set channels.whatsapp.allowFrom '["+8613900000000"]'

```

### 2. 登录机器人账号

1. 确保 Gateway 正在运行。
2. 在终端输入：`clawdbot channels login`
3. **拿出机器人手机（小号）**，打开 WhatsApp -> 设置 -> 已连接设备 -> 扫码。

---

## ? 第五部分：浏览器控制 (Edge 插件)

让机器人能操作你的 Microsoft Edge。

### 1. 获取插件路径

在终端运行：

```powershell
clawdbot browser extension install

```

> **终端解读**：它会输出一个路径，例如 `C:\Users\ZevinW\.clawdbot\extension`。复制这个路径。

### 2. 安装到 Edge

1. 打开 Edge 浏览器，地址栏输入：`edge://extensions`
2. 打开左侧/右侧的开关：**开发人员模式 (Developer mode)**。
3. 点击按钮：**加载解压缩的扩展 (Load unpacked)**。
4. 选择第 1 步中生成的文件夹。
5. 点击工具栏上的 ? 图标，确保状态为 `Connected`。

---

## ? 第六部分：高级技巧 (沙盒与服务)

### 1. 临时沙盒环境 (不影响主环境)

如果你想测试新的配置，但不想破坏现有的：

```powershell
# 1. 创建临时目录
md D:\ClawdTest\data

# 2. 设置临时环境变量 (仅当前窗口有效)
$env:CLAWDBOT_DIR = "D:\ClawdTest\data"

# 3. 启动临时网关 (使用不同端口)
clawdbot --port 18790

```

*关闭此窗口后，一切自动还原。*

### 2. 开机自启 (使用 PM2)

为了不让桌面一直开着两个黑框框：

```powershell
# 1. 安装 PM2
npm install -g pm2 pm2-windows-startup
pm2-startup install

# 2. 启动并保存网关
pm2 start clawdbot --name gateway
pm2 save

# 3. 将 Node 安装为后台服务
clawdbot node install --host 127.0.0.1 --port 18789 --display-name "AutoNode"
clawdbot node start

```

---

## ? 第七部分：故障排除 (Troubleshooting)

| 现象 | 原因 | 解决方法 |
| --- | --- | --- |
| **`Paired: 0`** | 虽然设备已批准，但 Node 程序没运行。 | 打开新窗口运行 `clawdbot node run ...`。 |
| **`AbortError`** | 重启时的正常断连报错。 | 忽略即可，只要随后显示 Listening。 |
| **配置报错 `received number**` | 电话号码没加引号。 | 使用 `'["+86..."]'` 格式重新配置。 |
| **WhatsApp 不回复** | 号码未在白名单或格式错误。 | 确保使用 E.164 格式（+国家码）。 |
| **Web Search 失败** | 缺少 API Key。 | 申请 Brave Search API Key 并配置。 |

---

### ? 使用示例

现在一切就绪，拿起你的手机（主号），给机器人（小号）发消息：

* **测试连接**：`Hello`
* **测试系统操作**：`检查一下 C 盘剩余空间`
* **测试浏览器**：`帮我总结一下 Edge 浏览器当前标签页的内容`