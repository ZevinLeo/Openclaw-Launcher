import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

// ==========================================
// 1. 程序入口
// ==========================================

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
        ChangeNotifierProvider(create: (_) => FileProvider()),
      ],
      child: const OpenClawApp(),
    ),
  );
}

class OpenClawApp extends StatelessWidget {
  const OpenClawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenClaw Dashboard (Flutter)',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        fontFamily: Platform.isWindows ? 'Microsoft YaHei UI' : null, // 适配 Windows 字体
      ),
      home: const DashboardScreen(),
    );
  }
}

// ==========================================
// 2. 数据模型 (Data Models)
// ==========================================

class AppConfig {
  Map<String, dynamic> _data = {};

  AppConfig(this._data);

  factory AppConfig.defaultConfig() {
    return AppConfig({
      "agents": {
        "defaults": {
          "workspace": "~/.openclaw/workspace",
          "model": {"primary": ""},
          "imageModel": {"primary": ""},
          "thinkingDefault": "off",
          "sandbox": {"mode": "non-main"}
        },
        "list": [
          {"id": "main", "name": "Default"}
        ]
      },
      "messages": {
        "tts": {"auto": "off", "provider": "elevenlabs"}
      },
      "channels": {
        "telegram": {"enabled": true, "botToken": "", "allowFrom": []},
        "discord": {"enabled": false, "token": "", "allowFrom": []}
      },
      "skills": {"entries": {}},
      "gateway": {"port": 18789},
      "tools": {"deny": []}
    });
  }

  dynamic get(String path) {
    List<String> keys = path.split('.');
    dynamic current = _data;
    for (var key in keys) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  void set(String path, dynamic value) {
    List<String> keys = path.split('.');
    dynamic current = _data;
    for (int i = 0; i < keys.length - 1; i++) {
      var key = keys[i];
      if (current is Map) {
        if (!current.containsKey(key)) current[key] = <String, dynamic>{};
        current = current[key];
      }
    }
    if (current is Map) {
      current[keys.last] = value;
    }
  }

  String toJson() => const JsonEncoder.withIndent('  ').convert(_data);
}

// ==========================================
// 3. 状态管理 (Providers)
// ==========================================

class ConfigProvider extends ChangeNotifier {
  AppConfig config = AppConfig.defaultConfig();
  String _statusMessage = "正在初始化...";
  late File _configFile;

  String get statusMessage => _statusMessage;

  ConfigProvider() {
    _init();
  }

  String get _homePath {
    Map<String, String> envVars = Platform.environment;
    if (Platform.isMacOS || Platform.isLinux) return envVars['HOME']!;
    if (Platform.isWindows) return envVars['UserProfile']!;
    return '.';
  }

  Future<void> _init() async {
    final dir = Directory(p.join(_homePath, '.openclaw'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _configFile = File(p.join(dir.path, 'openclaw.json'));
    await loadConfig();
  }

  Future<void> loadConfig() async {
    try {
      if (await _configFile.exists()) {
        final content = await _configFile.readAsString();
        config = AppConfig(jsonDecode(content));
        _statusMessage = "配置已加载";
      } else {
        _statusMessage = "未找到配置文件，使用默认值";
      }
    } catch (e) {
      _statusMessage = "加载错误: $e";
    }
    notifyListeners();
  }

  Future<void> saveConfig() async {
    try {
      await _configFile.writeAsString(config.toJson());
      _statusMessage = "配置已保存";
    } catch (e) {
      _statusMessage = "保存错误: $e";
    }
    notifyListeners();
  }

  void updateField(String path, dynamic value) {
    config.set(path, value);
    notifyListeners();
  }
}

class FileProvider extends ChangeNotifier {
  List<FileSystemEntity> files = [];
  File? selectedFile;
  String? fileContent;
  String _status = "";

  String get status => _status;

  Future<void> scanWorkspace(String workspacePath) async {
    String realPath = workspacePath;
    if (realPath.startsWith('~')) {
      final home = Platform.isWindows ? Platform.environment['UserProfile'] : Platform.environment['HOME'];
      realPath = realPath.replaceFirst('~', home!);
    }
    
    final dir = Directory(realPath);
    if (!await dir.exists()) {
      _status = "工作区不存在: $realPath";
      files = [];
      notifyListeners();
      return;
    }

    final targetFiles = ["AGENTS.md", "SOUL.md", "USER.md", "IDENTITY.md", "TOOLS.md"];
    try {
      List<FileSystemEntity> all = await dir.list().toList();
      files = all.where((f) {
        final name = p.basename(f.path);
        return targetFiles.contains(name);
      }).toList();
      _status = "文件列表已刷新";
    } catch (e) {
      _status = "扫描失败: $e";
    }
    notifyListeners();
  }

  Future<void> selectFile(File file) async {
    selectedFile = file;
    try {
      fileContent = await file.readAsString();
      _status = "已读取: ${p.basename(file.path)}";
    } catch (e) {
      fileContent = "Error reading file";
      _status = "读取失败: $e";
    }
    notifyListeners();
  }

  Future<void> saveContent(String newContent) async {
    if (selectedFile == null) return;
    try {
      await selectedFile!.writeAsString(newContent);
      fileContent = newContent;
      _status = "文件已保存";
    } catch (e) {
      _status = "保存失败: $e";
    }
    notifyListeners();
  }
}

// ==========================================
// 4. UI 界面
// ==========================================

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("🛠️ OpenClaw 控制中心"),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.psychology), text: "核心记忆 (Soul)"),
              Tab(icon: Icon(Icons.memory), text: "模型配置"),
              Tab(icon: Icon(Icons.cable), text: "渠道连接"),
              Tab(icon: Icon(Icons.bolt), text: "技能管理"),
              Tab(icon: Icon(Icons.security), text: "安全与网关"),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: FilledButton.icon(
                onPressed: () => cfg.saveConfig(),
                icon: const Icon(Icons.save),
                label: const Text("保存配置"),
              ),
            )
          ],
        ),
        body: Column(
          children: [
            const Expanded(
              child: TabBarView(
                children: [
                  SoulTab(),
                  ModelsTab(),
                  ChannelsTab(),
                  SkillsTab(),
                  SecurityTab(),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: Colors.grey.shade200,
              child: Text(cfg.statusMessage, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            )
          ],
        ),
      ),
    );
  }
}

