import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/ui/controller.dart';

import '../../controllers/terminal_controller.dart';
import '../../controllers/terminal_tab_manager.dart';
import 'terminal_keyboard.dart';
import 'terminal_theme.dart';

/// 终端标签页视图
class TerminalTabView extends StatefulWidget {
  const TerminalTabView({super.key});

  @override
  State<TerminalTabView> createState() => _TerminalTabViewState();
}

class _TerminalTabViewState extends State<TerminalTabView> {
  final HomeController homeController = Get.find<HomeController>();
  bool _isCopyDialogOpen = false;
  final Map<int, Offset> _terminalPointers = <int, Offset>{};
  final Map<TerminalTab, ScrollController> _terminalScrollControllers =
      <TerminalTab, ScrollController>{};
  final Set<TerminalTab> _tabsShowingScrollToLatest = <TerminalTab>{};
  final Set<TerminalTab> _tabsWithActiveUserScroll = <TerminalTab>{};
  final Map<TerminalTab, Timer> _scrollToLatestHideTimers =
      <TerminalTab, Timer>{};
  double? _pinchStartDistance;
  double? _pinchStartFontSize;
  bool _isPinching = false;

  static const double _fontSizeStep = 0.1;
  static const double _distancePerFontSizeStep = 24.0;

  ScrollController _scrollControllerFor(TerminalTab tab) {
    return _terminalScrollControllers.putIfAbsent(
      tab,
      () => ScrollController(),
    );
  }

  @override
  void dispose() {
    for (final timer in _scrollToLatestHideTimers.values) {
      timer.cancel();
    }
    for (final controller in _terminalScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setTerminalFontSize(TerminalTab tab, double size) {
    final scrollController = _scrollControllerFor(tab);
    final oldFontSize = homeController.terminalFontSize.value;
    final wasAtBottom = scrollController.hasClients &&
        scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 1;
    final oldOffset = scrollController.hasClients
        ? scrollController.position.pixels
        : 0.0;

    homeController.setTerminalFontSize(size);
    final newFontSize = homeController.terminalFontSize.value;
    if (!scrollController.hasClients || oldFontSize == newFontSize) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      final maxScrollExtent = scrollController.position.maxScrollExtent;
      final newOffset = wasAtBottom
          ? maxScrollExtent
          : oldOffset * newFontSize / oldFontSize;
      scrollController.jumpTo(newOffset.clamp(0.0, maxScrollExtent));
    });
  }

  bool _isActiveTerminalTab(TerminalTab tab) {
    final manager = homeController.terminalTabManager;
    final activeIndex = manager.activeTabIndex.value;
    return activeIndex >= 0 &&
        activeIndex < manager.tabs.length &&
        identical(manager.tabs[activeIndex], tab);
  }

  void _showScrollToLatest(TerminalTab tab) {
    _scrollToLatestHideTimers.remove(tab)?.cancel();
    if (_tabsShowingScrollToLatest.add(tab)) {
      setState(() {});
    }
  }

  void _scheduleScrollToLatestHide(TerminalTab tab) {
    if (_scrollToLatestHideTimers.containsKey(tab)) return;
    _scrollToLatestHideTimers[tab] = Timer(const Duration(seconds: 3), () {
      _scrollToLatestHideTimers.remove(tab);
      if (!mounted || !_tabsShowingScrollToLatest.remove(tab)) return;
      setState(() {});
    });
  }

  void _hideScrollToLatest(TerminalTab tab) {
    _scrollToLatestHideTimers.remove(tab)?.cancel();
    if (_tabsShowingScrollToLatest.remove(tab)) {
      setState(() {});
    }
  }

  bool _onTerminalScroll(
    TerminalTab tab,
    ScrollNotification notification,
  ) {
    if (!_isActiveTerminalTab(tab)) return false;

    if (notification.metrics.extentAfter <= 1.0) {
      _hideScrollToLatest(tab);
      return false;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.idle) {
        _tabsWithActiveUserScroll.remove(tab);
        if (_tabsShowingScrollToLatest.contains(tab)) {
          _scheduleScrollToLatestHide(tab);
        }
      } else {
        _tabsWithActiveUserScroll.add(tab);
      }
    } else if (notification is ScrollUpdateNotification &&
        _tabsWithActiveUserScroll.contains(tab)) {
      final scrollDelta = notification.scrollDelta;
      if (scrollDelta != null && scrollDelta > 0) {
        _showScrollToLatest(tab);
      } else if (scrollDelta != null &&
          scrollDelta < 0 &&
          _tabsShowingScrollToLatest.contains(tab)) {
        _scheduleScrollToLatestHide(tab);
      }
    }

