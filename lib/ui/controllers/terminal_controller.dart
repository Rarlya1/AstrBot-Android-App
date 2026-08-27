import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import 'package:xterm/xterm.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/scripts.dart' as scripts;
import '../../generated/l10n.dart';
import '../../core/constants/scripts.dart';
import '../../core/utils/file_utils.dart';
import '../routes/app_routes.dart';
import 'terminal_tab_manager.dart';

class HomeController extends GetxController {
  static const _nativeWebViewChannel = MethodChannel('astrbot_native_webview');
  static const double defaultTerminalFontSize = 12.0;
  static const double minTerminalFontSize = 8.0;
  static const double maxTerminalFontSize = 16.0;
  // 终端标签页管理器
  late final TerminalTabManager terminalTabManager;
  // bool vsCodeStaring = false;
  SettingNode privacySetting = 'privacy'.setting;
  SettingNode napCatWebUiEnabled = 'napcat_webui_enabled'.setting;
  SettingNode showTerminalWhiteText = 'show_terminal_white_text'.setting;
  SettingNode customStartupCommand = 'custom_startup_command'.setting;
  Pty? astrbotPty;
  Pty? napcatPty;

  final RxString napCatWebUiToken = ''.obs; // 存储 NapCat WebUI Token
  final RxBool napCatWebUiEnabledRx = false.obs; // GetX 响应式变量用于导航栏更新
  final RxBool showTerminalWhiteTextRx = false.obs; // GetX 响应式变量用于设置页更新
  // 仅保存在当前运行期间，应用重启后恢复 xterm 默认字号
  final RxDouble terminalFontSize = defaultTerminalFontSize.obs;
  final RxList<Map<String, String>> customWebViews =
      <Map<String, String>>[].obs; // 自定义 WebView 列表
  final RxInt navigateToTab = (-1).obs; // 通知 WebViewPage 切换标签页
  StreamSubscription? _napcatSubscription;
  StreamSubscription? _webviewSubscription; // 添加webview监听订阅

  late Terminal astrbotTerminal = Terminal(
    maxLines: 4096,
    onResize: (width, height, pixelWidth, pixelHeight) {
      astrbotPty?.resize(height, width);
    },
    onOutput: (data) {
      astrbotPty?.writeString(data);
    },
  );
  late Terminal napcatTerminal = Terminal(
    maxLines: 4096,
  );
  bool webviewHasOpen = false;
  final RxBool isLocalhostDetected = false.obs; // localhost:6185 检测标志
  bool _isAppInForeground = true; // 应用是否在前台
  bool _isAstrBotConfiguring = false; // AstrBot 配置中标志，用于控制终端输出过滤
  bool _isNapCatLogin = false; // NapCat 登录标记
  bool _isNapCatQuickLogin = false; // NapCat 快速登录标记
  String _pendingOutput = ''; // 待处理的输出缓冲

  File progressFile = File('${RuntimeEnvir.tmpPath}/progress');
  File progressDesFile = File('${RuntimeEnvir.tmpPath}/progress_des');
  final RxDouble progress = 0.0.obs;
  double step = 14.0;
  final RxString currentProgress = ''.obs;

  void setTerminalFontSize(double size) {
    terminalFontSize.value = size.clamp(minTerminalFontSize, maxTerminalFontSize).toDouble();
  }

  String getCustomStartupCommand() {
    return customStartupCommand.get() as String? ?? '';
  }

  // 进度 +1
  // Progress +1
  void bumpProgress() {
    try {
      int current = 0;
      if (progressFile.existsSync()) {
        final content = progressFile.readAsStringSync().trim();
        if (content.isNotEmpty) {
          current = int.tryParse(content) ?? 0;
        }
      } else {
        progressFile.createSync(recursive: true);
      }
      progressFile.writeAsStringSync('${current + 1}');
    } catch (e) {
      progressFile.writeAsStringSync('1');
    }
    update();
  }

