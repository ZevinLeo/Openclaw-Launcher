// ignore_for_file: unused_field, use_null_aware_elements, unused_element_parameter, unused_local_variable, unnecessary_import, avoid_print

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
// 1. 程序入口 & 主题系统 (重构)
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
        ChangeNotifierProvider(create: (_) => SkillsProvider()),
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
    
    // OpenList-Desktop 风格的颜色
    const accentColor = Color(0xFF3B82F6);      // 蓝色强调色
    const accentHover = Color(0xFF2563EB);     // 悬停蓝色
    const surfaceColor = Color(0xFF18181B);    // 深色背景
    const cardColor = Color(0xFF27272A);        // 卡片背景
    const borderColor = Color(0xFF3F3F46);      // 边框色
    const textPrimary = Color(0xFFFAFAFA);      // 主文字
    const textSecondary = Color(0xFF71717A);   // 次要文字

    return MaterialApp(
      title: 'OpenClaw Manager',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      
      // 亮色主题
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F4F5),
        cardColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentColor, 
          brightness: Brightness.light
        ),
        fontFamily: Platform.isWindows ? 'Microsoft YaHei UI' : null,
      ),

      // 深色主题 - OpenList-Desktop 风格
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: surfaceColor,
        cardColor: cardColor,
        colorScheme: const ColorScheme.dark(
          primary: accentColor,
          secondary: accentColor,
          surface: surfaceColor,
          outline: borderColor,
        ),
        fontFamily: Platform.isWindows ? 'Microsoft YaHei UI' : null,
        dividerColor: borderColor,
        
        // 卡片样式
        cardTheme: CardThemeData(
          color: cardColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: borderColor, width: 1),
          ),
        ),
        
        // 输入框样式
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: accentColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        
        // 按钮样式
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        
        // 文字样式
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: textPrimary),
          bodyMedium: TextStyle(color: textPrimary),
          bodySmall: TextStyle(color: textSecondary),
          titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
          labelLarge: TextStyle(color: textSecondary),
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
  DateTime? _serviceStartTime;
  int totalTokensUsed = 0;
  
  // 运行时长格式化
  String get uptime {
    if (_serviceStartTime == null) return "--";
    final d = DateTime.now().difference(_serviceStartTime!);
    if (d.inHours > 0) return "${d.inHours}h ${d.inMinutes % 60}m";
    if (d.inMinutes > 0) return "${d.inMinutes}m ${d.inSeconds % 60}s";
    return "${d.inSeconds}s";
  }

  String tokenUsageDisplay = "--";  // 用于显示的 token 用量文本
  String currentModelDisplay = "--"; // 当前使用的模型

  // 刷新 token 使用量（调用 openclaw status --usage）
  Future<void> refreshTokenUsage() async {
    if (cliCmd == null || !isGatewayRunning) {
      tokenUsageDisplay = "--";
      currentModelDisplay = "--";
      notifyListeners();
      return;
    }
    try {
      final res = await Process.run(
        'openclaw',
        ['status', '--json'],
        runInShell: true,
      );
      final output = res.stdout.toString();
      _parseJsonStatus(output);
      if (tokenUsageDisplay != "--") {
        addLog("Token: $tokenUsageDisplay | Model: $currentModelDisplay", type: "SUCCESS");
      }
    } catch (e) {
      addLog("Token 查询异常: $e", type: "ERROR");
    }
    notifyListeners();
  }

  void _parseJsonStatus(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final sessions = data['sessions'];
      if (sessions == null) return;
      
      final defaults = sessions['defaults'];
      if (defaults != null && defaults['model'] != null) {
        final model = defaults['model'].toString();
        final parts = model.split('/');
        currentModelDisplay = parts.length > 1 ? parts.last : model;
      }
      
      int totalInput = 0;
      int totalOutput = 0;
      final recent = sessions['recent'] as List?;
      if (recent != null) {
        for (var session in recent) {
          final input = session['inputTokens'];
          final output = session['outputTokens'];
          if (input is int) totalInput += input;
          if (output is int) totalOutput += output;
        }
      }
      
      final totalTokens = totalInput + totalOutput;
      if (totalTokens > 0) {
        tokenUsageDisplay = totalTokens >= 1000000
            ? "${(totalTokens / 1000000).toStringAsFixed(1)}M"
            : "${(totalTokens / 1000).toStringAsFixed(1)}K";
      } else {
        tokenUsageDisplay = "--";
      }
    } catch (e) {
      addLog("JSON 解析异常: $e", type: "ERROR");
    }
  }
  
  List<LogEntry> logs = [];
  final ScrollController logScrollCtrl = ScrollController();

  LauncherProvider() {
    _initFullCheck();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
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
    
    bool gatewayAlreadyRunning = await _waitForGatewayHttp();
    if (gatewayAlreadyRunning && !isGatewayRunning) {
      isGatewayRunning = true;
      _serviceStartTime = DateTime.now();
      addLog("检测到 Gateway 已在运行中", type: "INFO");
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
        final regex = RegExp(r"v?(\d+\.\d+\.\d+[-.\w]*)");
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
          addLog("发现新版本！可点击「立即更新」执行 openclaw update。", type: "INFO");
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

  Future<void> updateCore() async {
    if (cliCmd == null) {
      addLog("核心未安装，无法更新。", type: "ERROR");
      return;
    }
    addLog(">>> 正在执行 $cliCmd update ...", type: "CMD");
    try {
      final process = await Process.start(cliCmd!, ['update'], runInShell: true);
      _monitorStream(process.stdout, "Update");
      _monitorStream(process.stderr, "Update", isError: true);
      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        addLog("更新完成。", type: "SUCCESS");
      } else {
        addLog("更新进程退出，代码: $exitCode", type: "ERROR");
      }
      addLog("正在刷新版本状态...", type: "INFO");
      await _initFullCheck();
    } catch (e) {
      addLog("更新失败: $e", type: "ERROR");
    }
  }

  Future<void> startServices() async {
    if (cliCmd == null) {
      addLog("错误: 未找到核心程序，无法启动。", type: "ERROR");
      return;
    }
    if (isGatewayRunning) return;

    bool alreadyRunning = await _waitForGatewayHttp();
    if (alreadyRunning) {
      addLog("Gateway 已在运行中，直接使用", type: "INFO");
      isGatewayRunning = true;
      _serviceStartTime = DateTime.now();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 500));
      await _startNode();
      return;
    }

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
      _serviceStartTime = DateTime.now();
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
        // 完全启动后刷新 token 用量
        refreshTokenUsage();
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
    _serviceStartTime = null;
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
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        String type;
        if (!isError) {
          type = "INFO";
        } else {
          // stderr 内容智能分类：只有真正的错误才标红
          final lower = trimmed.toLowerCase();
          if (lower.contains("error") || lower.contains("fatal") || lower.contains("exception") || lower.contains("failed to")) {
            type = "ERROR";
          } else {
            type = "WARN";
          }
        }
        addLog(trimmed, type: type);
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
    try {
      final process = await Process.start(cliCmd!, args.split(" "), runInShell: true);
      _monitorStream(process.stdout, "CMD");
      _monitorStream(process.stderr, "CMD", isError: true);
    } catch (e) {
      addLog("执行失败: $e", type: "ERROR");
    }
  }

  /// 通用 shell 命令执行（终端输入框使用）
  Future<void> executeShellCommand(String command) async {
    if (command.trim().isEmpty) return;
    addLog("\$ $command", type: "CMD");
    try {
      final process = await Process.start(
        Platform.isWindows ? 'cmd' : 'sh',
        Platform.isWindows ? ['/c', command] : ['-c', command],
        runInShell: false,
      );
      _monitorStream(process.stdout, "Shell");
      _monitorStream(process.stderr, "Shell", isError: true);
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        addLog("进程退出，代码: $exitCode", type: "ERROR");
      }
    } catch (e) {
      addLog("命令执行失败: $e", type: "ERROR");
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
    "auth": {"profiles": {}},
    "agents": {"defaults": {"workspace": "~/.openclaw/workspace", "model": {"primary": ""}, "models": {}, "compaction": {"mode": "safeguard"}}, "list": [{"id": "main", "name": "Default"}]},
    "messages": {"tts": {"auto": "off", "provider": "elevenlabs"}},
    "channels": {
      "whatsapp": {"enabled": true, "dmPolicy": "pairing", "allowFrom": [], "groupPolicy": "allowlist", "groupAllowFrom": [], "groups": {"*": {"requireMention": true}}},
      "telegram": {"enabled": true, "botToken": "", "allowFrom": [], "groupPolicy": "allowlist", "groupAllowFrom": [], "groups": {"*": {"requireMention": true}}},
      "feishu": {"enabled": false, "domain": "feishu", "accounts": {"main": {"appId": "", "appSecret": ""}}, "dmPolicy": "pairing"},
      "discord": {"enabled": false, "token": "", "dm": {"enabled": true, "allowFrom": []}, "guilds": {}},
      "slack": {"enabled": false, "botToken": "", "appToken": "", "channels": {}, "dm": {"enabled": true, "allowFrom": []}, "slashCommand": {"enabled": true, "name": "openclaw", "ephemeral": true}},
      "imessage": {"enabled": false, "cliPath": "/usr/local/bin/imsg", "dbPath": "~/Library/Messages/chat.db", "allowFrom": []}
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
  Map<String, dynamic> authProfiles = {};  // 从 auth-profiles.json 加载
  String _statusMessage = "Ready";
  late File _configFile;
  late File _authFile;
  String get statusMessage => _statusMessage;
  ConfigProvider() { _init(); }
  String get _homePath => Platform.environment[Platform.isWindows ? 'UserProfile' : 'HOME'] ?? '.';
  Future<void> _init() async {
    final dir = Directory(p.join(_homePath, '.openclaw'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _configFile = File(p.join(dir.path, 'openclaw.json'));
    _authFile = File(p.join(dir.path, 'agents', 'main', 'agent', 'auth-profiles.json'));
    await loadConfig();
    await loadAuthProfiles();
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

  // === Auth Profiles (auth-profiles.json) ===
  Future<void> loadAuthProfiles() async {
    try {
      if (await _authFile.exists()) {
        final data = jsonDecode(await _authFile.readAsString());
        authProfiles = Map<String, dynamic>.from(data["profiles"] as Map? ?? {});
      }
    } catch (e) { _statusMessage = "加载认证配置失败"; }
    notifyListeners();
  }

  Future<void> saveAuthProfiles() async {
    try {
      // 读取原始文件保留 lastGood 和 usageStats
      Map<String, dynamic> fullData = {"version": 1, "profiles": {}, "lastGood": {}, "usageStats": {}};
      if (await _authFile.exists()) {
        fullData = Map<String, dynamic>.from(jsonDecode(await _authFile.readAsString()));
      }
      fullData["profiles"] = authProfiles;
      // 更新 lastGood
      final lastGood = Map<String, dynamic>.from(fullData["lastGood"] as Map? ?? {});
      for (var key in authProfiles.keys) {
        final parts = key.split(":");
        if (parts.length == 2) lastGood[parts[0]] = key;
      }
      fullData["lastGood"] = lastGood;
      await _authFile.writeAsString(const JsonEncoder.withIndent('  ').convert(fullData));
      _statusMessage = "认证配置已保存";
    } catch (e) { _statusMessage = "保存认证配置失败: $e"; }
    notifyListeners();
  }

  void addAuthProfile(String key, Map<String, dynamic> profile) {
    authProfiles[key] = profile;
    saveAuthProfiles();
  }

  void removeAuthProfile(String key) {
    authProfiles.remove(key);
    saveAuthProfiles();
  }

  void updateAuthProfile(String key, Map<String, dynamic> profile) {
    authProfiles[key] = profile;
    saveAuthProfiles();
  }
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
// 2. 主布局 (OpenList-Desktop 风格)
// ==========================================

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    const accentColor = Color(0xFF3B82F6);
    const surfaceColor = Color(0xFF18181B);
    const cardColor = Color(0xFF27272A);
    const borderColor = Color(0xFF3F3F46);
    const textSecondary = Color(0xFF71717A);
    
    // 页面路由
    final pages = [
      const DashboardPage(),
      const AIConfigPage(),
      const ChannelsPage(),
      const SkillsPage(),
      const SoulTab(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: Row(
        children: [
          // 一级侧边栏 - OpenList 风格
          Container(
            width: 220,
            decoration: BoxDecoration(
              color: isDark ? surfaceColor : Colors.white,
              border: Border(
                right: BorderSide(color: isDark ? borderColor : Colors.grey.shade200),
              ),
            ),
            child: Column(
              children: [
                // Logo Area
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.smart_toy, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("OpenClaw", style: TextStyle(
                            fontSize: 15, 
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          )),
                          Text("Manager", style: TextStyle(
                            fontSize: 10, 
                            color: textSecondary,
                          )),
                        ],
                      )
                    ],
                  ),
                ),
                
                const Divider(height: 1),
                
                // Navigation Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _NavItem(icon: Icons.dashboard_rounded, label: "仪表盘", index: 0, isSelected: nav.selectedIndex == 0),
                      _NavItem(icon: Icons.smart_toy_outlined, label: "AI 配置", index: 1, isSelected: nav.selectedIndex == 1),
                      _NavItem(icon: Icons.chat_bubble_outline_rounded, label: "消息渠道", index: 2, isSelected: nav.selectedIndex == 2),
                      _NavItem(icon: Icons.extension_outlined, label: "技能管理", index: 3, isSelected: nav.selectedIndex == 3),
                      _NavItem(icon: Icons.description_outlined, label: "应用日志", index: 4, isSelected: nav.selectedIndex == 4),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Divider(height: 1),
                      ),
                      _NavItem(icon: Icons.settings_outlined, label: "设置", index: 5, isSelected: nav.selectedIndex == 5),
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
            child: Container(
              color: isDark ? surfaceColor : const Color(0xFFF4F4F5),
              child: pages[nav.selectedIndex],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool isSelected;

  const _NavItem({required this.icon, required this.label, required this.index, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const accentColor = Color(0xFF3B82F6);
    const borderColor = Color(0xFF3F3F46);
    const textSecondary = Color(0xFF71717A);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => context.read<NavigationProvider>().setIndex(index),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected 
                ? accentColor.withAlpha(25) 
                : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: isSelected ? accentColor : textSecondary),
                const SizedBox(width: 12),
                Text(label, style: TextStyle(
                  color: isSelected ? accentColor : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                )),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    width: 3, height: 16,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ],
            ),
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
    const borderColor = Color(0xFF3F3F46);
    const textSecondary = Color(0xFF71717A);
    const accentColor = Color(0xFF3B82F6);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? borderColor : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: isRunning ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isRunning ? "服务运行中" : "服务未启动", style: TextStyle(color: textSecondary, fontSize: 12)),
                Text("端口: ${launcher.currentPort}", style: TextStyle(color: textSecondary.withAlpha(180), fontSize: 10)),
              ],
            ),
          ),
          if (!isRunning)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text("离线", style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. Dashboard (主页) - 重新设计
// ==========================================

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final TextEditingController _cmdController = TextEditingController();
  final FocusNode _cmdFocus = FocusNode();
  final List<String> _cmdHistory = [];
  int _cmdHistoryIdx = -1;
  Timer? _uptimeTimer;
  Timer? _tokenTimer;

  @override
  void initState() {
    super.initState();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _tokenTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (mounted) context.read<LauncherProvider>().refreshTokenUsage();
    });
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    _tokenTimer?.cancel();
    _cmdController.dispose();
    _cmdFocus.dispose();
    super.dispose();
  }

  void _submitCommand(LauncherProvider launcher) {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;
    _cmdHistory.insert(0, cmd);
    _cmdHistoryIdx = -1;
    _cmdController.clear();
    
    if (cmd == "clear" || cmd == "cls") {
      launcher.clearLogs();
      return;
    }
    launcher.executeShellCommand(cmd);
  }

  void _navigateHistory(bool up) {
    if (_cmdHistory.isEmpty) return;
    if (up) {
      if (_cmdHistoryIdx < _cmdHistory.length - 1) _cmdHistoryIdx++;
    } else {
      if (_cmdHistoryIdx > 0) {
        _cmdHistoryIdx--;
      } else {
        _cmdHistoryIdx = -1;
        _cmdController.clear();
        return;
      }
    }
    if (_cmdHistoryIdx >= 0 && _cmdHistoryIdx < _cmdHistory.length) {
      _cmdController.text = _cmdHistory[_cmdHistoryIdx];
      _cmdController.selection = TextSelection.fromPosition(TextPosition(offset: _cmdController.text.length));
    }
  }

  void _openTerminal() async {
    if (Platform.isWindows) {
      await Process.start('cmd.exe', [], mode: ProcessStartMode.normal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final launcher = context.watch<LauncherProvider>();
    final isRunning = launcher.isGatewayRunning;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accentColor = Color(0xFF3B82F6);
    const borderColor = Color(0xFF3F3F46);
    const cardColor = Color(0xFF27272A);
    const surfaceColor = Color(0xFF18181B);

    final hasUpdate = launcher.remoteVersion.isNotEmpty && launcher.remoteVersion != launcher.versionNumber;

    return Column(
      children: [
        _HeaderBar(title: "仪表盘", subtitle: "管理 OpenClaw 服务与监控"),
        
        // 上半区
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Column(
            children: [
              // ===== 1. 核心管理 (最上侧) =====
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? cardColor : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? borderColor : Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.settings_applications, size: 18, color: accentColor),
                        const SizedBox(width: 8),
                        Text("核心管理", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // 启动按钮
                        _CoreActionBtn(
                          label: "启动",
                          icon: Icons.play_arrow,
                          color: const Color(0xFF22C55E),
                          onTap: isRunning ? null : () => launcher.startServices(),
                        ),
                        const SizedBox(width: 12),
                        // 停止按钮
                        _CoreActionBtn(
                          label: "停止",
                          icon: Icons.stop,
                          color: Colors.red,
                          onTap: !isRunning ? null : () => launcher.stopAll(),
                        ),
                        const SizedBox(width: 12),
                        // WebUI 按钮
                        _CoreActionBtn(
                          label: "WebUI",
                          icon: Icons.language,
                          color: Colors.orange,
                          onTap: isRunning ? () => launcher.openWebUI() : null,
                        ),
                        const SizedBox(width: 12),
                        // 重启按钮
                        _CoreActionBtn(
                          label: "重启",
                          icon: Icons.refresh,
                          color: Colors.purple,
                          onTap: () {
                            launcher.stopAll();
                            Future.delayed(const Duration(seconds: 2), () => launcher.startServices());
                          },
                        ),
                        const SizedBox(width: 12),
                        // 打开 CMD 按钮
                        _CoreActionBtn(
                          label: "CMD",
                          icon: Icons.terminal,
                          color: Colors.blueGrey,
                          onTap: _openTerminal,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ===== 2. 左模块(核心监控) + 右模块(版本管理) =====
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 左模块 - 核心监控
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 200,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? cardColor : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? borderColor : Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.monitor_heart, size: 18, color: accentColor),
                              const SizedBox(width: 8),
                              Text("核心监控", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                              const Spacer(),
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  color: isRunning ? Colors.green : Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(isRunning ? "运行中" : "已停止", style: TextStyle(fontSize: 12, color: isRunning ? Colors.green : Colors.red, fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // 监控指标
                          Row(
                            children: [
                              Expanded(child: _MonitorItem(icon: Icons.bolt, label: "端口", value: launcher.currentPort)),
                              const SizedBox(width: 16),
                              Expanded(child: _MonitorItem(icon: Icons.memory, label: "进程ID", value: launcher.currentPid)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: _MonitorItem(icon: Icons.timer_outlined, label: "运行时间", value: launcher.uptime)),
                              const SizedBox(width: 16),
                              Expanded(child: _MonitorItem(icon: Icons.token, label: "已用Tokens", value: launcher.tokenUsageDisplay)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 右模块 - 版本管理
Expanded(
                    flex: 2,
                    child: Container(
                      height: 200,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentColor.withAlpha(50)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.smart_toy, size: 18, color: accentColor),
                              const SizedBox(width: 8),
                              Text("OpenClaw", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 18),
                                color: Colors.grey,
                                tooltip: "检测更新",
                                onPressed: () => launcher.checkForUpdates(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text("V${launcher.versionNumber}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                              ),
                              if (hasUpdate) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text("NEW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: _ActionButton(
                              icon: Icons.system_update,
                              label: hasUpdate ? "更新到 V${launcher.remoteVersion}" : "已是最新版本",
                              color: hasUpdate ? accentColor : Colors.grey,
                              onTap: hasUpdate ? () => launcher.updateCore() : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ===== 3. 实时日志 (最下面) =====
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF333333) : Colors.grey.shade400),
            ),
            child: Column(
              children: [
                // 终端标题栏
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161616) : const Color(0xFF2D2D2D),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.terminal, size: 14, color: Colors.grey),
                      const SizedBox(width: 8),
                      const Text("实时日志", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      SizedBox(
                        height: 24,
                        child: TextButton.icon(
                          onPressed: () => launcher.clearLogs(),
                          icon: const Icon(Icons.delete_sweep, size: 13),
                          label: const Text("清空", style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(foregroundColor: Colors.grey, padding: const EdgeInsets.symmetric(horizontal: 8)),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          final allLogs = launcher.logs.map((l) => "[${l.time}] ${l.message}").join("\n");
                          Clipboard.setData(ClipboardData(text: allLogs));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("日志已复制"), duration: Duration(seconds: 1)));
                        },
                        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.copy_all, size: 14, color: Colors.grey)),
                      ),
                    ],
                  ),
                ),
                // 日志内容
                Expanded(
                  child: SelectionArea(
                    child: ListView.builder(
                      controller: launcher.logScrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: launcher.logs.length,
                      itemBuilder: (ctx, i) {
                        final log = launcher.logs[i];
                        Color c = const Color(0xFFCCCCCC);
                        if (log.type == "ERROR") c = const Color(0xFFFF6B6B);
                        if (log.type == "WARN") c = const Color(0xFFFFD43B);
                        if (log.type == "SUCCESS") c = const Color(0xFF69DB7C);
                        if (log.type == "CMD") c = const Color(0xFF74C0FC);
                        if (log.type == "DEBUG") c = const Color(0xFF868E96);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: Text("[${log.time}] ${log.message}", style: TextStyle(color: c, fontFamily: "Consolas", fontSize: 12, height: 1.5)),
                        );
                      },
                    ),
                  ),
                ),
                // 命令输入框
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161616) : const Color(0xFF2D2D2D),
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
                    border: Border(top: BorderSide(color: isDark ? const Color(0xFF333333) : Colors.grey.shade600)),
                  ),
                  child: Row(
                    children: [
                      const Text("\$ ", style: TextStyle(color: Color(0xFF69DB7C), fontFamily: "Consolas", fontSize: 13, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: KeyboardListener(
                          focusNode: FocusNode(),
                          onKeyEvent: (event) {
                            if (event is KeyDownEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.arrowUp) _navigateHistory(true);
                              else if (event.logicalKey == LogicalKeyboardKey.arrowDown) _navigateHistory(false);
                            }
                          },
                          child: TextField(
                            controller: _cmdController,
                            focusNode: _cmdFocus,
                            style: const TextStyle(color: Colors.white, fontFamily: "Consolas", fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: "输入命令...",
                              hintStyle: TextStyle(color: Color(0xFF555555), fontFamily: "Consolas", fontSize: 13),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                              fillColor: Colors.transparent,
                              filled: true,
                            ),
                            onSubmitted: (_) { _submitCommand(launcher); _cmdFocus.requestFocus(); },
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () { _submitCommand(launcher); _cmdFocus.requestFocus(); },
                        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.send, size: 16, color: Color(0xFF69DB7C))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// 核心管理按钮
class _CoreActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _CoreActionBtn({required this.label, required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(50)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 统一操作按钮组件
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(50)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 监控指标项
class _MonitorItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MonitorItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 13, color: Colors.grey)),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
        ],
      ),
    );
  }
}

// 日志内容区（可滚动 + 可选择复制）
class _LogView extends StatelessWidget {
  const _LogView();

  @override
  Widget build(BuildContext context) {
    final launcher = context.watch<LauncherProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SelectionArea(
      child: ListView.builder(
        controller: launcher.logScrollCtrl,
        padding: const EdgeInsets.all(16),
        itemCount: launcher.logs.length,
        itemBuilder: (ctx, i) {
          final log = launcher.logs[i];
          Color c = const Color(0xFFCCCCCC);
          if (log.type == "ERROR") c = const Color(0xFFFF6B6B);
          if (log.type == "WARN") c = const Color(0xFFFFD43B);
          if (log.type == "SUCCESS") c = const Color(0xFF69DB7C);
          if (log.type == "CMD") c = const Color(0xFF74C0FC);
          if (log.type == "DEBUG") c = const Color(0xFF868E96);
          return Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text("[${log.time}] ${log.message}", style: TextStyle(color: c, fontFamily: "Consolas", fontSize: 12, height: 1.5)),
          );
        },
      ),
    );
  }
}

// 命令输入框
class _CommandInput extends StatefulWidget {
  const _CommandInput();
  
  @override
  State<_CommandInput> createState() => _CommandInputState();
}

class _CommandInputState extends State<_CommandInput> {
  final _cmdController = TextEditingController();
  final _cmdFocus = FocusNode();
  final List<String> _cmdHistory = [];
  int _cmdHistoryIdx = -1;
  
  void _submitCommand(LauncherProvider launcher) {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;
    _cmdHistory.insert(0, cmd);
    _cmdHistoryIdx = -1;
    _cmdController.clear();
    if (cmd == "clear" || cmd == "cls") {
      launcher.clearLogs();
      return;
    }
    launcher.executeShellCommand(cmd);
  }
  
  void _navigateHistory(bool up) {
    if (_cmdHistory.isEmpty) return;
    if (up) {
      if (_cmdHistoryIdx < _cmdHistory.length - 1) _cmdHistoryIdx++;
    } else {
      if (_cmdHistoryIdx > 0) _cmdHistoryIdx--;
      else { _cmdHistoryIdx = -1; _cmdController.clear(); return; }
    }
    if (_cmdHistoryIdx >= 0 && _cmdHistoryIdx < _cmdHistory.length) {
      _cmdController.text = _cmdHistory[_cmdHistoryIdx];
      _cmdController.selection = TextSelection.fromPosition(TextPosition(offset: _cmdController.text.length));
    }
  }
  
  @override
  void dispose() {
    _cmdController.dispose();
    _cmdFocus.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final launcher = context.watch<LauncherProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : const Color(0xFF2D2D2D),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF333333) : Colors.grey.shade600)),
      ),
      child: Row(
        children: [
          const Text("\$ ", style: TextStyle(color: Color(0xFF69DB7C), fontFamily: "Consolas", fontSize: 13, fontWeight: FontWeight.bold)),
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) _navigateHistory(true);
                  else if (event.logicalKey == LogicalKeyboardKey.arrowDown) _navigateHistory(false);
                }
              },
              child: TextField(
                controller: _cmdController,
                focusNode: _cmdFocus,
                style: const TextStyle(color: Colors.white, fontFamily: "Consolas", fontSize: 13),
                decoration: const InputDecoration(
                  hintText: "输入命令...",
                  hintStyle: TextStyle(color: Color(0xFF555555), fontFamily: "Consolas", fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                  fillColor: Colors.transparent,
                  filled: true,
                ),
                onSubmitted: (_) { _submitCommand(launcher); _cmdFocus.requestFocus(); },
              ),
            ),
          ),
          InkWell(
            onTap: () { _submitCommand(launcher); _cmdFocus.requestFocus(); },
            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.send, size: 16, color: Color(0xFF69DB7C))),
          ),
        ],
      ),
    );
  }
}
class _TokenStatusItem extends StatelessWidget {
  final String value;
  const _TokenStatusItem({required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accentColor = Color(0xFF3B82F6);
    const borderColor = Color(0xFF3F3F46);
    const cardColor = Color(0xFF27272A);
    
    return Tooltip(
      message: "数据每 10 分钟自动更新一次\n由 openclaw status --usage 提供",
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? cardColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? borderColor : Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.token, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              const Text("已用 Tokens", style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(width: 4),
              const Icon(Icons.help_outline, size: 12, color: Colors.grey),
            ]),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
      ),
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
    const borderColor = Color(0xFF3F3F46);
    const cardColor = Color(0xFF27272A);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? cardColor : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? borderColor : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
        ],
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
    const accentColor = Color(0xFF3B82F6);
    const borderColor = Color(0xFF3F3F46);
    const cardColor = Color(0xFF27272A);
    
