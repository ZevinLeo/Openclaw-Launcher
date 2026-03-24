// ignore_for_file: unnecessary_import, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ==========================================
// 1. 程序入口
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
        ChangeNotifierProvider(create: (_) => SkillsProvider()), // <--- 新增这一行
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
    
    // 定义你的蓝色主题色
    const primaryBlue = Color(0xFF2979FF); // 深色模式下的亮蓝
    const primaryBlueLight = Color(0xFF0078D4); // 亮色模式下的标准蓝

    return MaterialApp(
      title: 'OpenClaw Manager',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      
      // --- 亮色主题 (Light) ---
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF3F3F3),
        cardColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlueLight, 
          primary: primaryBlueLight,
          brightness: Brightness.light
        ),
        fontFamily: Platform.isWindows ? 'Microsoft YaHei UI' : null,
        dividerColor: Colors.grey.shade300,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBlueLight,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),

      // --- 深色主题 (Dark - 布局样式还原) ---
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F), // 极深黑背景
        cardColor: const Color(0xFF1E1E1E), // 卡片背景
        colorScheme: const ColorScheme.dark(
          primary: primaryBlue, // <--- 关键修改：这里改成了蓝色
          surface: Color(0xFF1E1E1E),
          outline: Color(0xFF333333),
        ),
        fontFamily: Platform.isWindows ? 'Microsoft YaHei UI' : null,
        dividerColor: const Color(0xFF2C2C2C),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF252525),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBlue, // 按钮变蓝
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: const MainLayout(),
    );
  }
}

// ==========================================
// 2. 核心 Provider (逻辑保持完整)
// ==========================================

class LogEntry {
  final String message;
  final String type;
  final String time;
  LogEntry(this.message, this.type) : time = "${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}";
}

class LauncherProvider extends ChangeNotifier {
  String? cliCmd;
  String versionNumber = "检测中...";
  String remoteVersion = "";
  Process? _procGateway;
  Process? _procNode;
  
  bool isGatewayRunning = false;
  bool isNodeConnected = false;
  bool isNodeInstalling = false;
  
  String currentPort = "18789";
  String currentPid = "--";
  
  List<LogEntry> logs = [];
  final ScrollController logScrollCtrl = ScrollController();

  LauncherProvider() {
    _initFullCheck();
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

  Future<void> _initFullCheck() async {
    addLog("初始化环境检测...", type: "CMD");
    if (!await _checkNodeInstalled()) {
      addLog("警告: 未检测到 Node.js 环境，无法运行服务。", type: "ERROR");
      isNodeInstalling = true;
      notifyListeners();
      return;
    }
    if (await _checkVersion("openclaw")) {
      cliCmd = "openclaw";
      addLog("核心已就绪: openclaw ($versionNumber)", type: "SUCCESS");
    } else {
      versionNumber = "未安装";
      addLog("未检测到核心程序，请前往设置页进行安装。", type: "ERROR");
    }
    notifyListeners();
  }

  Future<bool> _checkNodeInstalled() async {
    try {
      final res = await Process.run('node', ['-v'], runInShell: true);
      return res.exitCode == 0;
    } catch (e) { return false; }
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

  Future<void> checkForUpdates() async {
    if (cliCmd == null) {
      addLog("核心未安装，无法检查更新。", type: "ERROR");
      return;
    }
    addLog("正在检查云端版本 (npm view)...", type: "INFO");
    try {
      final res = await Process.run("npm", ["view", cliCmd!, "version"], runInShell: true);
      if (res.exitCode == 0) {
        remoteVersion = res.stdout.toString().trim();
        addLog("云端最新版本: $remoteVersion", type: "SUCCESS");
        if (remoteVersion != versionNumber) {
          addLog("发现新版本！请在设置页执行安装以更新。", type: "INFO");
        } else {
          addLog("当前已是最新版本。", type: "INFO");
        }
        notifyListeners();
      } else {
        addLog("版本检查失败: ${res.stderr}", type: "ERROR");
      }
    } catch (e) {
      addLog("无法连接 NPM 仓库。", type: "ERROR");
    }
  }

  Future<void> startServices() async {
    if (cliCmd == null) {
      addLog("错误: 未找到核心程序，无法启动。", type: "ERROR");
      return;
    }
    if (isGatewayRunning) return;

    addLog(">>> 正在启动 Gateway 服务...", type: "CMD");
    
    try {
      _procGateway = await Process.start(cliCmd!, ['gateway'], runInShell: true, mode: ProcessStartMode.normal);
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

      await Future.delayed(const Duration(milliseconds: 500));
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

      await Future.delayed(const Duration(seconds: 3));
      await _checkNodeStatus();
    } catch (e) {
      addLog("Node 启动失败: $e", type: "ERROR");
    }
  }

  Future<void> _checkNodeStatus() async {
    try {
      final res = await Process.run(cliCmd!, ['nodes', 'status'], runInShell: true);
      final out = res.stdout.toString();
      if (out.contains("Connected") || out.contains("paired")) {
        isNodeConnected = true;
        addLog("Node 已成功连接至集群。", type: "SUCCESS");
      } else {
        addLog("Node 状态检查: 未连接 (仍在重试...)", type: "DEBUG");
      }
      notifyListeners();
    } catch (e) { /* ignore */ }
  }

  Future<void> stopAll() async {
    addLog(">>> 正在停止所有服务...", type: "CMD");
    _procGateway?.kill();
    _procNode?.kill();
    if (Platform.isWindows) {
      try { await Process.run('taskkill', ['/F', '/IM', 'node.exe'], runInShell: true); } catch (e) { /* ignore */ }
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
        if (line.trim().isNotEmpty) addLog(line.trim(), type: isError ? "ERROR" : "INFO");
      }
    });
  }