  // 检测文本是否包含彩色 ANSI 代码(非白色/默认色)
  // Check if text contains colored ANSI codes (non-white/default)
  bool _hasColoredAnsiCode(String text) {
    // ANSI 彩色代码正则: \x1b[...m 或 \033[...m
    // 匹配所有颜色代码，排除白色(37)和重置代码(0)
    final ansiColorRegex = RegExp(
      r'\x1b\[([0-9;]+)m|\033\[([0-9;]+)m',
      multiLine: true,
    );

    final matches = ansiColorRegex.allMatches(text);
    for (var match in matches) {
      final code = match.group(1) ?? match.group(2) ?? '';
      // 检查是否包含颜色代码
      // 30-37: 前景色, 40-47: 背景色, 90-97: 高亮前景色, 100-107: 高亮背景色
      // 排除: 0(重置), 37(白色), 97(高亮白色)
      final codes = code.split(';');
      for (var c in codes) {
        final colorCode = int.tryParse(c.trim());
        if (colorCode != null) {
          // 有效的颜色代码(非白色且非重置)
          if ((colorCode >= 30 && colorCode <= 36) || // 前景色(黑到青)
              (colorCode >= 40 && colorCode <= 47) || // 背景色
              (colorCode >= 90 && colorCode <= 96) || // 高亮前景色(非白)
              (colorCode >= 100 && colorCode <= 107)) {
            // 高亮背景色
            return true;
          }
        }
      }
    }
    return false;
  }

  // 检测文本是否为纯彩色输出(不含白色文本)
  // Check if text is purely colored output (no white/default text)
  bool _isPurelyColoredOutput(String text) {
    // 移除所有 ANSI 代码后，检查是否还有可见文本
    final ansiRegex = RegExp(r'\x1b\[[0-9;]*m|\033\[[0-9;]*m');
    final cleanText = text.replaceAll(ansiRegex, '').trim();

    // 如果移除 ANSI 代码后没有可见文本，说明是纯 ANSI 控制序列
    if (cleanText.isEmpty) {
      return _hasColoredAnsiCode(text);
    }

    // 如果有可见文本但没有任何彩色代码，说明是纯白色文本
    if (!_hasColoredAnsiCode(text)) {
      return false;
    }

    // 关键判断：检查文本中是否所有可见内容都被彩色 ANSI 代码包裹
    // 策略：分段检查每个 ANSI 颜色代码后面的文本，直到遇到重置代码或下一个颜色代码
    final ansiColorRegex = RegExp(
      r'\x1b\[([0-9;]+)m|\033\[([0-9;]+)m',
      multiLine: true,
    );

    int lastIndex = 0;
    bool inColoredSection = false;
    bool hasUncoloredText = false;

    final matches = ansiColorRegex.allMatches(text).toList();

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];

      // 检查当前 ANSI 代码之前的文本
      if (match.start > lastIndex) {
        final textBefore = text.substring(lastIndex, match.start).trim();
        // 如果之前有文本且不在彩色段中，说明有未着色的白色文本
        if (textBefore.isNotEmpty && !inColoredSection) {
          hasUncoloredText = true;
          break;
        }
      }

      final code = match.group(1) ?? match.group(2) ?? '';
      final codes = code.split(';');

      // 检查这个 ANSI 代码是否是颜色代码(非白色)
      bool isColorCode = false;
      bool isResetCode = false;

      for (var c in codes) {
        final colorCode = int.tryParse(c.trim());
        if (colorCode != null) {
          if (colorCode == 0) {
            isResetCode = true;
          } else if ((colorCode >= 30 && colorCode <= 36) ||
              (colorCode >= 40 && colorCode <= 47) ||
              (colorCode >= 90 && colorCode <= 96) ||
              (colorCode >= 100 && colorCode <= 107)) {
            isColorCode = true;
          }
        }
      }

      if (isColorCode) {
        inColoredSection = true;
      } else if (isResetCode) {
        inColoredSection = false;
      }