    return false;
  }

  void _scrollToLatest(TerminalTab tab) {
    final controller = _scrollControllerFor(tab);
    if (!controller.hasClients) return;

    unawaited(controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    ));
    _hideScrollToLatest(tab);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final manager = homeController.terminalTabManager;
      final tabs = manager.tabs;
      final activeIndex = manager.activeTabIndex.value;

      if (tabs.isEmpty) {
        return const Center(
          child: Text('暂无终端'),
        );
      }

      return Column(
        children: [
          // 标签页头部
          _buildTabBar(tabs, activeIndex, manager),

          // 终端内容区域
          Expanded(
            child: IndexedStack(
              index: activeIndex,
              children: tabs.map((tab) {
                return _buildTerminalContent(tab);
              }).toList(),
            ),
          ),
        ],
      );
    });
  }

  /// 构建标签页栏
  Widget _buildTabBar(
    List<TerminalTab> tabs,
    int activeIndex,
    TerminalTabManager manager,
  ) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 标签页列表（可滚动）
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                return _buildTabItem(
                  tab: tabs[index],
                  isActive: index == activeIndex,
                  onTap: () => manager.switchToTab(index),
                  onClose: tabs[index].type == TerminalTabType.system
                      ? () => _showCloseConfirmDialog(index, manager)
                      : null,
                );
              },
            ),
          ),

          // 添加新终端按钮
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => manager.addSystemTerminalTab(),
            tooltip: '添加新终端',
          ),
        ],
      ),
    );
  }

  /// 构建单个标签页项
  Widget _buildTabItem({
    required TerminalTab tab,
    required bool isActive,
    required VoidCallback onTap,
    VoidCallback? onClose,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
          minWidth: 120,
          maxWidth: 200,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标签页图标
            Icon(
              tab.type == TerminalTabType.fixed
                  ? Icons.lock_outline
                  : Icons.terminal,
              size: 16,
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),

            // 标签页标题
            Flexible(
              child: Text(
                tab.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 关闭按钮（只有系统终端才显示）
            if (onClose != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建终端内容
  Widget _buildTerminalContent(TerminalTab tab) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerDown: (event) {
                    _terminalPointers[event.pointer] = event.localPosition;
                    if (_terminalPointers.length == 2) {
                      final points = _terminalPointers.values.toList();
                      _pinchStartDistance =
                          (points[0] - points[1]).distance;
                      _pinchStartFontSize =
                          homeController.terminalFontSize.value;
                      if (!_isPinching) {
                        setState(() => _isPinching = true);
                      }
                    }
                  },
                  onPointerMove: (event) {
                    if (!_terminalPointers.containsKey(event.pointer)) return;
                    _terminalPointers[event.pointer] = event.localPosition;
                    if (_terminalPointers.length != 2 ||
                        _pinchStartDistance == null ||
                        _pinchStartFontSize == null) {
                      return;
                    }

                    final points = _terminalPointers.values.toList();
                    final distance = (points[0] - points[1]).distance;
                    final distanceDelta = distance - _pinchStartDistance!;
                    final sizeDelta =
                        (distanceDelta / _distancePerFontSizeStep).round() *
                            _fontSizeStep;
                    _setTerminalFontSize(
                      tab,
                      _pinchStartFontSize! + sizeDelta,
                    );
                  },
                  onPointerUp: (event) {
                    _terminalPointers.remove(event.pointer);
                    final wasPinching = _isPinching;
                    if (_terminalPointers.isEmpty) {
                      _pinchStartDistance = null;
                      _pinchStartFontSize = null;
                      if (_isPinching) {
                        setState(() => _isPinching = false);
                      }
                    }
                    if (!wasPinching) _tryCopySelection(tab);
                  },
                  onPointerCancel: (event) {
                    _terminalPointers.remove(event.pointer);
                    _pinchStartDistance = null;
                    _pinchStartFontSize = null;
                    if (_isPinching) {
                      setState(() => _isPinching = false);
                    }
                  },
                  child: ClipRect(
                    child: Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (notification) =>
                              _onTerminalScroll(tab, notification),
                          child: TerminalView(
                            tab.terminal,
                            controller: tab.controller,
                            readOnly: tab.type == TerminalTabType.fixed,
                            backgroundOpacity: 1,
                            theme: ManjaroTerminalTheme(),
                            scrollController: _scrollControllerFor(tab),
                            textStyle: TerminalStyle(
                              fontSize:
                                  homeController.terminalFontSize.value,
                            ),
                          ),
                        ),
                        if (_isPinching)
                          Positioned.fill(
                            child: Align(
                              alignment: const Alignment(0, -0.5),
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.72),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    child: Text(
                                      '字体大小 ${homeController.terminalFontSize.value.toStringAsFixed(1)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: IgnorePointer(
                  ignoring: !_tabsShowingScrollToLatest.contains(tab),
                  child: AnimatedOpacity(
                    opacity:
                        _tabsShowingScrollToLatest.contains(tab) ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    child: Tooltip(
                      message: '滚动到最新输出',
                      child: Material(
                        color: tab.type == TerminalTabType.system
                            ? Theme.of(context).colorScheme.surface
                            : Colors.white,
                        elevation: 2,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _scrollToLatest(tab),
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (tab.type == TerminalTabType.system)
          TerminalKeyboard(terminal: tab.terminal),
      ],
    );
  }

  Future<void> _tryCopySelection(TerminalTab tab) async {
    if (_isCopyDialogOpen) return;

    final range = tab.controller.selection;
    if (range != null && !range.isCollapsed) {
      final text = tab.terminal.buffer.getText(range);
      if (text.isNotEmpty) {
        _isCopyDialogOpen = true;
        try {
          String displayText = text;
          if (text.length > 300) {
            displayText = text.substring(0, 300) + '\n... (共 ${text.length} 个字符，已折叠)';
          }

          final shouldCopy = await Get.dialog<bool>(
            AlertDialog(
              title: const Text('复制终端文本'),
              content: Text('$displayText\n\n是否复制已选中的文本？'),
              actions: [
                TextButton(
                  onPressed: () => Get.back(result: false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Get.back(result: true),
                  child: const Text('复制'),
                ),
              ],
            ),
            barrierDismissible: true,
          );
          if (shouldCopy == true) {
            await Clipboard.setData(ClipboardData(text: text));
            Get.snackbar(
              '已复制',
              '终端文本已复制到剪贴板',
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(seconds: 2),
            );
          }
        } finally {
          _isCopyDialogOpen = false;
          tab.controller.clearSelection();
        }
      }
    }
  }

  /// 显示关闭确认对话框
  void _showCloseConfirmDialog(int index, TerminalTabManager manager) {
    Get.dialog(
      AlertDialog(
        title: const Text('确认关闭'),
        content: const Text('确定要关闭这个终端吗？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              manager.closeTab(index);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