  Future<bool> _waitForGatewayHttp() async {
    for (int i = 0; i < 20; i++) { 
      try {
        final response = await http.get(Uri.parse('http://127.0.0.1:18789/'));
        if (response.statusCode == 200 || response.statusCode == 404) return true;
      } catch (e) { /* ignore */ }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  // 智能安装：自动判断 OS
  Future<void> runSmartInstaller() async {
    addLog("正在启动智能安装流程...", type: "CMD");
    
    const String urlSh = "https://openclaw.ai/install.sh";
    const String urlPs = "https://openclaw.ai/install.ps1";

    try {
      if (Platform.isWindows) {
        addLog("检测到 Windows 系统，正在调用 PowerShell 安装脚本...", type: "INFO");
        final psCommand = "iwr -useb $urlPs | iex";
        await Process.start('start', ['cmd', '/k', 'powershell -Command "$psCommand"'], runInShell: true);
        addLog("已弹出安装终端，请在窗口中查看进度。", type: "SUCCESS");
      } else {
        addLog("检测到 Unix 系统，正在调用 Bash 安装脚本...", type: "INFO");
        final bashCmd = "curl -fsSL $urlSh | bash";
        final process = await Process.start('sh', ['-c', bashCmd]);
        _monitorStream(process.stdout, "Install");
        _monitorStream(process.stderr, "Install Error", isError: true);
      }
      addLog("等待安装完成后，系统将自动刷新状态...", type: "INFO");
      await Future.delayed(const Duration(seconds: 8));
      _initFullCheck();
    } catch (e) {
      addLog("启动安装程序失败: $e", type: "ERROR");
    }
  }

  Future<void> runCommand(String args) async {
    if (cliCmd == null) return;
    addLog("执行: $cliCmd $args", type: "CMD");
    if (Platform.isWindows) {
      await Process.start('start', ['cmd', '/k', '$cliCmd $args'], runInShell: true);
    } else {
      final res = await Process.run(cliCmd!, args.split(" "), runInShell: true);
      addLog(res.stdout.toString());
    }
  }

  Future<void> backupData() async {
    try {
      final home = Platform.environment[Platform.isWindows ? 'UserProfile' : 'HOME'];
      if (home == null) return;
      final sourceDir = Directory(p.join(home, '.openclaw'));
      if (!await sourceDir.exists()) {
        addLog("未找到 .openclaw 目录，无需备份。", type: "INFO");
        return;
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final destPath = p.join(home, 'Desktop', 'OpenClaw_Backup_$timestamp');
      final destDir = Directory(destPath);
      await destDir.create(recursive: true);
      addLog("正在备份数据到: $destPath", type: "CMD");
      await _copyDirectory(sourceDir, destDir);
      addLog("备份完成。", type: "SUCCESS");
      launchUrl(Uri.file(destPath));
    } catch (e) {
      addLog("备份失败: $e", type: "ERROR");
    }
  }

  Future<void> _copyDirectory(Directory source, Directory dest) async {
    await for (var entity in source.list(recursive: false)) {
      if (entity is Directory) {
        var newDir = Directory(p.join(dest.absolute.path, p.basename(entity.path)));
        await newDir.create();
        await _copyDirectory(entity.absolute, newDir);
      } else if (entity is File) {
        await entity.copy(p.join(dest.path, p.basename(entity.path)));
      }
    }
  }

  Future<void> forceClean() async {
     addLog("正在执行强力清理...", type: "CMD");
     if (Platform.isWindows) {
       await Process.run('npm', ['uninstall', '-g', 'openclaw'], runInShell: true);
       await Process.run('pnpm', ['remove', '-g', 'openclaw'], runInShell: true);
     }
     addLog("清理指令已下达。请重新点击检测。", type: "SUCCESS");
     versionNumber = "已清理";
     cliCmd = null;
     notifyListeners();
  }
}

// ...ConfigProvider, FileProvider, ThemeProvider, NavigationProvider 保持不变...
// (为了确保代码完整性，以下重复这部分，确保单文件运行)

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
    "channels": {
      "whatsapp": {"enabled": true, "dmPolicy": "pairing", "selfChatMode": false, "mediaMaxMb": 50, "allowFrom": [], "configWrites": true, "ackReaction": {"emoji": "👀", "direct": true, "group": "mentions"}},
      "telegram": {"enabled": true, "botToken": "", "dmPolicy": "pairing", "streamMode": "partial", "allowFrom": [], "capabilities": {"inlineButtons": "allowlist"}},
      "feishu": {"enabled": false, "domain": "feishu", "accounts": {"main": {"appId": "", "appSecret": ""}}, "dmPolicy": "pairing"}
    },
    "gateway": {"port": 18789},
    "models": {"providers": {}}
  });
  dynamic get(String path) {
    List<String> keys = path.split('.');
    dynamic current = _data;
    for (var key in keys) {
      if (current is Map && current.containsKey(key)) current = current[key]; else return null;
    }
    return current;
  }
  void set(String path, dynamic value) {
    List<String> keys = path.split('.');
    dynamic current = _data;
    for (int i = 0; i < keys.length - 1; i++) {
      var key = keys[i];
      if (current is Map) { if (!current.containsKey(key)) current[key] = <String, dynamic>{}; current = current[key]; }
    }
    if (current is Map) current[keys.last] = value;
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
    if (!await dir.exists()) await dir.create(recursive: true);
    _configFile = File(p.join(dir.path, 'openclaw.json'));
    await loadConfig();
  }
  Future<void> loadConfig() async {
    try {
      if (await _configFile.exists()) { config = AppConfig(jsonDecode(await _configFile.readAsString())); }
    } catch (e) { _statusMessage = "加载配置失败"; }
    notifyListeners();
  }
  Future<void> saveConfig() async {
    try { await _configFile.writeAsString(config.toJson()); _statusMessage = "配置已保存"; } catch (e) { _statusMessage = "保存失败"; }
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
    if (!await dir.exists()) { _status = "工作区不存在"; files = []; notifyListeners(); return; }
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
    try { await selectedFile!.writeAsString(newContent); fileContent = newContent; _status = "已保存"; } catch (e) { _status = "保存失败"; }
    notifyListeners();
  }
}

// ==========================================
// 新增：技能管理 Provider
// ==========================================

class SkillModel {
  final String id;
  final String name;
  final String description;
  final String path;
  final String type; // 'workspace', 'global', 'bundled'
  final String? emoji;
  final Map<String, dynamic> metadata;
  
  SkillModel({
    required this.id, 
    required this.name, 
    required this.description, 
    required this.path, 
    required this.type,
    this.emoji,
    this.metadata = const {},
  });
}

class SkillsProvider extends ChangeNotifier {
  List<SkillModel> skills = [];
  bool isLoading = false;
  final String _homePath = Platform.environment[Platform.isWindows ? 'UserProfile' : 'HOME'] ?? '.';

  // 模拟 Bundled 技能 (因为无法直接读取打包内的文件，实际开发中可用 AssetBundle)
  final List<SkillModel> _bundledDefaults = [
    SkillModel(id: "browser", name: "browser", description: "Headless web browsing and interaction", path: "internal", type: "bundled", emoji: "🌐"),
    SkillModel(id: "python", name: "python", description: "Execute Python code in sandbox", path: "internal", type: "bundled", emoji: "🐍"),
  ];

  Future<void> loadSkills(String workspacePath) async {
    isLoading = true;
    notifyListeners();
    skills.clear();
    skills.addAll(_bundledDefaults);

    // 1. 扫描 Global Skills (~/.openclaw/skills)
    await _scanDir(p.join(_homePath, '.openclaw', 'skills'), 'global');

    // 2. 扫描 Workspace Skills
    String realWsPath = workspacePath.startsWith('~') 
        ? workspacePath.replaceFirst('~', _homePath) 
        : workspacePath;
    await _scanDir(p.join(realWsPath, 'skills'), 'workspace');

    // 去重逻辑：Workspace > Global > Bundled
    final Map<String, SkillModel> uniqueMap = {};
    // 先加低优先级的
    for (var s in skills) { uniqueMap[s.id] = s; } 
    // 这里的逻辑是后进覆盖，所以扫描顺序很重要，上面 scanDir 实际上是 append，
    // 为了实现 Workspace 覆盖 Global，我们需要倒序处理或者在 scan 时判断，
    // 简单起见，我们假设 UI 显示所有来源，但在 UI 层级标明 "Override"
    
    // 重新排序：Workspace 优先显示
    skills.sort((a, b) {
      if (a.type == 'workspace' && b.type != 'workspace') return -1;
      if (a.type != 'workspace' && b.type == 'workspace') return 1;
      return a.id.compareTo(b.id);
    });

    isLoading = false;
    notifyListeners();
  }

