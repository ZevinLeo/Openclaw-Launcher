import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==========================================
// 1. 程序入口 & 初始化
// ==========================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(prefs)),
        ChangeNotifierProvider(create: (_) => LauncherProvider()),
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
        ChangeNotifierProvider(create: (_) => FileProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
      ],
      child: const OpenClawApp(),
    ),
  );
}

class OpenClawApp extends StatelessWidget {
  const OpenClawApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    
    return MaterialApp(
      title: 'OpenClaw Manager',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF3F3F3),
        cardColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE54D2E), brightness: Brightness.light),
        fontFamily: Platform.isWindows ? 'Microsoft YaHei UI' : null,
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        cardColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE54D2E),
          surface: Color(0xFF1E1E1E),
          surfaceContainerHighest: Color(0xFF2C2C2C),
          outline: Color(0xFF333333),
        ),
        fontFamily: Platform.isWindows ? 'Microsoft YaHei UI' : null,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF252525),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      home: const MainLayout(),
    );
  }
}

// ==========================================
// 2. 核心逻辑 Provider
// ==========================================

class LogEntry {
  final String message;
  final String type; 
  final String time;
  LogEntry(this.message, this.type) : time = _formatTime();
  static String _formatTime() {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}";
  }
}

class LauncherProvider extends ChangeNotifier {
  String? cliCmd;
  String versionNumber = "检测中...";
  Process? _procGateway;
  Process? _procNode;
  
  bool isGatewayRunning = false;
  bool isNodeConnected = false;
  
  String currentPort = "18789";
  String currentPid = "--";
  
  List<LogEntry> logs = [];
  final ScrollController logScrollCtrl = ScrollController();

  LauncherProvider() {
    _initDetection();
  }

