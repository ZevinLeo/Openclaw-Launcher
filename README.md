# 🦞 Clawdbot 终极实操手册：从零构建本地 AI 枢纽

> **版本 (Version):** v1.1 
> **最后更新:** 2026-01-29

---

## 📘 核心目录导航

* [一、 简介](#intro)
* [二、 系统要求](#requirements)
* [三、 安装与向导配置 (核心交互流程)](#install)
* [四、 必做：填入 API Key (含 Qwen 避坑指南)](#apikey-config)
* [五、 🛠️ 常用命令速查手册](#commands)
* [六、 ✅ 验证与成功案例展示](#verify)
* [七、 📂 文件结构与安全建议](#structure)
* [八、 ❓ 常见问题 FAQ](#faq)

---

## <span id="intro">一、 简介</span>

Clawdbot 是一个开源的本地 AI 助手枢纽，它允许你将最顶尖的 AI 模型（如 DeepSeek-V3/R1、Qwen-Turbo）无缝接入 WhatsApp、Telegram 等平台，同时确保数据隐私。

---

## <span id="requirements">二、 系统要求</span>

* **Node.js**: **22.0.0** 或更高版本 (强烈推荐使用 `nvm` 管理)
* **操作系统**: Windows / macOS / Linux

---

## <span id="install">三、 安装与向导配置 (核心交互流程)</span>

### 1. 安装工具
```bash
npm install -g clawdbot

```

### 2. 启动配置向导

```bash
clawdbot onboard

```

### 3. 向导交互实录 (请严格按以下步骤操作)

#### 3.1 启动模式与安全确认

```text
◇  Security ... I understand this is powerful and inherently risky. Continue?
│  Yes

◇  Onboarding mode
│  QuickStart  ← 选择此项

```

#### 3.2 配置 AI 模型 (手动指定)

这里我们跳过内置提供商，直接手动指定模型名称。

```text
◇  Model/auth provider
│  Skip for now  ← 必选此项！(后续手动填 Key)

◇  Filter models by provider
│  All providers

◇  Default model
│  Enter model manually  ← 选择手动填写

◇  Default model
│  deepseek/deepseek-chat

```

> **📝 输入提示 (非常重要)：**
> * **DeepSeek V3**: 输入 `deepseek/deepseek-chat`
> * **DeepSeek R1**: 输入 `deepseek/deepseek-reasoner`
> * **阿里云 Qwen**: 建议输入 `qwencn/qwen-vl-plus` (不要用 qwen 开头，原因见第四章)
> 
> 

#### 3.3 配置聊天渠道 (二选一)

##### 🟢 选项 A：配置 WhatsApp

```text
◇  Select channel (QuickStart)
│  WhatsApp (QR link)

◇  WhatsApp phone setup
│  Separate phone just for Clawdbot

◆  WhatsApp DM policy
│  Pairing (recommended)

◆  WhatsApp allowFrom
│  Set allowFrom to specific numbers

◆  Allowed sender numbers
│  +8618888888888  ← 输入你的手机号(带国家码)

```

##### 🔵 选项 B：配置 Telegram

**准备工作：**

1. 在 Telegram 搜索 **@BotFather**，发送 `/newbot` 获取 **Bot Token**。
2. 搜索 **@userinfobot**，获取你的 **User ID** (纯数字)。

**向导操作：**

```text
◇  Select channel (QuickStart)
│  Telegram (Bot API)

◇  Paste Telegram bot token
│  123456:ABC-DEF1234ghIkl...  ← 粘贴 Token

◇  Telegram whitelist (optional)
│  123456789  ← 填入 User ID

```

#### 3.4 配置技能 (Skills)

暂时跳过，后续可按需添加。

```text
◇  Skills status ────────────╮
│                            │
│  Eligible: 5               │
│  Missing requirements: 44  │
│  Blocked by allowlist: 0   │
│                            │
├────────────────────────────╯
│
◆  Configure skills now? (recommended)
│  ○ Yes / ● No   ← 选择 No 跳过

```

#### 3.5 配置钩子 (Hooks) - 开启记忆

开启 Session Memory 以便机器人能记住对话上下文。

```text
◇  Hooks ──────────────────────────────────────────────────────────╮
│  Hooks let you automate actions when agent commands are issued.  │
│  Example: Save session context to memory when you issue /new.    │
├──────────────────────────────────────────────────────────────────╯
│
◆  Enable hooks?
│  ◻ Skip for now
│  ◻ 🚀 boot-md
│  ◻ 📝 command-logger
│  ◼ 💾 session-memory  ← 按空格键勾选此项 (变成实心方块)

```

#### 3.6 启动网关服务 (Gateway)

这一步会启动后台服务，请留意弹出的新窗口日志。

```text
◇  Gateway service runtime ────────────────────────────────────────────╮
│  QuickStart uses Node for the Gateway service (stable + supported).  │
├──────────────────────────────────────────────────────────────────────╯
│
◆  Gateway service already installed
│  ● Restart  ← 选择重启服务
│  ○ Reinstall
│  ○ Skip

```

**(此时会弹出新的命令行窗口，显示如下日志即代表启动成功)**

```text
06:41:41 [gateway] agent model: deepseek/deepseek-chat
06:41:41 [gateway] listening on ws://127.0.0.1:18789
06:41:41 [hooks] loaded 3 internal hook handlers
06:41:41 [whatsapp] [default] starting provider (+86153***********)
06:41:44 [whatsapp] Listening for personal WhatsApp inbound messages.
Ctrl+C to stop.

```

#### 3.7 完成并打开界面

最后一步，进入 Web UI 确认状态。

```text
◆  How do you want to hatch your bot?
│  ○ Hatch in TUI (recommended)
│  ● Open the Web UI  ← 选择此项打开网页版
│  ○ Do this later

```

---

## <span id="apikey-config">四、 必做：填入 API Key</span>

**注意：** 步骤 3.2 选择了 `Skip for now`，现在必须手动配置 Key。

### ⚠️ 阿里云 Qwen (通义千问) 用户特别警告

> 如果使用**国内版** API Key，配置文件中的 provider 名字**绝对不能叫 `qwen**`！
> * **原因**：Clawdbot 会将 `qwen` 强制重定向到国际版接口，导致 `401 Unauthorized`。
> * **解决**：请自定义名字为 **`qwencn`** 或 `qwenchina`等。
> 
> 

### 操作步骤

1. **打开配置文件**：
* Windows: `C:\Users\你的用户名\.clawdbot\clawdbot.json`
* Mac/Linux: `~/.clawdbot/clawdbot.json`


2. **修改 `models` 部分** (二选一复制)：

#### 🅰️ 方案 A：使用 DeepSeek (推荐)

> 🔗 **[点击这里获取 DeepSeek API Key](https://platform.deepseek.com/api_keys)**

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "deepseek": {
        "baseUrl": "[https://api.deepseek.com/v1](https://api.deepseek.com/v1)",
        "apiKey": "sk-你的DeepSeekKey",
        "api": "openai-completions",
        "models": [] 
      }
    }
  }
}

```

#### 🅱️ 方案 B：使用阿里云 Qwen (国内版)

> 🔗 **[点击这里获取阿里云百炼 API Key](https://dashscope.console.aliyun.com/apiKey)**
> *(注意：名字必须叫 qwencn，不要改回 qwen)*

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "qwencn": {
        "baseUrl": "[https://dashscope.aliyuncs.com/compatible-mode/v1](https://dashscope.aliyuncs.com/compatible-mode/v1)",
        "apiKey": "sk-你的阿里云Key",
        "api": "openai-completions",
        "models": [
           {
             "id": "qwen-vl-plus",
             "name": "Qwen VL",
             "input": ["text", "image"]
           }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "qwencn/qwen-plus" },
      "imageModel": { "primary": "qwencn/qwen-vl-plus" }
    }
  }
}

```

3. **重启服务生效**：
```bash
clawdbot gateway restart

```



---

## <span id="commands">五、 🛠️ 常用命令速查手册</span>

### 5.1 Gateway 管理

* `clawdbot channels status` : 查看状态
* `clawdbot gateway restart` : 重启服务 (改配置后必做)
* `clawdbot channels status --deep` : 深度连接检查

### 5.2 诊断与日志

* `tail -f ~/.clawdbot/logs/gateway.log` : 查看主日志
* `tail -f /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log` : 查看详细 API 日志
* `clawdbot doctor --fix` : 自动修复问题

### 5.3 界面与更新

* `clawdbot dashboard` : 打开 Web UI
* `clawdbot tui` : 打开终端聊天界面
* `npm install -g clawdbot@latest` : 更新版本

---

## <span id="verify">六、 ✅ 验证与成功案例展示</span>

> **准备工作：** 请在本文档同级目录下新建 `images` 文件夹，并将你的 WebUI 截图命名为 `webui-success.jpg`，WhatsApp 截图命名为 `whatsapp-success.jpg` 放入其中。

### 1. 访问 Web UI 确认运行

打开浏览器访问 `http://127.0.0.1:18789`。
如果看到如下界面，说明 Clawdbot 网关已成功启动，DeepSeek 和 Qwen 模型加载正常。

<div align="center">
<img src="./images/webui-success.png" width="800" alt="Clawdbot Web UI 成功运行界面" style="border-radius: 10px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);">
<p><em>▲ Clawdbot Web UI 控制台：显示 DeepSeek V3 与 Qwen3-VL-Plus 配置就绪</em></p>
</div>

### 2. WhatsApp 真机测试

拿起手机，向配置好的 WhatsApp 机器人发送消息：`介绍你使用的所有大模型`。
如下图所示，机器人能够精准调用 DeepSeek 进行文本回复，并列出当前的配置详情。

<div align="center">
<img src="./images/whatsapp-success.png" width="375" alt="WhatsApp 真机对话截图" style="border-radius: 15px; border: 2px solid #e0e0e0;">
<p><em>▲ WhatsApp 实测：成功调用 DeepSeek V3 进行流畅对话</em></p>
</div>

---

## <span id="structure">七、 📂 文件结构与安全建议</span>

### 7.1 配置文件位置

```text
~/.clawdbot/
├── clawdbot.json              # [核心] 主配置文件
├── credentials/               # API 凭证存储
├── sessions/                  # 全局会话数据
└── logs/                      # 日志文件夹

```

### 7.2 安全最佳实践

* **API Key**: 推荐使用 `clawdbot.json` 本地配置，禁止提交到 Git。
* **访问控制**: Gateway 默认只监听 `localhost`。如需远程控制，请使用 **Tailscale** 连回本地，严禁直接暴露端口到公网。

---

## <span id="faq">八、 ❓ 常见问题 FAQ</span>

* **Q: 为什么 Qwen 报错 401？**
* A: 检查配置文件中 provider 名字是否写成了 `qwen`。如果是，请改为 `qwencn`。


* **Q: Telegram 机器人没反应？**
* A: 确认配置文件或向导中填写的 User ID 正确。


* **Q: WhatsApp 怎么配对？**
* A: 启动后用白名单手机号发消息，如提示配对，在命令行输入 `clawdbot pairing approve whatsapp <配对码>`。



```
