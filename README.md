# 🦞 Clawdbot 终极实操手册：从零构建本地 AI 枢纽

> **版本 (Version):** v1.0
---

## 📘 核心目录导航

- [一、 简介](#intro)
- [二、 系统要求](#requirements)
- [三、 安装步骤](#install)
- [四、 💻 Clawdbot 控制台使用指南](#console-guide)
- [五、 配置 DeepSeek API 中转](#deepseek-config)
- [六、 验证和测试](#verify)
- [七、 常见踩坑点](#pitfalls)
- [八、 常见问题 FAQ](#faq)
- [九、 常用命令速查](#commands)

---

## <span id="intro">一、 简介</span>

Clawdbot 是一个开源的本地 AI 助手枢纽，它允许你将最顶尖的 AI 模型（如 DeepSeek-V3/R1）无缝接入 Telegram、Discord 等 12+ 消息平台，同时确保敏感数据在本地进行初步处理与存储。

**核心特点：**
- **数据主权**：完全开源，所有聊天记录与 Token 凭证均本地化。
- **全平台支持**：支持 Web 控制面板及多种主流即时通讯工具。
- **极速中转**：完美适配 DeepSeek API，享受极高性价比的智能体验。

---

## <span id="requirements">二、 系统要求</span>

### 必需条件

| 项目 | 规格要求 | 核心原因 |
| --- | --- | --- |
| **操作系统** | Windows / macOS / Linux | 涉及底层文件监控与网络网关映射 |
| **Node.js** | **22.0.0** 或更高版本 | 利用最新的异步特性实现高效数据流转发 |
| **包管理器** | pnpm (首选) / npm | 确保依赖项安装的一致性与安全性 |

---

## <span id="install">三、 安装步骤</span>

### 1. 升级 Node.js 版本

Clawdbot 对运行环境极其敏感，建议通过 **nvm** 确保版本达标：

```bash
# 安装并激活版本 22
nvm install 22
nvm use 22
nvm alias default 22

# 验证版本
node --version  # 应显示 v22.x.x

```

### 2. 选择安装方式

根据您的使用习惯选择其中一种路径：

* **方式一：npm 全局安装 (官方推荐)**

```bash
npm install -g clawdbot

```

* **方式二：一键 Shell 脚本**

```bash
curl -fsSL [https://clawd.bot/install.sh](https://clawd.bot/install.sh) | bash

```

### 3. 初始化配置 (Onboarding)

安装完成后运行配置向导：

```bash
clawdbot onboard

```

**配置向导流程：**

#### 步骤 1：安全确认

```text
◇  Security ───────────────────────────────────────────────────────╮
│  Clawdbot agents can run commands, read/write files, and act     │
│  through any tools you enable.                                   │
│  Please read: [https://docs.clawd.bot/security](https://docs.clawd.bot/security)                    │
├──────────────────────────────────────────────────────────────────╯

◇  I understand this is powerful and inherently risky. Continue?
│  Yes

```

#### 步骤 2：选择 AI 后端

由于 DeepSeek 的 API 完全兼容 OpenAI 格式，此处**直接选择 OpenAI** 即可。

```text
◇  Model/auth provider
│  OpenAI  ← 直接选择 OpenAI (DeepSeek 完美兼容 OpenAI 协议)

◆  OpenAI auth method
│  ● API key

```

#### 步骤 3：配置 DeepSeek API Key

**👉 获取 DeepSeek API Key 教程：**

1. 访问 DeepSeek 开放平台：[https://platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys)
2. 登录您的账户，点击右上角的 **"创建 API Key"**。
3. 复制生成的以 `sk-` 开头的密钥。

**回到终端输入凭证：**

```text
◇  Paste OpenAI API key
│  sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  ← 在此处粘贴您刚获取的 DeepSeek Key

◇  Base URL (optional)
│  [https://api.deepseek.com/v1](https://api.deepseek.com/v1)  ← 务必手动输入此地址 (不要漏掉 /v1)

```

> **提示：** 此时 onboard 向导会生成基础配置，稍后我们需要在第五章中手动优化模型参数。

#### 步骤 4：配置消息平台（可选）

```text
◇  Channel status ────────────────────────────╮
│  Telegram: not configured                    │
│  WhatsApp: not configured                    │
│  Discord: not configured                     │
│  ...共支持 12+ 平台                          │
├─────────────────────────────────────────────╯

◇  Select channel (QuickStart)
│  Telegram (Bot API)

```

**获取 Telegram Bot Token：**

1. 在 Telegram 中搜索 @BotFather
2. 发送 `/newbot`
3. 按提示输入 Bot 名称和用户名
4. 复制 Bot Token

#### 步骤 5：完成配置

```text
◇  Telegram: ok (@YourBotName) (1416ms)
   Agents: main (default)
   Heartbeat interval: 1h (main)

◇  Control UI ─────────────────────────────────────────────────────╮
│  Web UI: [http://127.0.0.1:18789/](http://127.0.0.1:18789/)                                 │
│  Web UI (with token): [http://127.0.0.1:18789/?token=your-token](http://127.0.0.1:18789/?token=your-token)   │
│  Gateway WS: ws://127.0.0.1:18789                                │
├──────────────────────────────────────────────────────────────────╯

└  Onboarding complete.

```

#### 步骤 6：配对验证（如使用 Telegram）

去 Telegram 给你的 Bot 发消息，会收到配对码：

```text
Clawdbot: access not configured.

Your Telegram user id: 1234567890
Pairing code: ABC12345

Ask the bot owner to approve with:
clawdbot pairing approve telegram <code>

```

在终端批准配对：

```bash
clawdbot pairing approve telegram ABC12345

```

---

## <span id="console-guide">四、 💻 Clawdbot 控制台使用指南</span>

### 核心操作区

* **🚀 一键启动 (One-Click Start)**：
* 自动在后台启动 Gateway 服务。
* 等待服务就绪后，自动启动 Node 并建立连接。
* 推荐日常使用此按钮。


* **🛑 全部停止 (Stop All)**：
* 强制结束所有关联进程 (clawdbot.exe, node.exe)，释放系统端口。


* **🔍 手动检测 (Manual Check)**：
* 如果您怀疑状态显示不准，点击此按钮强制刷新。



### 状态指示灯

* ⚪ **灰色 (Not Running)**：服务未启动。
* 🟢 **绿色 (Running/Connected)**：服务运行正常，连接成功。
* 🟡 **黄色 (Connecting...)**：服务启动中或正在配对。

### 设置与托盘

* **最小化到托盘**：勾选后，点击窗口右上角的关闭或最小化按钮，程序将隐藏到任务栏托盘区（右下角小图标），持续守护进程。
* **双击托盘图标**：重新显示主界面。

---

## <span id="deepseek-config">五、 配置 DeepSeek API 中转</span>

为了获得最佳体验，请手动编辑 `~/.clawdbot/clawdbot.json`，将 `models` 部分替换为以下高级模版：

### 1. 深度配置模版解析

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "openai": {
        "baseUrl": "[https://api.deepseek.com/v1](https://api.deepseek.com/v1)",
        "apiKey": "你的DEEPSEEK_API_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "deepseek-chat",
            "name": "DeepSeek Chat",
            "reasoning": false,
            "input": [
              "text"
            ],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": 64000,
            "maxTokens": 8192
          }
        ]
      }
    }
  }
}

```

### 2. 关键字段详细讲解

| 字段 | 含义说明 |
| --- | --- |
| **`mode`** | 设置为 `"merge"`，表示将此自定义配置与系统默认配置合并。 |
| **`api`** | 必须设为 `"openai-completions"`，确保 Clawdbot 使用 OpenAI 标准流式协议。 |
| **`id`** | 核心标识符，必须与 DeepSeek 官方模型 ID (`deepseek-chat`) 完全一致。 |
| **`reasoning`** | 是否开启推理模式。V3 设为 `false`，若配置 R1 则设为 `true`。 |
| **`cost`** | 计费定义。此处设为 `0` 代表仅在本地记录消耗，不影响实际 API 扣费。 |
| **`contextWindow`** | 上下文窗口大小。DeepSeek 支持较大上下文，此处建议设为 `64000`。 |
| **`maxTokens`** | 单次回复的最大长度上限。建议设为 `8192` 以获得完整回复。 |

### 3. 重启 Gateway 服务

每次修改配置文件后，必须通过控制台重启或执行：

```bash
clawdbot gateway restart

```

---

## <span id="verify">六、 验证和测试</span>

### 1. 检查 Gateway 状态

```bash
clawdbot channels status

```

**正常输出：**

```text
Gateway reachable.
- Telegram default: disabled, configured, stopped

```

### 2. 访问 Web UI

打开浏览器访问：
`http://127.0.0.1:18789/?token=你的token`

**Web UI 功能：**

* 💬 Chat: 直接与 AI 对话 (确认模型显示为 DeepSeek Chat)
* 📊 Overview: 查看系统状态
* 🔌 Channels: 管理消息通道
* ⚙️ Config: 修改配置

### 3. 发送测试消息

1. 输入消息：`你好，你是谁？`
2. 等待 AI 回复，确认其能识别自己为 DeepSeek 模型，状态显示 **"Health OK"**。

### 4. 查看日志

如果遇到问题，检查日志：

```bash
# Gateway 主日志
tail -f ~/.clawdbot/logs/gateway.log

# 详细调试日志
tail -f /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log

```

---

## <span id="pitfalls">七、 常见踩坑点</span>

* **❌ 踩坑 1：环境变量配置无效**
* **问题原因**：Clawdbot 不支持通过系统环境变量设置端点。
* **✅ 正确做法**：在 `~/.clawdbot/clawdbot.json` 配置文件中修改。


* **❌ 踩坑 2：JSON 语法错误**
* **错误原因**：手动编辑时漏掉括号或引号。
* **✅ 正确做法**：请确保 `models` 字段内部的对象嵌套闭合，使用 `jq` 验证。


* **❌ 踩坑 3：BaseURL 错误**
* **错误原因**：DeepSeek 的地址漏掉后缀。
* **✅ 正确做法**：地址必须带 `/v1`，即 `https://api.deepseek.com/v1`。


* **❌ 踩坑 4：Node.js 版本过低**
* **✅ 解决方案**：使用 nvm 安装 22+ 版本。



---

## <span id="faq">八、 常见问题 FAQ</span>

* **Q: 点击“一键启动”后，状态灯一直不绿？**
* **A**: 请检查是否已安装 Node.js 22+ 和 clawdbot 核心。您可以尝试打开 CMD 手动输入 `clawdbot gateway` 看看是否有报错信息。


* **Q: 提示模型未找到？**
* **A**: 请检查 `clawdbot.json` 中模型 `id` 是否正确填写为 `deepseek-chat`。


* **Q: 启动时提示 "Port 18789 is already in use"？**
* **A**: 点击 **“🛑 全部停止”** 按钮即可释放端口。


* **Q: Gateway 无法连接？**
* **A**: 1. 检查端口占用；2. 验证配置文件 JSON 格式；3. 查看错误日志：`tail -f ~/.clawdbot/logs/gateway.err.log`。



---

## <span id="commands">九、 常用命令速查</span>

```bash
# 重启网关服务
clawdbot gateway restart

# 环境深度检查
clawdbot doctor

# 查看实时详细日志
tail -f /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log

# 获取 Web UI 链接
clawdbot dashboard --no-open

```

```

```