  void addLog(String msg, {String type = "INFO"}) {
    logs.add(LogEntry(msg, type));
    notifyListeners();
    if (logScrollCtrl.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (logScrollCtrl.hasClients) {
          logScrollCtrl.animateTo(logScrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    }
  }

  Future<void> _initDetection() async {
    addLog("初始化环境检测...", type: "CMD");
    if (await _checkVersion("openclaw")) {
      cliCmd = "openclaw";
      addLog("核心已就绪: openclaw ($versionNumber)", type: "SUCCESS");
    } else if (await _checkVersion("openclaw-cn")) {
      cliCmd = "openclaw-cn";
      addLog("核心已就绪: openclaw-cn ($versionNumber)", type: "SUCCESS");
    } else {
      versionNumber = "未安装";
      addLog("未检测到核心程序，请前往设置页进行安装。", type: "ERROR");
    }
    notifyListeners();
  }

  Future<bool> _checkVersion(String cmd) async {
    try {
      final result = await Process.run(cmd, ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        final regex = RegExp(r"v?(\d+\.\d+\.\d+)");
        final match = regex.firstMatch(output);
        versionNumber = match?.group(1) ?? output;
        return true;
      }
    } catch (e) { /* ignore */ }
    return false;
  }

  Future<void> startServices() async {
    if (cliCmd == null) {
      addLog("错误: 未找到核心程序，无法启动。", type: "ERROR");
      return;
    }
    if (isGatewayRunning) return;

    addLog(">>> 正在启动 Gateway 服务...", type: "CMD");
    
    try {
      _procGateway = await Process.start(cliCmd!, ['gateway'], runInShell: true);
      currentPid = _procGateway!.pid.toString();
      _monitorStream(_procGateway!.stdout, "Gateway");
      _monitorStream(_procGateway!.stderr, "Gateway Error", isError: true);
      
      bool ready = await _waitForGatewayHttp();
      if (!ready) {
        addLog("Gateway 启动超时，端口 18789 可能被占用。", type: "ERROR");
        stopAll();
        return;
      }

      isGatewayRunning = true;
      notifyListeners();
      addLog("Gateway 启动成功 (HTTP 200 OK)", type: "SUCCESS");
      await _startNode();
    } catch (e) {
      addLog("启动异常: $e", type: "ERROR");
    }
  }

  Future<void> _startNode() async {
    addLog(">>> 正在启动 Node 进程...", type: "CMD");
    try {
      _procNode = await Process.start(
        cliCmd!, 
        ['node', 'run', '--host', '127.0.0.1', '--port', '18789', '--display-name', 'FlutterPC'],
        runInShell: true
      );
      _monitorStream(_procNode!.stdout, "Node");
      _monitorStream(_procNode!.stderr, "Node Error", isError: true);

      await Future.delayed(const Duration(seconds: 2));
      isNodeConnected = true; 
      notifyListeners();
      addLog("Node 已连接至本地集群。", type: "SUCCESS");
    } catch (e) {
      addLog("Node 启动失败: $e", type: "ERROR");
    }
  }

  Future<void> stopAll() async {
    addLog(">>> 正在停止所有服务...", type: "CMD");
    _procGateway?.kill();
    _procNode?.kill();
    
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/F', '/IM', 'node.exe'], runInShell: true);
    }
    
    isGatewayRunning = false;
    isNodeConnected = false;
    currentPid = "--";
    _procGateway = null;
    _procNode = null;
    notifyListeners();
    addLog("服务已全部停止。", type: "INFO");
  }

  Future<void> openWebUI() async {
    if (!isGatewayRunning) {
      addLog("请先启动服务。", type: "ERROR");
      return;
    }
    addLog("正在唤起 Web Dashboard...", type: "INFO");
    try {
      await Process.run(cliCmd!, ['dashboard'], runInShell: true);
    } catch (e) {
      addLog("无法打开浏览器: $e", type: "ERROR");
    }
  }

  void _monitorStream(Stream<List<int>> stream, String prefix, {bool isError = false}) {
    stream.transform(utf8.decoder).listen((data) {
      if (data.trim().isEmpty) return;
      for (var line in data.split('\n')) {
        if (line.trim().isNotEmpty) {
          addLog(line.trim(), type: isError ? "ERROR" : "INFO");
        }
      }
    });
  }

  Future<bool> _waitForGatewayHttp() async {
    for (int i = 0; i < 15; i++) { 
      try {
        final response = await http.get(Uri.parse('http://127.0.0.1:18789/'));
        if (response.statusCode == 200 || response.statusCode == 404) {
          return true;
        }
      } catch (e) { /* ignore */ }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<void> runInstaller(String method) async {
    addLog("正在启动安装程序 ($method)...", type: "CMD");
    String cmd = "npm";
    List<String> args = ["install", "-g", "openclaw-cn"];
    
    if (method == "powershell") {
      cmd = "powershell";
      args = ["-Command", "start cmd -ArgumentList '/k iwr -useb https://clawd.org.cn/install.ps1 | iex'"];
    }

    try {
      await Process.run(cmd, args, runInShell: true);
      await Future.delayed(const Duration(seconds: 5));
      _initDetection();
    } catch (e) {
      addLog("安装失败: $e", type: "ERROR");
    }
  }
}

// ==========================================
// 3. 辅助 Providers
// ==========================================

class ThemeProvider extends ChangeNotifier {
  final SharedPreferences prefs;
  ThemeMode _themeMode;
  ThemeProvider(this.prefs) : _themeMode = ThemeMode.values[prefs.getInt('theme_mode') ?? 0];
  ThemeMode get themeMode => _themeMode;
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    prefs.setInt('theme_mode', mode.index);
    notifyListeners();
  }
}

class NavigationProvider extends ChangeNotifier {
  int _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  void setIndex(int index) { _selectedIndex = index; notifyListeners(); }
}

class AppConfig {
  Map<String, dynamic> _data = {};
  AppConfig(this._data);
  factory AppConfig.defaultConfig() => AppConfig({
    "agents": {"defaults": {"workspace": "~/.openclaw/workspace", "model": {"primary": ""}, "imageModel": {"primary": ""}, "thinkingDefault": "off", "sandbox": {"mode": "non-main"}}, "list": [{"id": "main", "name": "Default"}]},
    "messages": {"tts": {"auto": "off", "provider": "elevenlabs"}},
    "channels": {"telegram": {"enabled": true, "botToken": "", "allowFrom": []}},
    "gateway": {"port": 18789},
  });
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
        if (!current.containsKey(key)) {
          current[key] = <String, dynamic>{};
        } 
        current = current[key]; 
      }
    }
    if (current is Map) {
      current[keys.last] = value;
    }
  }
  String toJson() => const JsonEncoder.withIndent('  ').convert(_data);
}