      lastIndex = match.end;
    }

    // 检查最后一个 ANSI 代码之后的文本
    if (lastIndex < text.length) {
      final textAfter = text.substring(lastIndex).trim();
      if (textAfter.isNotEmpty && !inColoredSection) {
        hasUncoloredText = true;
      }
    }

    // 如果存在未着色的文本，说明不是纯彩色输出
    return !hasUncoloredText;
  }

  // 检测文本是否包含 ANSI 重置代码
  // Check if text contains ANSI reset code
  bool _hasResetCode(String text) {
    // 匹配重置代码: \x1b[0m 或 \033[0m
    final resetRegex = RegExp(r'\x1b\[0m|\033\[0m');
    return resetRegex.hasMatch(text);
  }

  // 处理彩色输出过滤逻辑
  // Handle colored output filtering logic
  void _processColoredOutput(String event) {
    _pendingOutput += event;

    // 检查是否包含彩色代码和重置代码
    final isPurelyColored = _isPurelyColoredOutput(_pendingOutput);
    final hasReset = _hasResetCode(_pendingOutput);

    // 检查是否有完整的行(以换行符结尾)或者包含重置代码
    if (_pendingOutput.endsWith('\n') ||
        _pendingOutput.endsWith('\r\n') ||
        hasReset) {
      // 只有当输出是纯彩色的（不包含白色文本）时才输出
      if (isPurelyColored) {
        _writeWithTrim(astrbotTerminal, _pendingOutput);
      }
      // 清空缓冲
      _pendingOutput = '';
    }
  }

  // 检查条件是否满足，如果满足则触发跳转
  void _checkAndNavigateToWebview() {
    // 只有当条件满足且应用在前台时才跳转
    if (isLocalhostDetected.value &&
        _isAppInForeground &&
        !webviewHasOpen) {
      Future.microtask(() {
        // 安装页只负责加载，AstrBot 就绪后替换掉安装页。
        if (Get.currentRoute == AppRoutes.terminal) {
          Get.offNamed(AppRoutes.webview);
        }

        if (!_isNapCatLogin && !_isNapCatQuickLogin) {
          Get.snackbar(
            'NapCat 未登录',
            '请前往 NapCat 终端页或 WebUI 自行扫码登录',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.withValues(alpha: 0.8),
            colorText: Colors.white,
            duration: const Duration(seconds: 5),
          );
        } else if (!_isNapCatLogin && _isNapCatQuickLogin) {
          Get.snackbar(
            'NapCat 未配置快速登录',
            '请前往设置页配置快速登录QQ账号设置',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.orange.withValues(alpha: 0.8),
            colorText: Colors.white,
            duration: const Duration(seconds: 5),
          );
          _isNapCatLogin = true; // 视为已登录，防止重复触发
        }

        // 新建终端页并运行自定义启动命令
        final command = getCustomStartupCommand();
        if (command.trim().isNotEmpty) {
          terminalTabManager.addSystemTerminalTab(command);
        }

        webviewHasOpen = true;
      });
    }
  }

  // 监听输出，当输出中包含启动成功的标志时，启动 VewView 和导航栏页面
  void initWebviewListener() {
    if (astrbotPty == null) return;

    _webviewSubscription = astrbotPty!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((event) async {
      // 输出到 Flutter 控制台
      // Output to Flutter console
      if (event.trim().isNotEmpty) {
        // 按行分割输出，避免控制台输出混乱
        final lines = event.split('\n');
        for (var line in lines) {
          if (line.trim().isNotEmpty) {
            Log.i(line, tag: 'AstrBot');
          }
        }
      }

      // 检查是否包含 localhost:6185
      if (event.contains('http://localhost:6185')) {
        isLocalhostDetected.value = true;
        bumpProgress();

        // 检查是否条件满足
        // 现在的实际功能为检查napcat登录状态和新建终端运行自定义启动命令
        _checkAndNavigateToWebview();

        Future.delayed(const Duration(milliseconds: 2000), () {
          update();
        });

        // 不取消订阅，继续监听以便终端日志持续更新
      }

      // 只在 AstrBot 配置阶段，并且显示终端白色文本（未设置时默认开启）为关闭时才过滤非彩色输出
      // Only filter non‑colored output after AstrBot configuration starts when showTerminalWhiteText is disabled.
      if (_isAstrBotConfiguring && showTerminalWhiteText.get() == false) {
        // 使用新的彩色输出处理逻辑,支持多行彩色输出
        _processColoredOutput(event);
      } else {
        // 配置前显示所有输出
        _writeWithTrim(astrbotTerminal, event);
      }
    });
  }

  void initNapcatListener() {
    if (napcatPty == null) return;

    _napcatSubscription = napcatPty!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((event) async {
      // 输出到 Flutter 控制台
      // Output to Flutter console
      if (event.trim().isNotEmpty) {
        // 按行分割输出，避免控制台输出混乱
        final lines = event.split('\n');
        for (var line in lines) {
          if (line.trim().isNotEmpty) {
            Log.i(line, tag: 'AstrBot-Napcat');
          }
        }
      }

      // 捕获 NapCat WebUI Token
      if (event.contains('WebUi Token:')) {
        final match = RegExp(r'WebUi Token:\s+(\w+)').firstMatch(event);
        if (match != null) {
          final token = match.group(1);
          if (token != null) {
            napCatWebUiToken.value = token;
            Log.i('捕获到 NapCat Token: $token', tag: 'AstrBot');
          }
        }
      }

      if (event.contains('可用于快速登录')) {
        _isNapCatQuickLogin = true;
      }

      if (event.contains('正在快速登录')) {
        _isNapCatLogin = true;
      }

      // 写入 NapCat 终端视图
      _writeWithTrim(napcatTerminal, event);

    });
  }

  // 初始化环境，将动态库中的文件链接到数据目录
  // Init environment and link files from the dynamic library to the data directory
  Future<void> initEnvir() async {
    List<String> androidFiles = [
      'libbash.so',
      'libbusybox.so',
      'liblibtalloc.so.2.so',
      'libloader.so',
      'libproot.so',
      'libsudo.so'
    ];
    String libPath = await getLibPath();
    Log.i('libPath -> $libPath');

    for (int i = 0; i < androidFiles.length; i++) {
      // when android target sdk > 28
      // cannot execute file in /data/data/com.xxx/files/usr/bin
      // so we need create a link to /data/data/com.xxx/files/usr/bin
      final sourcePath = '$libPath/${androidFiles[i]}';
      String fileName = androidFiles[i].replaceAll(RegExp('^lib|\\.so\$'), '');
      String filePath = '${RuntimeEnvir.binPath}/$fileName';
      // custom path, termux-api will invoke
      File file = File(filePath);
      FileSystemEntityType type = await FileSystemEntity.type(filePath);
      Log.i('$fileName type -> $type');
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.link) {
        // old version adb is plain file
        Log.i('find plain file -> $fileName, delete it');
        await file.delete();
      }
      Link link = Link(filePath);
      if (link.existsSync()) {
        link.deleteSync();
      }
      try {
        Log.i('create link -> $fileName ${link.path}');
        link.createSync(sourcePath);
      } catch (e) {
        Log.e('installAdbToEnvir error -> $e');
      }
    }
  }

  // 同步当前进度
  // Sync the current progress
  void syncProgress() {
    progressFile.createSync(recursive: true);
    progressFile.writeAsStringSync('0');
    progressFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressFile.readAsString();
        Log.e('content -> $content');
        if (content.isEmpty) {
          return;
        }
        progress.value = int.parse(content) / step;
        Log.e('progress -> ${progress.value}');
        update();
      }
    });
    progressDesFile.createSync(recursive: true);
    progressDesFile.writeAsStringSync('');
    progressDesFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressDesFile.readAsString();
        currentProgress.value = content;

        // 当进度到达 "Napcat 已安装" 时，启动 NapCat 终端
        if (content.contains('Napcat ${S.current.installed}')) {
          napcatPty?.writeString('source ${RuntimeEnvir.homePath}/common.sh\nlogin_ubuntu "cd /root/Napcat; exec bash launcher.sh"\n');
          bumpProgress();
          Log.i('检测到 Napcat 已安装，启动 NapCat 终端', tag: 'AstrBot');
        }

        // 当进度到达 "AstrBot 配置中" 时，开始过滤非彩色输出并清除终端
        if (content.trim() == 'AstrBot 配置中') {
          _isAstrBotConfiguring = true;
          // 清除终端先前显示的所有文本
          astrbotTerminal.buffer.clear();
          astrbotTerminal.buffer.setCursor(0, 0);
          Log.i('检测到 AstrBot 配置中，清除终端内容', tag: 'AstrBot');
        }

        update();
      }
    });
  }

  // 创建 busybox 的软连接，来确保 proot 会用到的命令正常运行
  // create busybox symlinks, to ensure proot can use the commands normally
  void createBusyboxLink() {
    try {
      List<String> links = [
        ...[
          'awk',
          'ash',
          'basename',
          'bzip2',
          'curl',
          'cp',
          'chmod',
          'cut',
          'cat',
          'du',
          'dd',
          'find',
          'grep',
          'gzip'
        ],
        ...[
          'hexdump',
          'head',
          'id',
          'lscpu',
          'mkdir',
          'realpath',
          'rm',
          'sed',
          'stat',
          'sh',
          'tr',
          'tar',
          'uname',
          'xargs',
          'xz',
          'xxd'
        ]
      ];

      for (String linkName in links) {
        Link link = Link('${RuntimeEnvir.binPath}/$linkName');
        if (!link.existsSync()) {
          link.createSync('${RuntimeEnvir.binPath}/busybox');
        }
      }
      Link link = Link('${RuntimeEnvir.binPath}/file');
      link.createSync('/system/bin/file');
    } catch (e) {
      Log.e('Create link failed -> $e');
    }
  }

  void setProgress(String description) {
    currentProgress.value = description;
    astrbotTerminal.writeProgress(currentProgress.value);
  }

  Future<void> loadAstrBot() async {
    syncProgress();

    // 创建相关文件夹
    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
    Directory(RuntimeEnvir.homePath).createSync(recursive: true);
    Directory(RuntimeEnvir.binPath).createSync(recursive: true);

    await initEnvir();
    createBusyboxLink();

    // 创建终端
    astrbotPty =
        createPTY(rows: astrbotTerminal.viewHeight, columns: astrbotTerminal.viewWidth);
    napcatPty = createPTY();

    // 复制必要的文件
    setProgress('复制 Ubuntu 系统镜像...');
    await AssetsUtils.copyAssetToPath('assets/${Config.ubuntuFileName}',
        '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}');
    await AssetsUtils.copyAssetToPath('assets/astrbot-startup.sh',
        '${RuntimeEnvir.homePath}/astrbot-startup.sh');
    await AssetsUtils.copyAssetToPath(
        'assets/cmd_config.json', '${RuntimeEnvir.homePath}/cmd_config.json');
    await AssetsUtils.copyAssetToPath(
        'assets/proot.py', '${RuntimeEnvir.homePath}/proot.py');
    bumpProgress();

    // 获取当前应用版本号
    final appVersion = await getAppVersion();

    // 替换 astrbot-startup.sh 中的版本号占位符
    final startupScriptFile = File('${RuntimeEnvir.homePath}/astrbot-startup.sh');
    if (await startupScriptFile.exists()) {
      String scriptContent = await startupScriptFile.readAsString();
      scriptContent = scriptContent.replaceAll('{{VERSION}}', appVersion);
      await startupScriptFile.writeAsString(scriptContent);
    }

    // 写入 common.sh 脚本
    File('${RuntimeEnvir.homePath}/common.sh')
        .writeAsStringSync(getCommonScript(appVersion));

    initWebviewListener();
    bumpProgress();

    initNapcatListener();

    startAstrBot(astrbotPty!);
  }

  Future<void> startAstrBot(Pty astrbotPty) async {
    setProgress('开始安装 AstrBot...');
    astrbotPty.writeString(
        'source ${RuntimeEnvir.homePath}/common.sh\nstart_astrbot\n');
  }

  @override
  void onInit() {
    super.onInit();

    // 初始化终端标签页管理器
    terminalTabManager = TerminalTabManager();
    terminalTabManager.initializeFixedTab(
      astrbotTerminal,
      napcatTerminal,
    );

    // 初始化 NapCat WebUI 启用状态
    napCatWebUiEnabledRx.value = napCatWebUiEnabled.get() ?? false;

    // 初始化显示终端白色文本状态（默认打开）
    showTerminalWhiteTextRx.value = showTerminalWhiteText.get() ?? true;

    // 从持久化存储加载自定义 WebView 列表
    _loadCustomWebViews();

    // 为 Google Play 上架做准备
    // For Google Play
    Future.delayed(Duration.zero, () async {
      if (privacySetting.get() == null) {
        await Get.to(PrivacyAgreePage(
          onAgreeTap: () {
            privacySetting.set(true);
            Get.back();
          },
        ));
      }

      // 检查是否已安装 AstrBot
      final dataDir = Directory('${scripts.ubuntuPath}/root/AstrBot/data');
      if (!await dataDir.exists()) {
        Get.snackbar(
          '温馨提示',
          '点击任意位置可显示安装过程',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3),
        );
      }

      // 已安装时由 initialRoute 直接进入主界面，但 AstrBot 仍需由控制器启动。
      loadAstrBot();
    });

    // 监听应用生命周期状态变化
    WidgetsBinding.instance.addObserver(
      LifecycleObserver(
        onResume: () {
          _isAppInForeground = true;
          // 当应用回到前台且条件满足但webview未打开时，打开webview
          if (isLocalhostDetected.value && !webviewHasOpen) {
            Future.microtask(() {
              Get.toNamed(AppRoutes.webview);
              webviewHasOpen = true;
            });
          }
        },
        onPause: () {
          _isAppInForeground = false;
        },
      ),
    );
  }

  // 加载自定义 WebView 列表
  void _loadCustomWebViews() {
    final stored = box!.get('custom_webviews', defaultValue: <dynamic>[]);
    if (stored is List) {
      customWebViews.value = stored.map((e) {
        if (e is Map) {
          return {
            'title': e['title']?.toString() ?? '',
            'url': e['url']?.toString() ?? '',
          };
        }
        return <String, String>{};
      }).toList();
    }
  }

  // 保存自定义 WebView 列表
  void _saveCustomWebViews() {
    box!.put('custom_webviews', customWebViews.toList());
  }

  // 添加自定义 WebView
  void addCustomWebView(String title, String url) {
    customWebViews.add({'title': title, 'url': url});
    _saveCustomWebViews();
  }

  // 删除自定义 WebView
  void removeCustomWebView(int index) {
    if (index >= 0 && index < customWebViews.length) {
      final title = customWebViews[index]['title'] ?? customWebViews[index]['url'] ?? '';
      customWebViews.removeAt(index);
      _saveCustomWebViews();
      _nativeWebViewChannel.invokeMethod('closeWebView', title);
    }
  }

  // 更新自定义 WebView
  void updateCustomWebView(int index, String title, String url) {
    if (index >= 0 && index < customWebViews.length) {
      final oldTitle = customWebViews[index]['title'] ?? customWebViews[index]['url'] ?? '';
      customWebViews[index] = {'title': title, 'url': url};
      _saveCustomWebViews();
      // URL或标题变了，清除旧的 WebView 缓存
      _nativeWebViewChannel.invokeMethod('closeWebView', oldTitle);
    }
  }

  // 更新 NapCat WebUI 启用状态（用于同步响应式变量）
  void setNapCatWebUiEnabled(bool value) {
    napCatWebUiEnabled.set(value);
    napCatWebUiEnabledRx.value = value;
    _nativeWebViewChannel.invokeMethod('closeWebView', 'NapCat');
  }

  // 更新显示终端白色文本状态（用于同步响应式变量）
  void setShowTerminalWhiteText(bool value) {
    showTerminalWhiteText.set(value);
    showTerminalWhiteTextRx.value = value;
  }

  /// 写入终端
  void _writeWithTrim(Terminal t, String data) {
    t.write(data);
  }

  @override
  void onClose() {
    // 清理订阅，避免内存泄漏
    _napcatSubscription?.cancel();
    _webviewSubscription?.cancel();
    _napcatSubscription = null;
    _webviewSubscription = null;

    // 杀死所有终端进程，释放端口
    try {
      if (astrbotPty != null) {
        Log.i('正在关闭主终端进程...', tag: 'AstrBot');
        astrbotPty?.kill();
        astrbotPty = null;
      }
      if (napcatPty != null) {
        Log.i('正在关闭 NapCat 终端进程...', tag: 'AstrBot-Napcat');
        napcatPty?.kill();
        napcatPty = null;
      }
    } catch (e) {
      Log.e('关闭终端进程时出错: $e', tag: 'AstrBot');
    }

    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(
      LifecycleObserver(
        onResume: () {},
        onPause: () {},
      ),
    );
    super.onClose();
  }
}

/// 应用级 HomeController 注册入口。
class HomeControllerBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<HomeController>(HomeController(), permanent: true);
  }
}

// 应用生命周期观察者类
class LifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  final VoidCallback onPause;

  LifecycleObserver({required this.onResume, required this.onPause});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        onResume();
        break;
      case AppLifecycleState.paused:
        onPause();
        break;
      default:
        break;
    }
  }
}