    // 使用新风格: 边框卡片样式
    final bgColor = color ?? (isDark ? cardColor : Colors.white);
    
    return SizedBox(
      width: 130,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1.0,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 88,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? borderColor : Colors.grey.shade200,
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(label, style: TextStyle(color: iconColor, fontSize: 13, fontWeight: FontWeight.w500)),
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
// 5. AI 配置页面 (基于 OpenClaw 文档重构)
// ==========================================

// --- 支持的 Provider 预设 ---
const _providerPresets = <String, Map<String, String>>{
  "openrouter":  {"name": "OpenRouter",  "base": "https://openrouter.ai/api/v1",  "api": "openai-completions"},
  "openai":      {"name": "OpenAI",      "base": "https://api.openai.com/v1",     "api": "openai-completions"},
  "anthropic":   {"name": "Anthropic",   "base": "https://api.anthropic.com",      "api": "anthropic-messages"},
  "deepseek":    {"name": "DeepSeek",    "base": "https://api.deepseek.com/v1",   "api": "openai-completions"},
  "moonshot":    {"name": "Moonshot",    "base": "https://api.moonshot.cn/v1",    "api": "openai-completions"},
  "minimax":     {"name": "Minimax",     "base": "https://api.minimax.chat/v1",   "api": "openai-completions"},
  "mistral":     {"name": "Mistral",     "base": "https://api.mistral.ai/v1",     "api": "openai-completions"},
  "gemini":      {"name": "Gemini",      "base": "https://generativelanguage.googleapis.com/v1beta", "api": "openai-completions"},
  "together":    {"name": "Together",    "base": "https://api.together.xyz/v1",   "api": "openai-completions"},
  "xai":         {"name": "xAI",         "base": "https://api.x.ai/v1",           "api": "openai-completions"},
  "huggingface": {"name": "HuggingFace", "base": "https://api-inference.huggingface.co/v1", "api": "openai-completions"},
  "custom":      {"name": "Custom",      "base": "",                               "api": "openai-completions"},
};

class AIConfigPage extends StatefulWidget {
  const AIConfigPage({super.key});
  @override
  State<AIConfigPage> createState() => _AIConfigPageState();
}

class _AIConfigPageState extends State<AIConfigPage> {
  // 选中项: "core" | "auth:profileKey" | "models"
  String _selection = "core";

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final authProfiles = cfg.authProfiles;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF111111) : Colors.white;

    return Row(
      children: [
        // --- 左侧二级侧边栏 (OpenList 风格) ---
        Container(
          width: 240,
          color: isDark ? const Color(0xFF18181B) : Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 认证配置
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("认证配置", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    tooltip: "添加 Provider",
                    onPressed: () => _showAddAuthProfileDialog(cfg, authProfiles),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Auth profile 列表
              ...authProfiles.entries.map((entry) {
                final profile = Map<String, dynamic>.from(entry.value);
                final provider = profile["provider"] ?? entry.key;
                final preset = _providerPresets[provider] ?? _providerPresets["custom"]!;
                return _SecondarySidebarItem(
                  icon: Icons.vpn_key_outlined,
                  title: preset["name"] ?? provider,
                  subtitle: provider,
                  isSelected: _selection == "auth:${entry.key}",
                  onTap: () => setState(() => _selection = "auth:${entry.key}"),
                );
              }),
              const SizedBox(height: 16),
              // 模型配置
              const Divider(height: 1),
              const SizedBox(height: 16),
              const Text("模型配置", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 8),
              _SecondarySidebarItem(
                icon: Icons.hub_outlined,
                title: "核心设置",
                subtitle: "主模型、工作区",
                isSelected: _selection == "core",
                onTap: () => setState(() => _selection = "core"),
              ),
              const SizedBox(height: 4),
              _SecondarySidebarItem(
                icon: Icons.model_training_outlined,
                title: "模型列表",
                subtitle: "管理可用模型",
                isSelected: _selection == "models",
                onTap: () => setState(() => _selection = "models"),
              ),
            ],
          ),
        ),

        // --- 右侧内容区 ---
        Expanded(
          child: Column(
            children: [
              _buildHeader(cfg, authProfiles),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(32),
                  children: [_buildContent(cfg, authProfiles)],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 根据选中项构建标题栏
  Widget _buildHeader(ConfigProvider cfg, Map authProfiles) {
    if (_selection == "core") {
      return const _HeaderBar(title: "核心设置", subtitle: "配置主模型、工作区目录、压缩策略");
    }
    if (_selection == "models") {
      return const _HeaderBar(title: "模型列表", subtitle: "管理所有已配置的模型及其参数");
    }
    // auth profile
    final profileKey = _selection.substring(5);
    final profile = Map<String, dynamic>.from(authProfiles[profileKey] ?? {});
    final provider = profile["provider"] ?? profileKey;
    final preset = _providerPresets[provider] ?? _providerPresets["custom"]!;
    return _HeaderBar(title: preset["name"] ?? provider, subtitle: "配置认证信息");
  }

  // 根据选中项构建内容
  Widget _buildContent(ConfigProvider cfg, Map authProfiles) {
    if (_selection == "core") return _buildCoreSettings(cfg);
    if (_selection == "models") return _buildModelsList(cfg);
    // auth profile
    final profileKey = _selection.substring(5);
    final profile = Map<String, dynamic>.from(authProfiles[profileKey] ?? {});
    return _buildAuthProfileEditor(cfg, profileKey, profile, authProfiles);
  }

  // ============================
  // 核心设置 (主模型 + 工作区)
  // ============================
  Widget _buildCoreSettings(ConfigProvider cfg) {
    final agentDefaults = cfg.config.get("agents.defaults") as Map? ?? {};
    final modelPrimary = (agentDefaults["model"] as Map? ?? {})["primary"] ?? "";
    final workspace = agentDefaults["workspace"] ?? "";

    return Column(
      children: [
        _SectionCard(
          title: "主模型",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ConfigTextField(
                label: "主模型 ID",
                value: modelPrimary,
                onChanged: (v) => cfg.updateField("agents.defaults.model.primary", v),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withAlpha(40)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "格式: provider/model-id:variant\n示例: openrouter/auto, deepseek/deepseek-chat",
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "工作区",
          child: _ConfigTextField(
            label: "工作区路径",
            value: workspace,
            onChanged: (v) => cfg.updateField("agents.defaults.workspace", v),
          ),
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: "压缩策略",
          child: DropdownButtonFormField<String>(
            initialValue: agentDefaults["compaction"]?["mode"] ?? "safeguard",
            decoration: const InputDecoration(labelText: "压缩模式", isDense: true),
            items: const [
              DropdownMenuItem(value: "safeguard", child: Text("Safeguard (安全模式)")),
              DropdownMenuItem(value: "auto", child: Text("Auto (自动)")),
            ],
            onChanged: (v) => cfg.updateField("agents.defaults.compaction.mode", v),
          ),
        ),
      ],
    );
  }

  // ============================
  // 模型列表管理
  // ============================
  Widget _buildModelsList(ConfigProvider cfg) {
    final agentDefaults = cfg.config.get("agents.defaults") as Map? ?? {};
    final modelsMap = Map<String, dynamic>.from(agentDefaults["models"] as Map? ?? {});

    return Column(
      children: [
        // 操作栏
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("已配置模型 (${modelsMap.length})", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: () => _showAddModelDialog(cfg, modelsMap),
              icon: const Icon(Icons.add, size: 16),
              label: const Text("添加模型"),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (modelsMap.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text("暂无模型，请点击「添加模型」", style: TextStyle(color: Colors.grey))),
          ),
        // 模型卡片列表
        ...modelsMap.entries.map((entry) {
          final modelId = entry.key;
          final modelData = Map<String, dynamic>.from(entry.value);
          return _ModelCard(
            modelId: modelId,
            alias: modelData["alias"] ?? "",
            maxTokens: modelData["maxTokens"],
            temperature: modelData["temperature"],
            isPrimary: ((cfg.config.get("agents.defaults.model") as Map? ?? {})["primary"] ?? "") == modelId,
            onSetPrimary: () {
              cfg.updateField("agents.defaults.model.primary", modelId);
              setState(() {});
            },
            onEdit: () => _showEditModelDialog(cfg, modelId, modelData, modelsMap),
            onRemove: () {
              modelsMap.remove(modelId);
              cfg.updateField("agents.defaults.models", modelsMap);
              setState(() {});
            },
          );
        }),
      ],
    );
  }

  void _showAddModelDialog(ConfigProvider cfg, Map modelsMap) {
    final idCtrl = TextEditingController();
    final aliasCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("添加模型"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: idCtrl, decoration: const InputDecoration(labelText: "模型 ID (如 deepseek/deepseek-chat)")),
          const SizedBox(height: 8),
          TextField(controller: aliasCtrl, decoration: const InputDecoration(labelText: "别名 (可选)")),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
        FilledButton(onPressed: () {
          final id = idCtrl.text.trim();
          if (id.isNotEmpty) {
            modelsMap[id] = {"alias": aliasCtrl.text.trim().isNotEmpty ? aliasCtrl.text.trim() : id};
            cfg.updateField("agents.defaults.models", modelsMap);
            setState(() {});
          }
          Navigator.pop(ctx);
        }, child: const Text("添加")),
      ],
    ));
  }

  void _showEditModelDialog(ConfigProvider cfg, String modelId, Map modelData, Map modelsMap) {
    final aliasCtrl = TextEditingController(text: modelData["alias"] ?? "");
    final maxTokensCtrl = TextEditingController(text: (modelData["maxTokens"] ?? "").toString());
    final tempCtrl = TextEditingController(text: (modelData["temperature"] ?? "").toString());

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text("编辑: $modelId"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: aliasCtrl, decoration: const InputDecoration(labelText: "别名")),
          const SizedBox(height: 8),
          TextField(controller: maxTokensCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "最大 Tokens")),
          const SizedBox(height: 8),
          TextField(controller: tempCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "温度 (0-2)")),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
        FilledButton(onPressed: () {
          modelData["alias"] = aliasCtrl.text.trim();
          final mt = int.tryParse(maxTokensCtrl.text.trim());
          if (mt != null) modelData["maxTokens"] = mt;
          final temp = double.tryParse(tempCtrl.text.trim());
          if (temp != null) modelData["temperature"] = temp;
          modelsMap[modelId] = modelData;
          cfg.updateField("agents.defaults.models", modelsMap);
          setState(() {});
          Navigator.pop(ctx);
        }, child: const Text("保存")),
      ],
    ));
  }

  // ============================
  // 认证配置编辑器
  // ============================
  Widget _buildAuthProfileEditor(ConfigProvider cfg, String profileKey, Map profile, Map authProfiles) {
    final provider = profile["provider"] ?? profileKey;
    final mode = profile["type"] ?? "api_key";
    final apiKey = profile["key"] ?? "";
    final preset = _providerPresets[provider] ?? _providerPresets["custom"]!;

    return Column(
      children: [
        _SectionCard(
          title: "认证信息",
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            tooltip: "删除此认证",
            onPressed: () {
              authProfiles.remove(profileKey);
              cfg.saveAuthProfiles();
              setState(() => _selection = "core");
            },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Provider 选择
              DropdownButtonFormField<String>(
                initialValue: provider,
                decoration: const InputDecoration(labelText: "Provider", isDense: true),
                items: _providerPresets.entries.map((e) =>
                  DropdownMenuItem(value: e.key, child: Text("${e.value["name"]} (${e.key})"))
                ).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final newKey = "$v:default";
                  final newProfile = {"provider": v, "type": mode, "key": apiKey};
                  // 移除旧的，添加新的
                  authProfiles.remove(profileKey);
                  authProfiles[newKey] = newProfile;
                  cfg.saveAuthProfiles();
                  setState(() => _selection = "auth:$newKey");
                },
              ),
              const SizedBox(height: 16),
              // 认证模式
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: "认证模式", isDense: true),
                items: const [
                  DropdownMenuItem(value: "api_key", child: Text("API Key (直接配置)")),
                  DropdownMenuItem(value: "env", child: Text("环境变量 (ENV)")),
                  DropdownMenuItem(value: "ref", child: Text("Secrets Ref (高级)")),
                ],
                onChanged: (v) {
                  profile["type"] = v ?? "api_key";
                  authProfiles[profileKey] = profile;
                  cfg.saveAuthProfiles();
                  setState(() {});
                },
              ),
              if (mode == "api_key") ...[
                const SizedBox(height: 16),
                _ConfigTextField(
                  label: "API Key",
                  value: apiKey,
                  isSecret: true,
                  onChanged: (v) {
                    profile["key"] = v;
                    authProfiles[profileKey] = profile;
                    cfg.saveAuthProfiles();
                  },
                ),
              ],
              const SizedBox(height: 16),
              // Base URL
              _ConfigTextField(
                label: "Base URL",
                value: preset["base"] ?? "",
                onChanged: (v) {}, // read-only display for reference
              ),
              const SizedBox(height: 8),
              Text("API 类型: ${preset["api"]}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  // ============================
  // 添加认证 Profile 对话框
  // ============================
  void _showAddAuthProfileDialog(ConfigProvider cfg, Map authProfiles) {
    String selectedProvider = "openrouter";
    final keyCtrl = TextEditingController(text: "default");

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
      return AlertDialog(
        title: const Text("添加认证"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedProvider,
              decoration: const InputDecoration(labelText: "Provider", isDense: true),
              items: _providerPresets.entries.map((e) =>
                DropdownMenuItem(value: e.key, child: Text("${e.value["name"]} (${e.key})"))
              ).toList(),
              onChanged: (v) => setDialogState(() => selectedProvider = v ?? "openrouter"),
            ),
            const SizedBox(height: 12),
            TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: "Profile ID (如: default, production)", isDense: true)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          FilledButton(onPressed: () {
            final id = keyCtrl.text.trim();
            if (id.isNotEmpty) {
              final profileKey = "$selectedProvider:$id";
              authProfiles[profileKey] = {"provider": selectedProvider, "type": "api_key", "key": ""};
              cfg.saveAuthProfiles();
              setState(() => _selection = "auth:$profileKey");
            }
            Navigator.pop(ctx);
          }, child: const Text("添加")),
        ],
      );
    }));
  }
}