class ConfigProvider extends ChangeNotifier {
  AppConfig config = AppConfig.defaultConfig();
  String _statusMessage = "Ready";
  late File _configFile;
  String get statusMessage => _statusMessage;
  ConfigProvider() { _init(); }
  String get _homePath => Platform.environment[Platform.isWindows ? 'UserProfile' : 'HOME'] ?? '.';
  Future<void> _init() async {
    final dir = Directory(p.join(_homePath, '.openclaw'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _configFile = File(p.join(dir.path, 'openclaw.json'));
    await loadConfig();
  }
  Future<void> loadConfig() async {
    try {
      if (await _configFile.exists()) { 
        config = AppConfig(jsonDecode(await _configFile.readAsString())); 
      }
    } catch (e) { _statusMessage = "加载配置失败"; }
    notifyListeners();
  }
  Future<void> saveConfig() async {
    try { 
      await _configFile.writeAsString(config.toJson()); 
      _statusMessage = "配置已保存"; 
    } catch (e) { _statusMessage = "保存失败"; }
    notifyListeners();
  }
  void updateField(String path, dynamic value) { config.set(path, value); notifyListeners(); }
}

class FileProvider extends ChangeNotifier {
  List<FileSystemEntity> files = [];
  File? selectedFile;
  String? fileContent;
  String _status = "";
  String get status => _status;
  Future<void> scanWorkspace(String workspacePath) async {
    String realPath = workspacePath.startsWith('~') ? workspacePath.replaceFirst('~', Platform.environment[Platform.isWindows ? 'UserProfile' : 'HOME']!) : workspacePath;
    final dir = Directory(realPath);
    if (!await dir.exists()) { 
      _status = "工作区不存在"; 
      files = []; 
      notifyListeners(); 
      return; 
    }
    try {
      files = (await dir.list().toList()).where((f) => ["AGENTS.md", "SOUL.md", "USER.md", "IDENTITY.md", "TOOLS.md"].contains(p.basename(f.path))).toList();
    } catch (e) { _status = "扫描失败"; }
    notifyListeners();
  }
  Future<void> selectFile(File file) async {
    selectedFile = file;
    try { fileContent = await file.readAsString(); } catch (e) { fileContent = "Error"; }
    notifyListeners();
  }
  Future<void> saveContent(String newContent) async {
    if (selectedFile == null) return;
    try { 
      await selectedFile!.writeAsString(newContent); 
      fileContent = newContent; 
      _status = "已保存"; 
    } catch (e) { _status = "保存失败"; }
    notifyListeners();
  }
}

// ==========================================
// 4. UI 组件与布局
// ==========================================

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final cfg = context.watch<ConfigProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pages = [
      const DashboardPage(),
      const ModelsTab(),
      const ChannelsTab(),
      const SkillsTab(),
      const SoulTab(),
      const SettingsPage(),
    ];

    final titles = ["概览", "AI 配置", "消息渠道", "测试诊断", "应用日志", "设置"];
    final subtitles = ["服务状态、日志与快捷操作", "模型参数与 TTS 设置", "连接 Telegram / Discord", "技能加载与调试", "核心记忆文件管理", "个性化与核心管理"];

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 260,
            color: isDark ? const Color(0xFF161616) : Colors.white,
            child: Column(
              children: [
                _buildSidebarHeader(context),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _NavTile(index: 0, icon: Icons.dashboard_outlined, label: "概览", selected: nav.selectedIndex == 0),
                      const Divider(height: 30, color: Colors.transparent),
                      _NavTile(index: 1, icon: Icons.psychology_outlined, label: "AI 配置", selected: nav.selectedIndex == 1),
                      _NavTile(index: 2, icon: Icons.chat_bubble_outline, label: "消息渠道", selected: nav.selectedIndex == 2),
                      _NavTile(index: 3, icon: Icons.science_outlined, label: "测试诊断", selected: nav.selectedIndex == 3),
                      _NavTile(index: 4, icon: Icons.description_outlined, label: "应用日志", selected: nav.selectedIndex == 4),
                      _NavTile(index: 5, icon: Icons.settings_outlined, label: "设置", selected: nav.selectedIndex == 5),
                    ],
                  ),
                ),
                _buildSidebarFooter(context),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(titles[nav.selectedIndex], style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                          const SizedBox(height: 4),
                          Text(subtitles[nav.selectedIndex], style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                      FilledButton.icon(
                        onPressed: () => cfg.saveConfig(),
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text("Save Config"),
                        style: FilledButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.blue.shade100,
                          foregroundColor: isDark ? Colors.white : Colors.blue.shade900,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: pages[nav.selectedIndex]),
                Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  color: isDark ? const Color(0xFF161616) : Colors.white,
                  alignment: Alignment.centerLeft,
                  child: Text(cfg.statusMessage, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.code, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("OpenClaw", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("Manager", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSidebarFooter(BuildContext context) {
    final launcher = context.watch<LauncherProvider>();
    final isRunning = launcher.isGatewayRunning;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202020) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF333333) : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: isRunning ? Colors.green : Colors.red, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isRunning ? "服务运行中" : "服务已停止", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const Text("端口: 18789", style: TextStyle(fontSize: 12)),
            ],
          )
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final bool selected;
  const _NavTile({required this.index, required this.icon, required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : Colors.grey;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(icon, color: color, size: 20),
        title: Text(label, style: TextStyle(color: selected ? (theme.brightness == Brightness.dark ? Colors.white : Colors.black) : Colors.grey, fontSize: 14, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        selected: selected,
        selectedTileColor: theme.brightness == Brightness.dark ? const Color(0xFF252525) : theme.colorScheme.primary.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => context.read<NavigationProvider>().setIndex(index),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        dense: true,
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final launcher = context.watch<LauncherProvider>();
    final isRunning = launcher.isGatewayRunning;

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        _SectionCard(
          title: "服务状态",
          trailing: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: isRunning ? Colors.green : Colors.red, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(isRunning ? "运行中" : "已停止", style: TextStyle(color: isRunning ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          child: Row(
            children: [
              _InfoBox(icon: Icons.electrical_services, label: "端口", value: launcher.currentPort),
              const SizedBox(width: 16),
              _InfoBox(icon: Icons.memory, label: "进程 ID", value: launcher.currentPid),
              const SizedBox(width: 16),
              _InfoBox(icon: Icons.storage, label: "版本", value: launcher.versionNumber),
              const SizedBox(width: 16),
              _InfoBox(icon: Icons.router, label: "Node", value: launcher.isNodeConnected ? "Connected" : "--"),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "快捷操作",
          child: Row(
            children: [
              _BigActionButton(label: "启动", icon: Icons.play_arrow, color: const Color(0xFF386A20), textColor: const Color(0xFFB8F397), onTap: isRunning ? null : () => launcher.startServices()),
              const SizedBox(width: 16),
              _BigActionButton(label: "停止", icon: Icons.stop, color: Theme.of(context).cardColor, textColor: Colors.grey, onTap: !isRunning ? null : () => launcher.stopAll()),
              const SizedBox(width: 16),
              _BigActionButton(label: "Web 控制台", icon: Icons.language, color: Theme.of(context).cardColor, textColor: const Color(0xFFFFB74D), iconColor: Colors.orange, onTap: isRunning ? () => launcher.openWebUI() : null),
              const SizedBox(width: 16),
              _BigActionButton(label: "强制重启", icon: Icons.refresh, color: Theme.of(context).cardColor, textColor: const Color(0xFFE1BEE7), iconColor: Colors.purpleAccent, onTap: () { launcher.stopAll(); Future.delayed(const Duration(seconds: 2), () => launcher.startServices()); }),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "实时日志",
          trailing: const Icon(Icons.refresh, size: 16, color: Colors.grey),
          child: Container(
            height: 250,
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F0F) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              controller: launcher.logScrollCtrl,
              itemCount: launcher.logs.length,
              itemBuilder: (ctx, i) {
                final log = launcher.logs[i];
                Color c = Colors.grey;
                if (log.type == "ERROR") c = Colors.red;
                if (log.type == "SUCCESS") c = Colors.green;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text("[${log.time}] ${log.message}", style: TextStyle(color: c, fontFamily: "Consolas", fontSize: 12)),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF333333) : Colors.grey.shade300),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
              // ignore: use_null_aware_elements
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoBox({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF282828) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
          ],
        ),
      ),
    );
  }
}

class _BigActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color textColor;
  final Color? iconColor;
  final VoidCallback? onTap;

  const _BigActionButton({required this.label, required this.icon, required this.color, required this.textColor, this.iconColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? color : (color == const Color(0xFF386A20) ? color : Colors.white);
    final border = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade300;

    return Expanded(
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1.0,
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
            boxShadow: (isDark || onTap == null) ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5)],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: iconColor ?? textColor),
                const SizedBox(height: 8),
                Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final launcher = context.watch<LauncherProvider>();

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        _SectionCard(
          title: "🎨 界面偏好",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("主题模式"),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('跟随系统'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: ThemeMode.light, label: Text('亮色模式'), icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('深色模式'), icon: Icon(Icons.dark_mode)),
                ],
                selected: {themeProvider.themeMode},
                onSelectionChanged: (Set<ThemeMode> newSelection) {
                  themeProvider.setThemeMode(newSelection.first);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "🛠️ 核心管理",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("当前版本: ${launcher.versionNumber}"),
              const SizedBox(height: 16),
              const Text("安装/修复核心 (PowerShell)"),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(icon: const Icon(Icons.download), label: const Text("安装 OpenClaw CN"), onPressed: () => launcher.runInstaller("powershell")),
                  OutlinedButton.icon(icon: const Icon(Icons.download), label: const Text("安装 OpenClaw 原版"), onPressed: () => launcher.runInstaller("powershell")),
                ],
              ),
            ],
          ),
        )
      ],
    );
  }
}