  Future<void> _scanDir(String dirPath, String type) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    try {
      await for (var entity in dir.list()) {
        if (entity is Directory) {
          final skillMd = File(p.join(entity.path, 'SKILL.md'));
          if (await skillMd.exists()) {
            final content = await skillMd.readAsString();
            final meta = _parseFrontmatter(content);
            final folderName = p.basename(entity.path);
            
            // 如果 SKILL.md 里没有 name，用文件夹名
            final id = meta['name'] ?? folderName;
            
            // 检查是否覆盖了已有的 (简单的 list 替换逻辑)
            skills.removeWhere((s) => s.id == id); // 移除旧的（低优先级的）
            
            skills.add(SkillModel(
              id: id,
              name: id,
              description: meta['description'] ?? 'No description',
              path: entity.path,
              type: type,
              emoji: meta['emoji'], // 从 metadata.openclaw.emoji 获取
              metadata: meta,
            ));
          }
        }
      }
    } catch (e) {
      print("Scan Error: $e");
    }
  }

  // 一个简易的 Frontmatter 解析器 (不依赖 YAML 包以保持单文件运行)
  Map<String, dynamic> _parseFrontmatter(String content) {
    final Map<String, dynamic> result = {};
    try {
      final match = RegExp(r'^---\s*\n(.*?)\n---', dotAll: true).firstMatch(content);
      if (match != null) {
        final yamlText = match.group(1)!;
        final lines = yamlText.split('\n');
        for (var line in lines) {
          final parts = line.split(':');
          if (parts.length >= 2) {
            final key = parts[0].trim();
            var value = parts.sublist(1).join(':').trim();
            // 去除引号
            if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
              value = value.substring(1, value.length - 1);
            }
            result[key] = value;
          }
          // 极其简陋的 metadata 提取，仅用于演示 Emoji
          if (line.contains('"emoji":')) {
             final emojiMatch = RegExp(r'"emoji":\s*"([^"]+)"').firstMatch(line);
             if (emojiMatch != null) result['emoji'] = emojiMatch.group(1);
          }
        }
      }
    } catch (e) { /* ignore */ }
    return result;
  }
}

// ==========================================
// 3. 主布局 (Sidebar + Content)
// ==========================================

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 页面路由
    final pages = [
      const DashboardPage(),      // 0: 主页
      const AIConfigPage(),       // 1: AI 配置
      const ChannelsPage(),       // 2: 消息渠道 (二级侧边栏)
      const SkillsPage(),          // 3: 测试诊断
      const SoulTab(),            // 4: 应用日志
      const SettingsPage(),       // 5: 设置
    ];

    return Scaffold(
      body: Row(
        children: [
          // 一级侧边栏 (最左侧) - 始终保持深色或跟随主题
          Container(
            width: 240,
            color: isDark ? const Color(0xFF111111) : Colors.white,
            child: Column(
              children: [
                // Logo Area
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary, // 使用主题蓝
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.code, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("OpenClaw", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text("Manager", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      )
                    ],
                  ),
                ),
                
                // Navigation Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _SidebarItem(icon: Icons.home_rounded, label: "主页", index: 0, isSelected: nav.selectedIndex == 0),
                      const SizedBox(height: 4),
                      _SidebarItem(icon: Icons.smart_toy_outlined, label: "AI 配置", index: 1, isSelected: nav.selectedIndex == 1),
                      const SizedBox(height: 4),
                      _SidebarItem(icon: Icons.chat_bubble_outline_rounded, label: "消息渠道", index: 2, isSelected: nav.selectedIndex == 2),
                      const SizedBox(height: 4),
                      _SidebarItem(icon: Icons.extension_outlined, label: "技能管理", index: 3, isSelected: nav.selectedIndex == 3),
                      const SizedBox(height: 4),
                      _SidebarItem(icon: Icons.description_outlined, label: "应用日志", index: 4, isSelected: nav.selectedIndex == 4),
                      const SizedBox(height: 4),
                      _SidebarItem(icon: Icons.settings_outlined, label: "设置", index: 5, isSelected: nav.selectedIndex == 5),
                    ],
                  ),
                ),

                // Bottom Status
                _BottomStatusWidget(),
              ],
            ),
          ),
          
          // 右侧内容区
          Expanded(
            child: pages[nav.selectedIndex],
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool isSelected;

  const _SidebarItem({required this.icon, required this.label, required this.index, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeColor = theme.colorScheme.primary; // 蓝色
    
    // 文字颜色：深色模式下选中是白，未选中灰；亮色模式下选中蓝，未选中灰
    final fgColor = isSelected 
        ? (isDark ? Colors.white : activeColor) 
        : Colors.grey;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.read<NavigationProvider>().setIndex(index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected 
              ? (isDark ? const Color(0xFF252525) : activeColor.withAlpha(25)) 
              : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // 蓝色指示条
              if (isSelected)
                Container(
                  width: 3, height: 16,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: activeColor, // 蓝色
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              else
                const SizedBox(width: 15),
              
              Icon(icon, size: 20, color: fgColor),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(
                color: fgColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomStatusWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final launcher = context.watch<LauncherProvider>();
    final isRunning = launcher.isGatewayRunning;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.transparent : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: isRunning ? Colors.green : Colors.red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isRunning ? "服务运行中" : "服务未启动", style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const Text("端口: 18789", style: TextStyle(color: Colors.grey, fontSize: 11)), // 修正透明度文本颜色
            ],
          )
        ],
      ),
    );
  }
}

