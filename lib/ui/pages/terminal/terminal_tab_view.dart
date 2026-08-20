import 'package:flutter/material.dart';
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
  double? _pinchStartDistance;
  double? _pinchStartFontSize;
  bool _isPinching = false;

  static const double _fontSizeStep = 0.2;
  static const double _distancePerFontSizeStep = 24.0;

  ScrollController _scrollControllerFor(TerminalTab tab) {
    return _terminalScrollControllers.putIfAbsent(
      tab,
      () => ScrollController(),
    );
  }

  @override
  void dispose() {
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
          child: Listener(
            onPointerDown: (event) {
              _terminalPointers[event.pointer] = event.localPosition;
              if (_terminalPointers.length == 2) {
                final points = _terminalPointers.values.toList();
                _pinchStartDistance = (points[0] - points[1]).distance;
                _pinchStartFontSize = homeController.terminalFontSize.value;
                _isPinching = true;
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
              final sizeDelta = (distanceDelta / _distancePerFontSizeStep).round() * _fontSizeStep;
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
                _isPinching = false;
              }
              if (!wasPinching) _tryCopySelection(tab);
            },
            onPointerCancel: (event) {
              _terminalPointers.remove(event.pointer);
              _pinchStartDistance = null;
              _pinchStartFontSize = null;
            },
            child: ClipRect(
              child: TerminalView(
                tab.terminal,
                controller: tab.controller,
                readOnly: tab.type == TerminalTabType.fixed,
                backgroundOpacity: 1,
                theme: ManjaroTerminalTheme(),
                scrollController: _scrollControllerFor(tab),
                textStyle: TerminalStyle(fontSize: homeController.terminalFontSize.value),
              ),
            ),
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