class _ConfigTextField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool isSecret;
  const _ConfigTextField({required this.label, required this.value, required this.onChanged, this.isSecret = false});
  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController(text: value);
    ctrl.selection = TextSelection.fromPosition(TextPosition(offset: ctrl.text.length));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(controller: ctrl, obscureText: isSecret, onChanged: onChanged, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class ModelsTab extends StatelessWidget {
  const ModelsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        _ConfigTextField(label: "主模型", value: cfg.config.get("agents.defaults.model.primary") ?? "", onChanged: (v) => cfg.updateField("agents.defaults.model.primary", v)),
        _ConfigTextField(label: "视觉模型", value: cfg.config.get("agents.defaults.imageModel.primary") ?? "", onChanged: (v) => cfg.updateField("agents.defaults.imageModel.primary", v)),
      ],
    );
  }
}

class ChannelsTab extends StatelessWidget {
  const ChannelsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        _ConfigTextField(label: "Telegram Bot Token", value: cfg.config.get("channels.telegram.botToken") ?? "", onChanged: (v) => cfg.updateField("channels.telegram.botToken", v), isSecret: true),
      ],
    );
  }
}

class SkillsTab extends StatelessWidget {
  const SkillsTab({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("技能诊断模块开发中...", style: TextStyle(color: Colors.grey)));
  }
}