// ==========================================
// 4. Dashboard (主页)
// ==========================================

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final launcher = context.watch<LauncherProvider>();
    final isRunning = launcher.isGatewayRunning;

    return Column(
      children: [
        _HeaderBar(title: "主页", subtitle: "服务状态、日志与快捷操作"),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _SectionCard(
                title: "服务状态",
                trailing: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: isRunning ? Colors.green : Colors.red, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(isRunning ? "运行中" : "已停止", style: TextStyle(color: isRunning ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                child: Row(
                  children: [
                    _StatusItem(icon: Icons.bolt, label: "端口", value: launcher.currentPort),
                    const SizedBox(width: 16),
                    _StatusItem(icon: Icons.memory, label: "进程 ID", value: launcher.currentPid),
                    const SizedBox(width: 16),
                    // 版本卡片，内含检查更新按钮
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF252525) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.storage, size: 14, color: Colors.grey),
                              const SizedBox(width: 6),
                              const Text("版本", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ]),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(launcher.versionNumber, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                if (launcher.remoteVersion.isNotEmpty && launcher.remoteVersion != launcher.versionNumber) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                                    child: Text("New: ${launcher.remoteVersion}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                                const Spacer(),
                                SizedBox(
                                  height: 28,
                                  child: OutlinedButton.icon(
                                    onPressed: () => launcher.checkForUpdates(),
                                    icon: const Icon(Icons.update, size: 14),
                                    label: const Text("检查更新", style: TextStyle(fontSize: 11)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    _StatusItem(icon: Icons.router, label: "Node", value: launcher.isNodeConnected ? "已连接" : "--"),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SectionCard(
                title: "快捷操作",
                child: Row(
                  children: [
                    _DashboardBtn(
                      label: "启动", icon: Icons.play_arrow, 
                      color: const Color(0xFF386A20), iconColor: const Color(0xFFB8F397), 
                      onTap: isRunning ? null : () => launcher.startServices()
                    ),
                    const SizedBox(width: 16),
                    _DashboardBtn(label: "停止", icon: Icons.stop, color: null, iconColor: const Color.fromARGB(255, 0, 0, 0), onTap: !isRunning ? null : () => launcher.stopAll()),
                    const SizedBox(width: 16),
                    _DashboardBtn(label: "WebUI", icon: Icons.language, color: null, iconColor: Colors.orange, onTap: isRunning ? () => launcher.openWebUI() : null),
                    const SizedBox(width: 16),
                    _DashboardBtn(label: "重启", icon: Icons.refresh, color: null, iconColor: Colors.purpleAccent, onTap: () { launcher.stopAll(); Future.delayed(const Duration(seconds: 2), () => launcher.startServices()); }),
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
          ),
        ),
      ],
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatusItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252525) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
          ],
        ),
      ),
    );
  }
}

class _DashboardBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final Color iconColor;
  final VoidCallback? onTap;

  const _DashboardBtn({required this.label, required this.icon, this.color, required this.iconColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = color ?? (isDark ? const Color(0xFF252525) : Colors.white);
    
    return Expanded(
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1.0,
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          elevation: color == null && !isDark ? 2 : 0, // 亮色模式下给白色按钮一点阴影
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 90,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: iconColor, size: 24),
                  const SizedBox(height: 8),
                  Text(label, style: TextStyle(color: iconColor, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 5. AI 配置页面 (完全重构)
// ==========================================

class AIConfigPage extends StatefulWidget {
  const AIConfigPage({super.key});

  @override
  State<AIConfigPage> createState() => _AIConfigPageState();
}

class _AIConfigPageState extends State<AIConfigPage> {
  // selectionId: "core" 代表核心设置，其他字符串代表 Provider 的 ID
  String _selectionId = "core"; 

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final modelsConfig = cfg.config.get("models") as Map? ?? {};
    final providers = Map<String, dynamic>.from(modelsConfig["providers"] as Map? ?? {});

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF111111) : Colors.white; // 二级侧边栏背景

    return Row(
      children: [
        // --- 左侧：二级侧边栏 ---
        Container(
          width: 260,
          color: sidebarBg,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("全局设置", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              _SecondarySidebarItem(
                icon: Icons.hub,
                title: "核心模型路由",
                subtitle: "Primary & Fallback",
                isSelected: _selectionId == "core",
                onTap: () => setState(() => _selectionId = "core"),
              ),
              const SizedBox(height: 24),
              
              // Provider 列表头 + 添加按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("模型提供商", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    tooltip: "添加提供商",
                    onPressed: () => _showAddProviderDialog(context, providers, cfg),
                  )
                ],
              ),
              const SizedBox(height: 8),
              
              // 动态 Provider 列表
              Expanded(
                child: ListView(
                  children: providers.keys.map((key) {
                    final pData = providers[key] as Map;
                    return _SecondarySidebarItem(
                      icon: Icons.dns_outlined,
                      title: key,
                      subtitle: pData['api'] ?? 'openai',
                      isSelected: _selectionId == key,
                      onTap: () => setState(() => _selectionId = key),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // --- 右侧：内容详情区 ---
        Expanded(
          child: Column(
            children: [
               _HeaderBar(
                 title: _selectionId == "core" ? "核心路由" : "提供商: $_selectionId", 
                 subtitle: _selectionId == "core" ? "配置系统的默认模型与视觉模型" : "配置 BaseURL 与 API Key"
               ),
               Expanded(
                 child: ListView(
                   padding: const EdgeInsets.all(32),
                   children: [
                     if (_selectionId == "core")
                       _buildCoreSettings(context)
                     else if (providers.containsKey(_selectionId))
                       _buildProviderSettings(context, _selectionId, providers[_selectionId], cfg)
                     else
                       const Center(child: Text("未找到配置"))
                   ],
                 ),
               )
            ],
          ),
        ),
      ],
    );
  }

  // 构建核心设置视图
  Widget _buildCoreSettings(BuildContext context) {
    final cfg = context.read<ConfigProvider>();
    final agentDefaults = cfg.config.get("agents.defaults") as Map? ?? {};
    final modelDefaults = agentDefaults["model"] as Map? ?? {};
    final imageDefaults = agentDefaults["imageModel"] as Map? ?? {};

    return Column(
      children: [
        _SectionCard(
          title: "默认模型",
          child: Column(
            children: [
              _ConfigTextField(
                label: "主模型 ID (Primary)",
                value: modelDefaults["primary"] ?? "",
                onChanged: (v) => cfg.updateField("agents.defaults.model.primary", v),
              ),
              _ConfigTextField(
                label: "视觉模型 ID (Vision)",
                value: imageDefaults["primary"] ?? "",
                onChanged: (v) => cfg.updateField("agents.defaults.imageModel.primary", v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "高可用策略",
          child: _StringListEditor(
            label: "回退模型列表 (Fallbacks)",
            items: modelDefaults["fallbacks"] ?? [],
            onChanged: (list) => cfg.updateField("agents.defaults.model.fallbacks", list),
          ),
        ),
      ],
    );
  }

  // 构建 Provider 详情视图
  Widget _buildProviderSettings(BuildContext context, String id, Map data, ConfigProvider cfg) {
    // 这里复用原本的逻辑，但展开为平铺视图
    return Column(
      children: [
        _SectionCard(
          title: "连接凭证",
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () {
               final newMap = Map<String, dynamic>.from(cfg.config.get("models.providers"));
               newMap.remove(id);
               cfg.updateField("models.providers", newMap);
               setState(() => _selectionId = "core");
            },
          ),
          child: Column(
            children: [
              _ConfigTextField(
                label: "Base URL", 
                value: data["baseUrl"] ?? "", 
                onChanged: (v) => cfg.updateField("models.providers.$id.baseUrl", v)
              ),
              _ConfigTextField(
                label: "API Key", 
                value: data["apiKey"] ?? "", 
                isSecret: true, 
                onChanged: (v) => cfg.updateField("models.providers.$id.apiKey", v)
              ),
              _ConfigTextField(
                label: "API Type", 
                value: data["api"] ?? "openai-completions", 
                onChanged: (v) => cfg.updateField("models.providers.$id.api", v)
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "模型映射",
          child: _ModelListEditor(
            models: List<Map<String, dynamic>>.from((data["models"] as List? ?? []).map((e) => Map<String, dynamic>.from(e))), 
            onChanged: (list) => cfg.updateField("models.providers.$id.models", list)
          ),
        ),
      ],
    );
  }

  void _showAddProviderDialog(BuildContext context, Map providers, ConfigProvider cfg) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("添加提供商"),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: "ID (如: deepseek, openai)")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
        FilledButton(onPressed: () {
          final id = ctrl.text.trim();
          if (id.isNotEmpty && !providers.containsKey(id)) {
            // 直接更新 Config
            cfg.updateField("models.providers.$id", {
              "baseUrl": "https://api.example.com/v1", 
              "apiKey": "", 
              "api": "openai-completions", 
              "models": []
            });
            setState(() => _selectionId = id);
          }
          Navigator.pop(ctx);
        }, child: const Text("添加"))
      ],
    ));
  }
}

// ==========================================
// 补全：AI 模型列表编辑器组件
// ==========================================

class _ModelListEditor extends StatelessWidget {
  final List<Map<String, dynamic>> models;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  const _ModelListEditor({required this.models, required this.onChanged});

  void _addModel() {
    final newList = List<Map<String, dynamic>>.from(models)
      ..add({
        "id": "new-model",
        "name": "New Model",
        "reasoning": false,
        "contextWindow": 200000,
        "maxTokens": 8192,
        "input": ["text"]
      });
    onChanged(newList);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text("模型列表", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        TextButton.icon(
            onPressed: _addModel,
            icon: const Icon(Icons.add, size: 16),
            label: const Text("添加模型")),
      ]),
      const SizedBox(height: 8),
      if (models.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text("暂无模型映射，请点击添加。", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      ...models.asMap().entries.map((e) => _ModelEditCard(
            data: e.value,
            onUpdate: (v) {
              final l = List<Map<String, dynamic>>.from(models);
              l[e.key] = v;
              onChanged(l);
            },
            onRemove: () {
              final l = List<Map<String, dynamic>>.from(models);
              l.removeAt(e.key);
              onChanged(l);
            },
          )),
    ]);
  }
}

class _ModelEditCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  final VoidCallback onRemove;
  const _ModelEditCard({required this.data, required this.onUpdate, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252525) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: TextField(
                  controller: TextEditingController(text: data["id"]),
                  decoration: const InputDecoration(
                      labelText: "Model ID (e.g. gpt-4)", isDense: true, border: UnderlineInputBorder()),
                  onChanged: (v) {
                    data["id"] = v;
                    data["name"] = v;
                    onUpdate(data);
                  })),
          IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.red), onPressed: onRemove)
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _SmallNumField(
                  label: "Context",
                  value: data["contextWindow"] ?? 200000,
                  onChanged: (v) {
                    data["contextWindow"] = v;
                    onUpdate(data);
                  })),
          const SizedBox(width: 8),
          Expanded(
              child: _SmallNumField(
                  label: "Tokens",
                  value: data["maxTokens"] ?? 8192,
                  onChanged: (v) {
                    data["maxTokens"] = v;
                    onUpdate(data);
                  })),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: CheckboxListTile(
                  title: const Text("启用推理 (Reasoning)", style: TextStyle(fontSize: 12)),
                  value: data["reasoning"] ?? false,
                  onChanged: (v) {
                    data["reasoning"] = v;
                    onUpdate(data);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero)),
        ])
      ]),
    );
  }
}

