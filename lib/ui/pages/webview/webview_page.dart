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

  @override
  void initState() {
    super.initState();
    _initSystemUI();
    // 监控自定义 WebView 列表变化，清空原生端缓存
    ever(homeController.customWebViews, (_) {
      _nativeWebViewChannel.invokeMethod('closeAllWebViews');
    });
    // NapCat 开关变化时也清缓存
    ever(homeController.napCatWebUiEnabledRx, (_) {
      _nativeWebViewChannel.invokeMethod('closeAllWebViews');
    });
    // 首次打开自动启动 AstrBot
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openInNativeWebView('http://127.0.0.1:6185', 'AstrBot', tabIndex: 0);
    });
  }

  @override
  void dispose() {
    _restoreSystemUI();
    super.dispose();
  }

  void _initSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));
  }

  void _restoreSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
  }

  /// 在原生 WebView Activity 中打开 URL
  Future<void> _openInNativeWebView(String url, String title, {int tabIndex = 0}) async {
    try {
      final pxRatio = MediaQuery.of(context).devicePixelRatio;
      final bottomNavHeight = (MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight) * pxRatio;
      final topPadding = MediaQuery.of(context).padding.top * pxRatio;
      await _nativeWebViewChannel.invokeMethod('openMainView', {
        'url': url,
        'title': title,
        'tabIndex': tabIndex,
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
  }  @override
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

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: Scaffold(
          // Web 标签页时透明让 SurfaceView 下的 WebView 透出来
          backgroundColor: validCurrentIndex < webTitles.length ? Colors.transparent : Colors.white,
          body: Stack(
            children: [
              SafeArea(
                top: true,
                child: IndexedStack(
                  index: validCurrentIndex,
                  children: [
                    // 所有 Web 页面都是空占位，实际页面在原生 Activity 中打开
                    ...List.generate(webTitles.length, (index) {
                      final isWebTab = true;
                      return const SizedBox(); // 空占位，WebView 在原生 Activity 中
                    }),

                    // 终端页面
                    const TerminalTabView(),

                    // 设置页面
                    const SettingsPage(),
                  ],
                ),
              ),
              // Web 标签页的状态栏区域画白，避免透明背景露黑
              if (validCurrentIndex < webTitles.length)
                Positioned(
                  top: 0, left: 0, right: 0,
                  height: MediaQuery.of(context).padding.top,
                  child: const ColoredBox(color: Colors.white),
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
                  // AstrBot
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
                _openInNativeWebView(url, title, tabIndex: index);
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