class SoulTab extends StatefulWidget {
  const SoulTab({super.key});
  @override
  State<SoulTab> createState() => _SoulTabState();
}

class _SoulTabState extends State<SoulTab> {
  final TextEditingController _controller = TextEditingController();
  String? _currentFilePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cfg = context.read<ConfigProvider>();
      context.read<FileProvider>().scanWorkspace(cfg.config.get('agents.defaults.workspace') ?? "~/.openclaw/workspace");
    });
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FileProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (fp.fileContent != null && _controller.text != fp.fileContent && fp.selectedFile?.path != _currentFilePath) {
      _controller.text = fp.fileContent!;
      _currentFilePath = fp.selectedFile?.path;
    }

    return Row(
      children: [
        Container(
          width: 200,
          decoration: BoxDecoration(border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)))),
          child: ListView.builder(
            itemCount: fp.files.length,
            itemBuilder: (ctx, i) {
              final f = fp.files[i] as File;
              final selected = f.path == fp.selectedFile?.path;
              return ListTile(
                title: Text(p.basename(f.path), style: TextStyle(color: selected ? (isDark ? Colors.white : Colors.black) : Colors.grey, fontSize: 13)),
                selected: selected,
                selectedTileColor: isDark ? const Color(0xFF252525) : Colors.blue.withValues(alpha: 0.1),
                onTap: () { context.read<FileProvider>().selectFile(f); _currentFilePath = null; },
              );
            },
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(fp.selectedFile != null ? p.basename(fp.selectedFile!.path) : "NO FILE", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    TextButton(onPressed: fp.selectedFile == null ? null : () => context.read<FileProvider>().saveContent(_controller.text), child: const Text("Save"))
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 13, height: 1.4),
                  decoration: InputDecoration(
                    fillColor: isDark ? const Color(0xFF141414) : Colors.white,
                    filled: true,
                    border: InputBorder.none, 
                    contentPadding: const EdgeInsets.all(16)
                  ),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}