class _SmallNumField extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _SmallNumField({required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (v) => onChanged(int.tryParse(v) ?? value));
}

// ==========================================
// 6. 消息渠道 (二级侧边栏样式更新)
// ==========================================

class ChannelsPage extends StatefulWidget {
  const ChannelsPage({super.key});
  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  int _selectedChannelIdx = 0;
  
  // OpenClaw 支持的所有渠道模板（用于添加时选择）
  static final allAvailableChannels = [
    {"name": "WhatsApp", "icon": Icons.phone_android, "desc": "Meta 官方 API", "configKey": "whatsapp"},
    {"name": "Telegram", "icon": Icons.send, "desc": "Bot API", "configKey": "telegram"},
    {"name": "Feishu", "icon": Icons.work, "desc": "飞书/Lark 机器人", "configKey": "feishu"},
    {"name": "Discord", "icon": Icons.discord, "desc": "Bot Gateway", "configKey": "discord"},
    {"name": "iMessage", "icon": Icons.message, "desc": "macOS 本地集成", "configKey": "imessage"},
  ];

  // 当前已添加的渠道
  List<Map<String, dynamic>> channels = [
    {"name": "WhatsApp", "icon": Icons.phone_android, "desc": "Meta 官方 API", "configKey": "whatsapp"},
    {"name": "Telegram", "icon": Icons.send, "desc": "Bot API", "configKey": "telegram"},
    {"name": "Feishu", "icon": Icons.work, "desc": "飞书/Lark 机器人", "configKey": "feishu"},
    {"name": "Discord", "icon": Icons.discord, "desc": "Bot Gateway", "configKey": "discord"},
    {"name": "iMessage", "icon": Icons.message, "desc": "macOS 本地集成", "configKey": "imessage"},
  ];

  void _addChannel(BuildContext context) {
    // 找出尚未添加的渠道
    final existingKeys = channels.map((c) => c["configKey"]).toSet();
    final available = allAvailableChannels.where((c) => !existingKeys.contains(c["configKey"])).toList();
    
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("所有支持的渠道都已添加")));
      return;
    }

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("添加渠道"),
      content: SizedBox(
        width: 300,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: available.length,
          itemBuilder: (_, i) {
            final ch = available[i];
            return ListTile(
              leading: Icon(ch["icon"] as IconData),
              title: Text(ch["name"] as String),
              subtitle: Text(ch["desc"] as String),
              onTap: () {
                setState(() {
                  channels.add(Map<String, dynamic>.from(ch));
                  _selectedChannelIdx = channels.length - 1;
                });
                // 初始化该渠道的默认配置
                final cfg = context.read<ConfigProvider>();
                cfg.updateField("channels.${ch['configKey']}.enabled", true);
                Navigator.pop(ctx);
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消"))],
    ));
  }

  void _removeChannel(int index) {
    final ch = channels[index];
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text("删除 ${ch['name']}"),
      content: const Text("确认移除此渠道？对应的配置数据不会被删除，重新添加后可恢复。"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
        FilledButton(
          onPressed: () {
            setState(() {
              channels.removeAt(index);
              if (_selectedChannelIdx >= channels.length) {
                _selectedChannelIdx = channels.isEmpty ? 0 : channels.length - 1;
              }
            });
            Navigator.pop(ctx);
          },
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text("删除"),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF111111) : Colors.white;

    return Row(
      children: [
        // 二级侧边栏
        Container(
          width: 260,
          color: sidebarBg,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("已启用渠道", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    tooltip: "添加渠道",
                    onPressed: () => _addChannel(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: channels.isEmpty
                  ? const Center(child: Text("暂无渠道，点击 + 添加", style: TextStyle(color: Colors.grey, fontSize: 12)))
                  : ListView.builder(
                    itemCount: channels.length,
                    itemBuilder: (context, index) {
                      return Dismissible(
                        key: ValueKey(channels[index]['configKey']),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          _removeChannel(index);
                          return false; // 由对话框控制实际删除
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(color: Colors.red.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.delete, color: Colors.red, size: 20),
                        ),
                        child: _SecondarySidebarItem(
                          icon: channels[index]['icon'] as IconData,
                          title: channels[index]['name'] as String,
                          subtitle: channels[index]['desc'] as String?,
                          isSelected: index == _selectedChannelIdx,
                          onTap: () => setState(() => _selectedChannelIdx = index),
                        ),
                      );
                    },
                  ),
              ),
            ],
          ),
        ),
        
        // 内容详情
        Expanded(
          child: channels.isEmpty
            ? const Center(child: Text("请先添加一个渠道", style: TextStyle(color: Colors.grey)))
            : Column(
              children: [
                _HeaderBar(
                  title: channels[_selectedChannelIdx]['name'] as String, 
                  subtitle: "配置 ${channels[_selectedChannelIdx]['name']} 的连接参数与策略"
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: _buildDetailPanel(),
                  ),
                ),
              ],
            ),
        ),
      ],
    );
  }

  Widget _buildDetailPanel() {
    if (channels.isEmpty) return const SizedBox.shrink();
    final configKey = channels[_selectedChannelIdx]['configKey'] as String;
    switch (configKey) {
      case "whatsapp": return const _WhatsAppConfigView();
      case "telegram": return const _TelegramConfigView();
      case "feishu": return const _FeishuConfigView();
      case "discord": return const _DiscordConfigView();
      case "imessage": return const _IMessageConfigView();
      default: return const Center(child: Text("未知的渠道"));
    }
  }
}

// ==========================================
// 补全：渠道配置详情子页面
// ==========================================