// 模型卡片组件（可展开）
class _ModelCard extends StatefulWidget {
  final String modelId;
  final String alias;
  final int? maxTokens;
  final double? temperature;
  final bool isPrimary;
  final VoidCallback onSetPrimary;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ModelCard({
    required this.modelId,
    required this.alias,
    this.maxTokens,
    this.temperature,
    required this.isPrimary,
    required this.onSetPrimary,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  State<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<_ModelCard> {
  bool _isExpanded = false;
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252525) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: widget.isPrimary ? Border.all(color: Colors.blue, width: 1.5) : null,
      ),
      child: Column(
        children: [
          // 头部（点击展开/收起）
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(widget.alias.isNotEmpty ? widget.alias : widget.modelId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                            if (widget.isPrimary) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(4)),
                                child: const Text("主模型", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(widget.modelId, style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: "Consolas")),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
                    onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  ),
                ],
              ),
            ),
          ),
          // 展开内容
          if (_isExpanded) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const Divider(),
                  // 参数显示
                  if (widget.maxTokens != null || widget.temperature != null) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (widget.maxTokens != null)
                          Chip(label: Text("Tokens: ${widget.maxTokens}", style: const TextStyle(fontSize: 11)), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                        if (widget.temperature != null)
                          Chip(label: Text("Temp: ${widget.temperature}", style: const TextStyle(fontSize: 11)), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 操作按钮（统一风格）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ActionButton(
                        icon: widget.isPrimary ? Icons.star : Icons.star_border,
                        label: widget.isPrimary ? "主模型" : "设为主模型",
                        color: widget.isPrimary ? Colors.amber : Colors.grey,
                        onTap: widget.isPrimary ? null : widget.onSetPrimary,
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: Icons.edit,
                        label: "编辑",
                        color: Colors.blue,
                        onTap: () => setState(() => _isEditing = true),
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: Icons.delete,
                        label: "删除",
                        color: Colors.red,
                        onTap: widget.onRemove,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
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
    {"name": "Slack", "icon": Icons.chat_bubble_outline, "desc": "Slack Bot", "configKey": "slack"},
    {"name": "iMessage", "icon": Icons.message, "desc": "macOS 本地集成", "configKey": "imessage"},
  ];

  // 当前已添加的渠道
  List<Map<String, dynamic>> channels = [
    {"name": "WhatsApp", "icon": Icons.phone_android, "desc": "Meta 官方 API", "configKey": "whatsapp"},
    {"name": "Telegram", "icon": Icons.send, "desc": "Bot API", "configKey": "telegram"},
    {"name": "Feishu", "icon": Icons.work, "desc": "飞书/Lark 机器人", "configKey": "feishu"},
    {"name": "Discord", "icon": Icons.discord, "desc": "Bot Gateway", "configKey": "discord"},
    {"name": "Slack", "icon": Icons.chat_bubble_outline, "desc": "Slack Bot", "configKey": "slack"},
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
      case "slack": return const _SlackConfigView();
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
    final ws = cfg.config.get("channels.whatsapp") as Map? ?? {};
    final groups = ws["groups"] as Map? ?? {};
    return ListView(children: [
      _SectionCard(
          title: "私聊策略 (DM)",
          child: Column(children: [
            _EnumDropdown(
                label: "DM 策略",
                value: ws["dmPolicy"] ?? "pairing",
                options: const ["pairing", "allowlist", "open"],
                onChanged: (v) => cfg.updateField("channels.whatsapp.dmPolicy", v)),
            const SizedBox(height: 16),
            _StringListEditor(
                label: "DM 白名单 (AllowFrom)",
                items: ws["allowFrom"] ?? [],
                onChanged: (list) => cfg.updateField("channels.whatsapp.allowFrom", list)),
          ])),
      const SizedBox(height: 24),
      _SectionCard(
          title: "群聊策略 (Group)",
          child: Column(children: [
            _EnumDropdown(
                label: "群聊策略",
                value: ws["groupPolicy"] ?? "allowlist",
                options: const ["allowlist", "open", "disabled"],
                onChanged: (v) => cfg.updateField("channels.whatsapp.groupPolicy", v)),
            const SizedBox(height: 16),
            _StringListEditor(
                label: "群聊白名单 (GroupAllowFrom)",
                items: ws["groupAllowFrom"] ?? [],
                onChanged: (list) => cfg.updateField("channels.whatsapp.groupAllowFrom", list)),
            const SizedBox(height: 16),
            _SwitchTile(
                title: "群聊需要 @提及",
                value: groups["*"]?["requireMention"] ?? true,
                onChanged: (v) => cfg.updateField("channels.whatsapp.groups.*.requireMention", v)),
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
    final groups = tg["groups"] as Map? ?? {};
    return ListView(children: [
      _SectionCard(
          title: "Bot Token",
          child: Column(children: [
            _SwitchTile(
                title: "启用 Telegram 渠道",
                value: tg["enabled"] ?? true,
                onChanged: (v) => cfg.updateField("channels.telegram.enabled", v)),
            const SizedBox(height: 16),
            _ConfigTextField(
                label: "Bot Token",
                value: tg["botToken"] ?? "",
                isSecret: true,
                onChanged: (v) => cfg.updateField("channels.telegram.botToken", v)),
          ])),
      const SizedBox(height: 24),
      _SectionCard(
          title: "私聊策略 (DM)",
          child: Column(children: [
            _EnumDropdown(
                label: "DM 策略",
                value: tg["dmPolicy"] ?? "pairing",
                options: const ["pairing", "allowlist", "open"],
                onChanged: (v) => cfg.updateField("channels.telegram.dmPolicy", v)),
            const SizedBox(height: 16),
            _StringListEditor(
                label: "DM 白名单 (AllowFrom User IDs)",
                items: tg["allowFrom"] ?? [],
                onChanged: (list) => cfg.updateField("channels.telegram.allowFrom", list)),
          ])),
      const SizedBox(height: 24),
      _SectionCard(
          title: "群聊策略 (Group)",
          child: Column(children: [
            _EnumDropdown(
                label: "群聊策略",
                value: tg["groupPolicy"] ?? "allowlist",
                options: const ["allowlist", "open", "disabled"],
                onChanged: (v) => cfg.updateField("channels.telegram.groupPolicy", v)),
            const SizedBox(height: 16),
            _StringListEditor(
                label: "群聊白名单 (GroupAllowFrom)",
                items: tg["groupAllowFrom"] ?? [],
                onChanged: (list) => cfg.updateField("channels.telegram.groupAllowFrom", list)),
            const SizedBox(height: 16),
            _SwitchTile(
                title: "群聊需要 @提及",
                value: groups["*"]?["requireMention"] ?? true,
                onChanged: (v) => cfg.updateField("channels.telegram.groups.*.requireMention", v)),
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

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _regPath = r'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _appName = 'OpenClawManager';
  bool _autoStart = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAutoStart();
  }

  Future<void> _checkAutoStart() async {
    if (!Platform.isWindows) { setState(() => _loading = false); return; }
    try {
      final res = await Process.run('reg', ['query', _regPath, '/v', _appName], runInShell: true);
      setState(() {
        _autoStart = res.exitCode == 0 && res.stdout.toString().contains(_appName);
        _loading = false;
      });
    } catch (_) {
      setState(() { _autoStart = false; _loading = false; });
    }
  }

  String _getExePath() {
    String exePath = Platform.resolvedExecutable;
    if (!File(exePath).existsSync()) {
      final exeName = 'openclaw_dashboard.exe';
      final currentDir = Directory.current.path;
      final altPath = '$currentDir\\$exeName';
      if (File(altPath).existsSync()) {
        exePath = altPath;
      }
    }
    return exePath;
  }

  Future<void> _toggleAutoStart(bool value) async {
    if (!Platform.isWindows) return;
    try {
      if (value) {
        final exePath = _getExePath();
        await Process.run('reg', ['add', _regPath, '/v', _appName, '/t', 'REG_SZ', '/d', '"$exePath"', '/f'], runInShell: true);
      } else {
        await Process.run('reg', ['delete', _regPath, '/v', _appName, '/f'], runInShell: true);
      }
      setState(() => _autoStart = value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(value ? "已开启开机自启动" : "已关闭开机自启动"), duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("操作失败: $e"), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

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
      SwitchListTile(
        title: const Text("开机自启动"),
        subtitle: Text(_loading ? "检测中..." : (_autoStart ? "已开启 — 系统启动时自动运行" : "未开启")),
        value: _autoStart,
        onChanged: _loading ? null : _toggleAutoStart,
        secondary: Icon(_autoStart ? Icons.check_circle : Icons.circle_outlined, color: _autoStart ? Colors.green : Colors.grey),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: Theme.of(context).cardColor,
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accentColor = Color(0xFF3B82F6);
    const borderColor = Color(0xFF3F3F46);
    
    return Container(
      height: 72, padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181B) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? borderColor : Colors.grey.shade200)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
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
    const accentColor = Color(0xFF3B82F6);
    return _ActionButton(
      icon: Icons.save,
      label: "保存",
      color: accentColor,
      onTap: () => context.read<ConfigProvider>().saveConfig(),
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
    const borderColor = Color(0xFF3F3F46);
    const cardColor = Color(0xFF27272A);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? cardColor : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? borderColor : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
          if (trailing != null) trailing!
        ]),
        const SizedBox(height: 16),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700)),
      const SizedBox(height: 8),
      TextField(
        controller: _ctrl,
        obscureText: _obscure,
        onChanged: widget.onChanged,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          suffixIcon: widget.isSecret ? IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18), onPressed: ()=>setState(()=>_obscure=!_obscure)) : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
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
    const borderColor = Color(0xFF3F3F46);
    const cardColor = Color(0xFF27272A);
    
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? cardColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? borderColor : Colors.grey.shade200),
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 14)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600))
          ]),
        ),
      ),
    );
  }
}

