import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/terminal_controller.dart';
import '../settings/settings_page.dart';
import '../terminal/terminal_tab_view.dart';
import '../../navbar/bottom_nav_bar.dart';

/// 原生 WebView Activity 的 MethodChannel
const _nativeWebViewChannel = MethodChannel('astrbot_native_webview');

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  int _currentIndex = 0;
  int _previousNavItemCount = 0;

  final HomeController homeController = Get.find<HomeController>();
  StreamSubscription? _readySub;
  StreamSubscription? _napcatReadySub;

  @override
  void initState() {
    super.initState();
    // 首次打开自动启动 AstrBot（未就绪则显示加载等待）
    if (homeController.isLocalhostDetected.value) {
      _openInNativeWebView('http://127.0.0.1:6185', 'AstrBot');
    }
    // 监听 AstrBot 就绪后自动加载（仅当前在 AstrBot 标签页时才打开）
    _readySub = homeController.isLocalhostDetected.listen((ready) {
      if (ready && _currentIndex == 0 && mounted) {
        _openInNativeWebView('http://127.0.0.1:6185', 'AstrBot');
      }
    });
    // 监听 NapCat 就绪后关闭旧 WebView，切回时会重新打开
    _napcatReadySub = homeController.napCatWebUiToken.listen((token) {
      if (token.isNotEmpty) {
        _nativeWebViewChannel.invokeMethod('closeWebView', 'NapCat');
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 依赖 Theme，需在 initState 之后调用；主题切换后同样会重新应用
    _initSystemUI();
  }

  @override
  void dispose() {
    _readySub?.cancel();
    _napcatReadySub?.cancel();
    _restoreSystemUI();
    super.dispose();
  }

  void _initSystemUI() {
    _applySystemUIOverlay();
  }

  void _restoreSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
  }

  /// 状态栏配色跟随当前主题，避免深色模式下出现白条与深色图标
  void _applySystemUIOverlay() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    ));
  }

  /// 在原生 Activity 中打开 WebView
  Future<void> _openInNativeWebView(String url, String title) async {
    try {
      final pxRatio = MediaQuery.of(context).devicePixelRatio;
      final bottomNavHeight = (MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight) * pxRatio;
      final topPadding = MediaQuery.of(context).padding.top * pxRatio;
      await _nativeWebViewChannel.invokeMethod('openMainView', {
        'url': url,
        'title': title,
        'navBarHeight': bottomNavHeight.toInt(),
        'statusBarHeight': topPadding.toInt(),
      });
    } catch (e) {
      debugPrint('Native WebView failed: $e');
      if (mounted) {
        Get.snackbar(
          '打开失败',
          '无法打开 WebView: $e',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }



  /// 隐藏原生 WebView，回到 Flutter 界面
  Future<void> _hideNativeWebView() async {
    try {
      await _nativeWebViewChannel.invokeMethod('hideWebView');
    } catch (e) {
      debugPrint('hideWebView error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final bool napCatEnabled = homeController.napCatWebUiEnabledRx.value;
      final customWebViews = homeController.customWebViews;

      final List<String> webTitles = [
        'AstrBot', // 索引 0
        if (napCatEnabled) 'NapCat', // 索引 1（如果启用）
        ...customWebViews.map((wv) => wv['title'] ?? wv['url'] ?? ''), // 自定义
      ];

      final int settingsIndex = webTitles.length + 1;
      final int currentNavItemCount = webTitles.length + 2;

      int validCurrentIndex = _currentIndex;
      if (_previousNavItemCount != 0 && _previousNavItemCount != currentNavItemCount) {
        validCurrentIndex = settingsIndex;
        _previousNavItemCount = currentNavItemCount;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _currentIndex = settingsIndex;
            });
          }
        });
      } else if (_previousNavItemCount == 0) {
        _previousNavItemCount = currentNavItemCount;
      }

      // 监听设置页点击"返回主页"的导航请求
      if (homeController.navigateToTab.value == 0) {
        homeController.navigateToTab.value = -1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _nativeWebViewChannel.invokeMethod('closeWebView', 'AstrBot');
            _openInNativeWebView('http://127.0.0.1:6185', 'AstrBot');
            setState(() {
              _currentIndex = 0;
            });
          }
        });
      }

      final ThemeData theme = Theme.of(context);
      final bool isDark = theme.brightness == Brightness.dark;

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        child: Scaffold(
          // Web 标签页时透明让 SurfaceView 下的 WebView 透出来
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              SafeArea(
                top: true,
                child: IndexedStack(
                  index: validCurrentIndex,
                  children: [
                    // 所有 Web 页面都是空占位，实际页面在原生 Activity 中打开
                    ...List.generate(webTitles.length, (index) {
                      final isAstrBotPage = index == 0;
                      final loading = isAstrBotPage && !homeController.isLocalhostDetected.value;
                      if (loading) {
                        return Obx(() => Container(
                          color: Theme.of(context).colorScheme.surface,
                          child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 200,
                                child: LinearProgressIndicator(
                                  value: homeController.progress.value,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(homeController.currentProgress.value, style: const TextStyle(fontSize: 14)),
                            ],
                          ),
                        )));
                      }
                      return const SizedBox(); // 空占位，WebView 在原生 Activity 中
                    }),

                    // 终端页面
                    const TerminalTabView(),

                    // 设置页面
                    const SettingsPage(key: PageStorageKey<String>('settings_page')),
                  ],
                ),
              ),
              // 状态栏区域铺主题背景色，避免透明背景露出底层黑色
              Positioned(
                top: 0, left: 0, right: 0,
                height: MediaQuery.of(context).padding.top,
                child: ColoredBox(color: theme.colorScheme.surface),
              ),
            ],
          ),
          bottomNavigationBar: WebViewBottomNavBar(
            currentIndex: validCurrentIndex,
            onTap: (int index) {
              // 判断是否为 Web 标签（不是终端和设置）
              if (index < webTitles.length) {
                // 获取对应的 URL
                String url;
                String title;
                if (index == 0) {
                  // AstrBot：未就绪时不打开 WebView，显示加载进度
                  if (!homeController.isLocalhostDetected.value) {
                    setState(() => _currentIndex = index);
                    return;
                  }
                  url = 'http://127.0.0.1:6185';
                  title = 'AstrBot';
                } else if (napCatEnabled && index == 1) {
                  // NapCat
                  final token = homeController.napCatWebUiToken.value;
                  url = token.isNotEmpty
                      ? 'http://127.0.0.1:6099/webui?token=$token'
                      : 'http://127.0.0.1:6099/webui';
                  title = 'NapCat';
                } else {
                  // 自定义 WebView
                  final customIndex = index - (napCatEnabled ? 2 : 1);
                  if (customIndex < customWebViews.length) {
                    final wv = customWebViews[customIndex];
                    url = wv['url'] ?? '';
                    title = wv['title'] ?? url;
                  } else {
                    return; // 无效索引
                  }
                }
                // 在原生 Activity 中打开
                _openInNativeWebView(url, title);
                setState(() {
                  _currentIndex = index;
                });
              } else {
                // 终端或设置标签 → 隐藏原生 WebView，切换 IndexedStack
                _hideNativeWebView();
                setState(() {
                  _currentIndex = index;
                });
              }
            },
          ),
        ),
      );
    });
  }
}