class _WhatsAppConfigView extends StatelessWidget {
  const _WhatsAppConfigView();
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final launcher = context.watch<LauncherProvider>();
    final ws = cfg.config.get("channels.whatsapp") as Map? ?? {};
    return ListView(children: [
      _SectionCard(
          title: "WhatsApp 连接",
          child: Column(children: [
            const Text("点击下方按钮启动登录，并在终端扫码。", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
                icon: const Icon(Icons.qr_code),
                label: const Text("启动登录"),
                onPressed: () => launcher.runCommand("channels login")),
          ])),
      const SizedBox(height: 24),
      _SectionCard(
          title: "策略配置",
          child: Column(children: [
            _SwitchTile(
                title: "启用",
                value: ws["enabled"] ?? true,
                onChanged: (v) => cfg.updateField("channels.whatsapp.enabled", v)),
            const SizedBox(height: 16),
            _EnumDropdown(
                label: "DM 策略",
                value: ws["dmPolicy"] ?? "pairing",
                options: const ["pairing", "allowlist", "open"],
                onChanged: (v) => cfg.updateField("channels.whatsapp.dmPolicy", v)),
            const SizedBox(height: 16),
            _StringListEditor(
                label: "白名单 (AllowFrom)",
                items: ws["allowFrom"] ?? [],
                onChanged: (list) => cfg.updateField("channels.whatsapp.allowFrom", list)),
          ])),
    ]);
  }
}

class _TelegramConfigView extends StatelessWidget {
  const _TelegramConfigView();
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final tg = cfg.config.get("channels.telegram") as Map? ?? {};
    return ListView(children: [
      _SectionCard(
          title: "Bot Token",
          child: _ConfigTextField(
              label: "Token",
              value: tg["botToken"] ?? "",
              isSecret: true,
              onChanged: (v) => cfg.updateField("channels.telegram.botToken", v))),
      const SizedBox(height: 24),
      _SectionCard(
          title: "策略配置",
          child: Column(children: [
            _SwitchTile(
                title: "启用",
                value: tg["enabled"] ?? true,
                onChanged: (v) => cfg.updateField("channels.telegram.enabled", v)),
            const SizedBox(height: 16),
            _StringListEditor(
                label: "允许的用户ID",
                items: tg["allowFrom"] ?? [],
                onChanged: (list) => cfg.updateField("channels.telegram.allowFrom", list)),
          ])),
    ]);
  }
}

class _FeishuConfigView extends StatelessWidget {
  const _FeishuConfigView();
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final fs = cfg.config.get("channels.feishu") as Map? ?? {};
    final acc = (fs["accounts"] as Map? ?? {})["main"] as Map? ?? {};
    return ListView(children: [
      _SectionCard(
          title: "飞书凭证",
          child: Column(children: [
            _ConfigTextField(
                label: "App ID",
                value: acc["appId"] ?? "",
                onChanged: (v) => cfg.updateField("channels.feishu.accounts.main.appId", v)),
            _ConfigTextField(
                label: "App Secret",
                value: acc["appSecret"] ?? "",
                isSecret: true,
                onChanged: (v) =>
                    cfg.updateField("channels.feishu.accounts.main.appSecret", v)),
          ])),
    ]);
  }
}

// ==========================================
// 7. Settings & Others
// ==========================================

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final launcher = context.watch<LauncherProvider>();
    return ListView(padding: const EdgeInsets.all(32), children: [
      _SectionCard(title: "界面偏好", child: SegmentedButton<ThemeMode>(
        segments: const [ButtonSegment(value: ThemeMode.system, label: Text('自动'), icon: Icon(Icons.brightness_auto)), ButtonSegment(value: ThemeMode.light, label: Text('亮色'), icon: Icon(Icons.light_mode)), ButtonSegment(value: ThemeMode.dark, label: Text('深色'), icon: Icon(Icons.dark_mode))],
        selected: {themeProvider.themeMode}, onSelectionChanged: (s) => themeProvider.setThemeMode(s.first),
      )),
      const SizedBox(height: 24),
      _SectionCard(title: "核心管理", child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("当前版本: ${launcher.versionNumber}", style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _BigInstallButton(title: "安装", subtitle: "openclaw.ai", icon: Icons.download, color: Colors.blue, onTap: () => launcher.runSmartInstaller())),
          const SizedBox(width: 16),
          Expanded(child: _BigInstallButton(title: "修复", subtitle: "重新安装核心", icon: Icons.build, color: Colors.orange, onTap: () => launcher.runSmartInstaller())),
          const SizedBox(width: 16),
          Expanded(child: _BigInstallButton(title: "卸载", subtitle: "移除核心程序", icon: Icons.delete_forever, color: Colors.red, onTap: () => launcher.forceClean())),
        ]),
      ])),
    ]);
  }
}

// ==========================================
// 技能管理页面 (SkillsPage)
// ==========================================