// --- Tab 1: Soul (文件编辑器) ---
class SoulTab extends StatefulWidget {
  const SoulTab({super.key});
  @override
  State<SoulTab> createState() => _SoulTabState();
}

class _SoulTabState extends State<SoulTab> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 使用 addPostFrameCallback 并检查 mounted，修复 Context Warning
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cfg = context.read<ConfigProvider>();
      final ws = cfg.config.get('agents.defaults.workspace') ?? "~/.openclaw/workspace";
      context.read<FileProvider>().scanWorkspace(ws);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fileProvider = context.watch<FileProvider>();

    if (fileProvider.fileContent != null && _controller.text != fileProvider.fileContent) {
      if (fileProvider.selectedFile?.path != _currentFilePath) {
         _controller.text = fileProvider.fileContent!;
         _currentFilePath = fileProvider.selectedFile?.path;
      }
    }

    return Row(
      children: [
        Container(
          width: 250,
          color: Colors.grey.shade50,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text("📂 工作区文件", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: fileProvider.files.length,
                  itemBuilder: (context, index) {
                    final file = fileProvider.files[index] as File;
                    final name = p.basename(file.path);
                    final isSelected = file.path == fileProvider.selectedFile?.path;
                    
                    return ListTile(
                      title: Text(name),
                      leading: const Icon(Icons.description, size: 20),
                      selected: isSelected,
                      selectedTileColor: Colors.blue.shade50,
                      onTap: () {
                        context.read<FileProvider>().selectFile(file);
                        _currentFilePath = null; 
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: OutlinedButton(
                   onPressed: () {
                     final cfg = context.read<ConfigProvider>();
                     final ws = cfg.config.get('agents.defaults.workspace');
                     context.read<FileProvider>().scanWorkspace(ws);
                   }, 
                   child: const Text("刷新列表")
                ),
              )
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.white,
                child: Row(
                  children: [
                    Text(fileProvider.selectedFile != null 
                      ? "正在编辑: ${p.basename(fileProvider.selectedFile!.path)}" 
                      : "未选择文件"),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: fileProvider.selectedFile == null ? null : () {
                        context.read<FileProvider>().saveContent(_controller.text);
                      },
                      child: const Text("保存文件内容"),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 14),
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  String? _currentFilePath;
}

// --- Tab 2: Models ---
class ModelsTab extends StatelessWidget {
  const ModelsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: "🧠 核心模型"),
        _ConfigTextField(
          label: "主模型 (Primary)",
          value: cfg.config.get("agents.defaults.model.primary") ?? "",
          onChanged: (v) => cfg.updateField("agents.defaults.model.primary", v),
        ),
        _ConfigTextField(
          label: "视觉模型 (Image)",
          value: cfg.config.get("agents.defaults.imageModel.primary") ?? "",
          onChanged: (v) => cfg.updateField("agents.defaults.imageModel.primary", v),
        ),
        _ConfigDropdown(
          label: "思考等级 (Thinking)",
          value: cfg.config.get("agents.defaults.thinkingDefault") ?? "off",
          options: const ["off", "low", "high"],
          onChanged: (v) => cfg.updateField("agents.defaults.thinkingDefault", v),
        ),
        const SizedBox(height: 32),
        _SectionHeader(title: "🗣️ TTS 语音合成"),
        _ConfigDropdown(
          label: "自动朗读 (Auto Mode)",
          value: cfg.config.get("messages.tts.auto") ?? "off",
          options: const ["off", "always", "inbound"],
          onChanged: (v) => cfg.updateField("messages.tts.auto", v),
        ),
         _ConfigDropdown(
          label: "提供商 (Provider)",
          value: cfg.config.get("messages.tts.provider") ?? "elevenlabs",
          options: const ["elevenlabs", "openai"],
          onChanged: (v) => cfg.updateField("messages.tts.provider", v),
        ),
      ],
    );
  }
}

// --- Tab 3: Channels ---
class ChannelsTab extends StatefulWidget {
  const ChannelsTab({super.key});
  @override
  State<ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends State<ChannelsTab> {
  String _selectedChannel = "telegram";

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    
    final basePath = "channels.$_selectedChannel";
    final enabled = cfg.config.get("$basePath.enabled") ?? false;
    final tokenKey = _selectedChannel == "discord" ? "token" : "botToken";
    final token = cfg.config.get("$basePath.$tokenKey") ?? "";
    final allowList = (cfg.config.get("$basePath.allowFrom") as List?)?.join(", ") ?? "";

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: "🔌 渠道配置"),
          // 修复：使用 InputDecorator + DropdownButton 替代 DropdownButtonFormField
          InputDecorator(
            decoration: const InputDecoration(
              labelText: "选择渠道",
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedChannel,
                items: const [
                  DropdownMenuItem(value: "telegram", child: Text("Telegram")),
                  DropdownMenuItem(value: "discord", child: Text("Discord")),
                ],
                onChanged: (v) => setState(() => _selectedChannel = v!),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text("启用 $_selectedChannel"),
                    value: enabled,
                    onChanged: (v) => cfg.updateField("$basePath.enabled", v),
                  ),
                  _ConfigTextField(
                    label: "Token / Key",
                    value: token,
                    isSecret: true,
                    onChanged: (v) => cfg.updateField("$basePath.$tokenKey", v),
                  ),
                  _ConfigTextField(
                    label: "AllowList (逗号分隔)",
                    value: allowList,
                    onChanged: (v) {
                      final list = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                      cfg.updateField("$basePath.allowFrom", list);
                    },
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

// --- Tab 4: Skills ---
class SkillsTab extends StatelessWidget {
  const SkillsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final entries = cfg.config.get("skills.entries") as Map? ?? {};

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: "⚡ 技能管理"),
        if (entries.isEmpty) 
          const Center(child: Text("暂无技能配置，请检查 config.json")),
        
        ...entries.entries.map((e) {
          final name = e.key;
          final details = e.value as Map;
          final enabled = details['enabled'] ?? true;
          
          return Card(
            child: ListTile(
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(details['apiKey'] != null ? "需要 API Key" : "无特殊配置"),
              trailing: Switch(
                value: enabled,
                onChanged: (v) {},
              ),
            ),
          );
        }),
      ],
    );
  }
}

// --- Tab 5: Security ---
class SecurityTab extends StatelessWidget {
  const SecurityTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final port = cfg.config.get("gateway.port") ?? 18789;
    final mode = cfg.config.get("agents.defaults.sandbox.mode") ?? "non-main";

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionHeader(title: "🔒 安全设置"),
        _ConfigDropdown(
          label: "沙盒模式 (Sandbox Mode)",
          value: mode,
          options: const ["off", "non-main", "all"],
          onChanged: (v) => cfg.updateField("agents.defaults.sandbox.mode", v),
        ),
        const SizedBox(height: 32),
        _SectionHeader(title: "⚙️ 网关设置"),
        _ConfigTextField(
          label: "端口 (Port)",
          value: port.toString(),
          onChanged: (v) => cfg.updateField("gateway.port", int.tryParse(v) ?? 18789),
        ),
      ],
    );
  }
}

// ==========================================
// 5. 通用 UI 组件
// ==========================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _ConfigTextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool isSecret;

  const _ConfigTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.isSecret = false,
  });

  @override
  State<_ConfigTextField> createState() => _ConfigTextFieldState();
}

class _ConfigTextFieldState extends State<_ConfigTextField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _ConfigTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _ctrl.text) {
      // 避免光标跳动逻辑...
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _ctrl,
        obscureText: widget.isSecret,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _ConfigDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _ConfigDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 修复：使用 InputDecorator + DropdownButton 替代 DropdownButtonFormField
    // 以解决新版 Flutter 的 value 过时警告
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: options.contains(value) ? value : null,
            items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: onChanged,
            isDense: true,
            isExpanded: true,
          ),
        ),
      ),
    );
  }
}