// ==========================================
// 新增组件：二级侧边栏胶囊选项 (OpenList 风格)
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
    const accentColor = Color(0xFF3B82F6);
    const borderColor = Color(0xFF3F3F46);
    const cardColor = Color(0xFF27272A);
    
    // 选中：accent色背景 + 白色文字
    // 未选中：透明背景 + 灰色文字
    final bgColor = isSelected ? accentColor : Colors.transparent;
    final fgColor = isSelected 
        ? Colors.white 
        : (isDark ? Colors.grey.shade400 : Colors.grey.shade700);
    final subtitleColor = isSelected 
        ? Colors.white.withAlpha(200) 
        : (isDark ? Colors.grey.shade500 : Colors.grey.shade500);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? accentColor.withAlpha(25) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isSelected ? Border.all(color: accentColor.withAlpha(50)) : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? accentColor : (isDark ? cardColor : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: isSelected ? Colors.white : fgColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? accentColor : fgColor,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
// 新增：Slack 配置视图
// ==========================================
class _SlackConfigView extends StatelessWidget {
  const _SlackConfigView();
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final slack = cfg.config.get("channels.slack") as Map? ?? {};
    final dm = slack["dm"] as Map? ?? {};
    final sc = slack["slashCommand"] as Map? ?? {};
    return ListView(children: [
      _SectionCard(
          title: "Slack 认证",
          child: Column(children: [
            _SwitchTile(
                title: "启用 Slack 渠道",
                value: slack["enabled"] ?? false,
                onChanged: (v) => cfg.updateField("channels.slack.enabled", v)),
            const SizedBox(height: 16),
            _ConfigTextField(
                label: "Bot Token (xoxb-...)",
                value: slack["botToken"] ?? "",
                isSecret: true,
                onChanged: (v) => cfg.updateField("channels.slack.botToken", v)),
            _ConfigTextField(
                label: "App Token (xapp-...)",
                value: slack["appToken"] ?? "",
                isSecret: true,
                onChanged: (v) => cfg.updateField("channels.slack.appToken", v)),
          ])),
      const SizedBox(height: 24),
      _SectionCard(
          title: "私聊策略 (DM)",
          child: Column(children: [
            _SwitchTile(
                title: "允许私聊",
                value: dm["enabled"] ?? true,
                onChanged: (v) => cfg.updateField("channels.slack.dm.enabled", v)),
            const SizedBox(height: 16),
            _StringListEditor(
                label: "DM 白名单 (AllowFrom User IDs)",
                items: dm["allowFrom"] ?? [],
                onChanged: (list) => cfg.updateField("channels.slack.dm.allowFrom", list)),
          ])),
      const SizedBox(height: 24),
      _SectionCard(
          title: "Slash Command",
          child: Column(children: [
            _SwitchTile(
                title: "启用 Slash Command",
                value: sc["enabled"] ?? true,
                onChanged: (v) => cfg.updateField("channels.slack.slashCommand.enabled", v)),
            const SizedBox(height: 16),
            _ConfigTextField(
                label: "命令名称",
                value: sc["name"] ?? "openclaw",
                onChanged: (v) => cfg.updateField("channels.slack.slashCommand.name", v)),
            _SwitchTile(
                title: "仅自己可见 (Ephemeral)",
                value: sc["ephemeral"] ?? true,
                onChanged: (v) => cfg.updateField("channels.slack.slashCommand.ephemeral", v)),
          ])),
    ]);
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