class SkillsPage extends StatefulWidget {
  const SkillsPage({super.key});

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  String? _selectedSkillId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cfg = context.read<ConfigProvider>();
      final ws = cfg.config.get("agents.defaults.workspace") ?? "~/.openclaw/workspace";
      context.read<SkillsProvider>().loadSkills(ws);
    });
  }

  @override
  Widget build(BuildContext context) {
    final skillsProvider = context.watch<SkillsProvider>();
    final cfg = context.watch<ConfigProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF111111) : Colors.white;

    // 获取当前选中技能的配置 (从 openclaw.json)
    final skillEntries = cfg.config.get("skills.entries") as Map? ?? {};
    final selectedSkillModel = skillsProvider.skills.firstWhere(
      (s) => s.id == _selectedSkillId, 
      orElse: () => skillsProvider.skills.isNotEmpty ? skillsProvider.skills.first : SkillModel(id: "none", name: "none", description: "", path: "", type: "")
    );
    
    // 如果没有选中，且列表不为空，默认选第一个
    if (_selectedSkillId == null && skillsProvider.skills.isNotEmpty) {
      _selectedSkillId = skillsProvider.skills.first.id;
    }

    final skillConfig = skillEntries[_selectedSkillId] as Map? ?? {};
    final isEnabled = skillConfig["enabled"] ?? true; // 默认为 true (如果未显式禁用)

    return Row(
      children: [
        // 1. 技能列表侧边栏
        Container(
          width: 260,
          color: sidebarBg,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("已安装技能", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16),
                    onPressed: () {
                       final ws = cfg.config.get("agents.defaults.workspace") ?? "~/.openclaw/workspace";
                       skillsProvider.loadSkills(ws);
                    },
                  )
                ],
              ),
              const SizedBox(height: 12),
              if (skillsProvider.isLoading)
                const LinearProgressIndicator(minHeight: 2),
              
              Expanded(
                child: ListView.builder(
                  itemCount: skillsProvider.skills.length,
                  itemBuilder: (context, index) {
                    final skill = skillsProvider.skills[index];
                    final isSel = skill.id == _selectedSkillId;
                    
                    // 检查 config 里的 enabled 状态来改变列表项的透明度或图标
                    final entry = skillEntries[skill.id] as Map? ?? {};
                    final active = entry["enabled"] ?? true;

                    return _SecondarySidebarItem(
                      icon: active ? Icons.extension : Icons.extension_off, // 这里可以用 skill.emoji 替换 Icon
                      title: skill.name,
                      subtitle: skill.type.toUpperCase(), // Workspace / Bundled
                      isSelected: isSel,
                      onTap: () => setState(() => _selectedSkillId = skill.id),
                    );
                  },
                ),
              ),
              // ClawHub 链接
              Container(
                padding: const EdgeInsets.only(top: 16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
                child: InkWell(
                  onTap: () => launchUrl(Uri.parse("https://clawhub.com")),
                  child: const Row(
                    children: [
                      Icon(Icons.storefront, size: 16, color: Colors.blue),
                      SizedBox(width: 8),
                      Text("浏览 ClawHub 市场", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),

        // 2. 技能详情与配置
        Expanded(
          child: skillsProvider.skills.isEmpty 
            ? const Center(child: Text("未找到技能"))
            : Column(
            children: [
              _HeaderBar(
                title: selectedSkillModel.name,
                subtitle: selectedSkillModel.description,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(32),
                  children: [
                    // 状态卡片
                    _SectionCard(
                      title: "状态控制",
                      trailing: Switch(
                        value: isEnabled, 
                        onChanged: (val) {
                          // 写入 openclaw.json: skills.entries.<id>.enabled
                          cfg.updateField("skills.entries.$_selectedSkillId.enabled", val);
                        }
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("来源: ${selectedSkillModel.path}", style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: "Consolas")),
                          const SizedBox(height: 8),
                          if (!isEnabled)
                            const Text("此技能已被禁用，Agent 在运行时将不会看到此工具。", style: TextStyle(color: Colors.orange, fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 环境变量配置
                    _SectionCard(
                      title: "环境注入 (Environment)",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("在此配置技能所需的 API Key 或环境变量。这些变量仅在 Agent 运行时注入。", style: TextStyle(color: Colors.grey, fontSize: 13)),
                          const SizedBox(height: 16),
                          
                          // API Key 快捷方式
                          _ConfigTextField(
                            label: "API Key (apiKey)",
                            value: skillConfig["apiKey"] ?? "",
                            isSecret: true,
                            onChanged: (v) => cfg.updateField("skills.entries.$_selectedSkillId.apiKey", v),
                          ),
                          
                          const Divider(height: 32),
                          const Text("自定义 ENV 变量", style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          
                          // 自定义 Env Map 编辑器
                          _EnvMapEditor(
                            env: Map<String, dynamic>.from(skillConfig["env"] ?? {}),
                            onChanged: (newMap) => cfg.updateField("skills.entries.$_selectedSkillId.env", newMap),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    // 元数据展示
                    _SectionCard(
                      title: "元数据 (Metadata)",
                      child: Text(
                        const JsonEncoder.withIndent('  ').convert(selectedSkillModel.metadata),
                        style: const TextStyle(fontFamily: "Consolas", fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 辅助组件：简单的 Key-Value 编辑器
class _EnvMapEditor extends StatelessWidget {
  final Map<String, dynamic> env;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const _EnvMapEditor({required this.env, required this.onChanged});

  void _addPair(BuildContext context) {
    String key = "";
    String val = "";
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("添加变量"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(decoration: const InputDecoration(labelText: "KEY (e.g. GEMINI_TOKEN)"), onChanged: (v)=>key=v),
          const SizedBox(height: 8),
          TextField(decoration: const InputDecoration(labelText: "VALUE"), onChanged: (v)=>val=v),
        ],
      ),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("取消")),
        FilledButton(onPressed: () {
          if(key.isNotEmpty) {
            final newMap = Map<String, dynamic>.from(env);
            newMap[key] = val;
            onChanged(newMap);
          }
          Navigator.pop(ctx);
        }, child: const Text("添加"))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...env.entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8)
          ),
          child: Row(
            children: [
              Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: "Consolas")),
              const Text(" = "),
              Expanded(child: Text(e.value.toString(), style: const TextStyle(fontFamily: "Consolas"), overflow: TextOverflow.ellipsis)),
              IconButton(
                icon: const Icon(Icons.delete, size: 16),
                onPressed: () {
                  final newMap = Map<String, dynamic>.from(env);
                  newMap.remove(e.key);
                  onChanged(newMap);
                },
              )
            ],
          ),
        )),
        OutlinedButton.icon(
          onPressed: () => _addPair(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text("Add ENV Variable"),
        )
      ],
    );
  }
}

// 日志与文件管理页 (SoulTab - 重构)
// ==========================================

class SoulTab extends StatefulWidget {
  const SoulTab({super.key});

  @override
  State<SoulTab> createState() => _SoulTabState();
}

class _SoulTabState extends State<SoulTab> {
  @override
  void initState() {
    super.initState();
    // 初始化时加载默认工作区文件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FileProvider>().scanWorkspace("~/.openclaw/workspace");
    });
  }

  @override
  Widget build(BuildContext context) {
    final fileProvider = context.watch<FileProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF111111) : Colors.white;

    return Row(
      children: [
        // 文件列表侧边栏
        Container(
          width: 260,
          color: sidebarBg,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("工作区文件", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16), 
                    onPressed: () => fileProvider.scanWorkspace("~/.openclaw/workspace")
                  )
                ],
              ),
              const SizedBox(height: 8),
              if (fileProvider.files.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Text("未找到文件或路径不存在", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: fileProvider.files.length,
                  itemBuilder: (context, index) {
                    final file = fileProvider.files[index] as File;
                    final fileName = p.basename(file.path);
                    final isSel = fileProvider.selectedFile?.path == file.path;
                    
                    return _SecondarySidebarItem(
                      icon: Icons.article_outlined,
                      title: fileName,
                      isSelected: isSel,
                      onTap: () => fileProvider.selectFile(file),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // 文件编辑器
        Expanded(
          child: Column(
            children: [
              _HeaderBar(
                title: fileProvider.selectedFile != null ? p.basename(fileProvider.selectedFile!.path) : "应用日志/配置",
                subtitle: fileProvider.status.isNotEmpty ? fileProvider.status : "查看与编辑 Agent 核心设定文件"
              ),
              Expanded(
                child: fileProvider.selectedFile == null
                    ? const Center(child: Text("请从左侧选择一个文件", style: TextStyle(color: Colors.grey)))
                    : Container(
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? const Color(0xFF333333) : Colors.grey.shade300),
                        ),
                        child: TextField(
                          controller: TextEditingController(text: fileProvider.fileContent)
                            ..selection = TextSelection.collapsed(offset: 0), // 防止重置时光标跳动
                          maxLines: null,
                          expands: true,
                          style: const TextStyle(fontFamily: "Consolas", fontSize: 13, height: 1.4),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (v) {
                             // 简单的防抖保存逻辑可以加在这里，暂时只更新 Provider 状态
                             // fileProvider.updateCache(v); 
                             // 实际保存由 HeaderBar 的 Save 按钮触发
                             fileProvider.fileContent = v;
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


// ==========================================
// 8. 基础组件库
// ==========================================

class _HeaderBar extends StatelessWidget {
  final String title, subtitle;
  const _HeaderBar({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80, padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withAlpha(25))), color: Theme.of(context).scaffoldBackgroundColor),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ]),
        const _SaveButton()
      ]),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton();
  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => context.read<ConfigProvider>().saveConfig(),
      icon: const Icon(Icons.save, size: 16),
      label: const Text("Save"),
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
      decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? const Color(0xFF333333) : Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)), ?trailing]),
        const SizedBox(height: 20),
        child
      ]),
    );
  }
}

class _ConfigTextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool isSecret;
  const _ConfigTextField({required this.label, required this.value, required this.onChanged, this.isSecret = false});
  @override
  State<_ConfigTextField> createState() => _ConfigTextFieldState();
}
class _ConfigTextFieldState extends State<_ConfigTextField> {
  late TextEditingController _ctrl;
  late bool _obscure;
  @override
  void initState() { super.initState(); _ctrl = TextEditingController(text: widget.value); _obscure = widget.isSecret; }
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      const SizedBox(height: 8),
      TextField(controller: _ctrl, obscureText: _obscure, onChanged: widget.onChanged, decoration: InputDecoration(suffixIcon: widget.isSecret ? IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: ()=>setState(()=>_obscure=!_obscure)) : null))
    ]));
  }
}

class _StringListEditor extends StatefulWidget {
  final String label;
  final List<dynamic> items;
  final ValueChanged<List<String>> onChanged;
  const _StringListEditor({required this.label, required this.items, required this.onChanged});
  @override
  State<_StringListEditor> createState() => _StringListEditorState();
}
class _StringListEditorState extends State<_StringListEditor> {
  final TextEditingController _ctrl = TextEditingController();
  void _add() { if (_ctrl.text.isNotEmpty) { widget.onChanged(List<String>.from(widget.items.map((e)=>e.toString()))..add(_ctrl.text)); _ctrl.clear(); } }
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      const SizedBox(height: 8),
      Row(children: [Expanded(child: TextField(controller: _ctrl, decoration: const InputDecoration(hintText: "添加..."))), IconButton(onPressed: _add, icon: const Icon(Icons.add))]),
      Wrap(spacing: 8, children: widget.items.map((e) => Chip(label: Text(e.toString()), onDeleted: () => widget.onChanged(List<String>.from(widget.items.map((x)=>x.toString()))..remove(e)))).toList())
    ]);
  }
}

class _EnumDropdown extends StatelessWidget {
  final String label, value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  const _EnumDropdown({required this.label, required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(initialValue: options.contains(value) ? value : options.first, items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChanged)
    ]);
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({required this.title, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SwitchListTile(title: Text(title), value: value, onChanged: onChanged, contentPadding: EdgeInsets.zero);
}

class _BigInstallButton extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BigInstallButton({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF252525) : Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300)),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Icon(icon, size: 32, color: color), const SizedBox(height: 8), Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)), Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey))
      ]))),
    );
  }
}

// ==========================================
// 新增组件：二级侧边栏胶囊选项 (Capsule Style)
// ==========================================
class _SecondarySidebarItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _SecondarySidebarItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // 颜色逻辑：
    // 选中：主题色 (蓝色)
    // 未选中：深色模式下为 0xFF252525 (深灰)，亮色模式下为 Grey[200]
    final bgColor = isSelected
        ? theme.colorScheme.primary
        : (isDark ? const Color(0xFF252525) : Colors.grey.shade200);

    final fgColor = isSelected
        ? Colors.white
        : (isDark ? Colors.grey.shade400 : Colors.grey.shade700);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12), // 圆角胶囊
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 18, color: fgColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: fgColor,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            // ignore: deprecated_member_use
                            color: fgColor.withOpacity(0.7),
                            fontSize: 10,
                          ),
                        )
                      ]
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 新增：Discord 配置视图
// ==========================================
class _DiscordConfigView extends StatelessWidget {
  const _DiscordConfigView();

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final discord = cfg.config.get("channels.discord") as Map? ?? {};
    final dm = discord["dm"] as Map? ?? {};

    return ListView(
      children: [
        _SectionCard(
          title: "Bot 认证",
          child: Column(
            children: [
              const Text(
                "请确保在 Discord Developer Portal 开启了 'Message Content Intent'。",
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
              const SizedBox(height: 12),
              _ConfigTextField(
                label: "Bot Token",
                value: discord["token"] ?? "",
                isSecret: true,
                onChanged: (v) => cfg.updateField("channels.discord.token", v),
              ),
              const SizedBox(height: 8),
              _SwitchTile(
                title: "启用 Discord 渠道",
                value: discord["enabled"] ?? true,
                onChanged: (v) => cfg.updateField("channels.discord.enabled", v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "私聊策略 (Direct Messages)",
          child: Column(
            children: [
               _SwitchTile(
                title: "允许私聊",
                value: dm["enabled"] ?? true,
                onChanged: (v) => cfg.updateField("channels.discord.dm.enabled", v),
              ),
              const SizedBox(height: 16),
              _EnumDropdown(
                label: "验证策略",
                value: dm["policy"] ?? "pairing",
                options: const ["pairing", "allowlist", "open", "disabled"],
                onChanged: (v) => cfg.updateField("channels.discord.dm.policy", v),
              ),
              const SizedBox(height: 8),
              const Text(
                "pairing: 首次对话需验证码; allowlist: 仅允许白名单用户; open: 开放所有 (不推荐)",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _StringListEditor(
                label: "用户白名单 (AllowFrom User IDs)",
                items: dm["allowFrom"] ?? [],
                onChanged: (list) => cfg.updateField("channels.discord.dm.allowFrom", list),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "高级设置",
          child: Column(
            children: [
              _ConfigTextField(
                label: "媒体上传限制 (MB)",
                value: (discord["mediaMaxMb"] ?? 8).toString(),
                onChanged: (v) => cfg.updateField("channels.discord.mediaMaxMb", int.tryParse(v) ?? 8),
              ),
              const SizedBox(height: 16),
              _ConfigTextField(
                 label: "分段长度限制 (Characters)",
                 value: (discord["textChunkLimit"] ?? 2000).toString(),
                 onChanged: (v) => cfg.updateField("channels.discord.textChunkLimit", int.tryParse(v) ?? 2000),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==========================================
// 新增：iMessage 配置视图
// ==========================================
class _IMessageConfigView extends StatelessWidget {
  const _IMessageConfigView();

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final imsg = cfg.config.get("channels.imessage") as Map? ?? {};
    
    return ListView(
      children: [
        _SectionCard(
          title: "本地环境配置 (macOS)",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "需要 'imsg' 命令行工具及 '完全磁盘访问权限' 读取 chat.db。",
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
              const SizedBox(height: 16),
              _ConfigTextField(
                label: "CLI 路径 (cliPath)",
                value: imsg["cliPath"] ?? "/usr/local/bin/imsg",
                onChanged: (v) => cfg.updateField("channels.imessage.cliPath", v),
              ),
              _ConfigTextField(
                label: "数据库路径 (dbPath)",
                value: imsg["dbPath"] ?? "~/Library/Messages/chat.db",
                onChanged: (v) => cfg.updateField("channels.imessage.dbPath", v),
              ),
              _SwitchTile(
                title: "启用 iMessage",
                value: imsg["enabled"] ?? true,
                onChanged: (v) => cfg.updateField("channels.imessage.enabled", v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "远程连接 (可选)",
          child: Column(
            children: [
              const Text(
                "如果通过 SSH 连接远程 Mac (如 Tailscale)，请配置主机地址。",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              _ConfigTextField(
                label: "远程主机 (User@Host)",
                value: imsg["remoteHost"] ?? "",
                onChanged: (v) => cfg.updateField("channels.imessage.remoteHost", v),
              ),
              _SwitchTile(
                title: "自动同步附件 (SCP)",
                value: imsg["includeAttachments"] ?? false,
                onChanged: (v) => cfg.updateField("channels.imessage.includeAttachments", v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "策略配置",
          child: Column(
            children: [
              _EnumDropdown(
                label: "DM 策略",
                value: imsg["dmPolicy"] ?? "pairing",
                options: const ["pairing", "allowlist", "open", "disabled"],
                onChanged: (v) => cfg.updateField("channels.imessage.dmPolicy", v),
              ),
              const SizedBox(height: 16),
              _StringListEditor(
                label: "允许的 Handle (Email/Phone)",
                items: imsg["allowFrom"] ?? [],
                onChanged: (list) => cfg.updateField("channels.imessage.allowFrom", list),
              ),
            ],
          ),
        ),
      ],
    );
  }
}