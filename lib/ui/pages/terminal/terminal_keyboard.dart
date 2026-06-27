import 'dart:async';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// 终端底部小键盘，仅系统终端页显示，跟随键盘上抬
class TerminalKeyboard extends StatefulWidget {
  final Terminal terminal;
  const TerminalKeyboard({super.key, required this.terminal});

  @override
  State<TerminalKeyboard> createState() => _TerminalKeyboardState();
}

class _TerminalKeyboardState extends State<TerminalKeyboard> {
  String _mod = ''; // 当前激活的修饰键：ctrl / alt / shift / 空

  /// 向终端发送按键事件
  void _send(TerminalKey key, {bool ctrl = false, bool alt = false, bool shift = false}) {
    widget.terminal.keyInput(key, ctrl: ctrl, alt: alt, shift: shift);
  }

  /// 切换修饰键状态
  void _tapMod(String m) => setState(() => _mod = _mod == m ? '' : m);

  /// 修饰键弹出组合键行
  List<Widget> _modKeys() {
    if (_mod == 'ctrl') {
      // Ctrl 组合键：C(复制) V(粘贴) A(全选) X(剪切) Z(撤销) D(断开)
      return 'cvaxzd'.split('').map((ch) {
        final key = TerminalKey.values.firstWhere(
          (k) => k.name == 'key${ch.toUpperCase()}',
          orElse: () => TerminalKey.keyA,
        );
        return _pill(ch.toUpperCase(), () {
          _send(key, ctrl: true);
          setState(() => _mod = '');
        });
      }).toList();
    }
    if (_mod == 'alt') {
      return [
        _pill('Enter', () {
          _send(TerminalKey.enter, alt: true);
          setState(() => _mod = '');
        }),
      ];
    }
    if (_mod == 'shift') {
      // Shift 方向键：W A S D
      return 'wasd'.split('').map((ch) {
        final key = TerminalKey.values.firstWhere(
          (k) => k.name == 'key${ch.toUpperCase()}',
          orElse: () => TerminalKey.keyA,
        );
        return _pill(ch.toUpperCase(), () {
          _send(key, shift: true);
          setState(() => _mod = '');
        });
      }).toList();
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      margin: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 修饰键弹出行
          if (_mod.isNotEmpty)
            Container(
              height: 28,
              padding: const EdgeInsets.only(left: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: _modKeys(),
              ),
            ),
          // 主键盘行
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Ctrl / Alt / Shift 键组
                _modGroup(cs),
                const SizedBox(width: 8),
                // 滑动命令键
                Expanded(
                  child: SizedBox(
                    height: 24,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _pill('Esc', () => _send(TerminalKey.escape)),
                        _pill('Tab', () => _send(TerminalKey.tab)),
                        _repeatPill('↑', () => _send(TerminalKey.arrowUp)),
                        _repeatPill('↓', () => _send(TerminalKey.arrowDown)),
                        _repeatPill('←', () => _send(TerminalKey.arrowLeft)),
                        _repeatPill('→', () => _send(TerminalKey.arrowRight)),
                        _pill('Del', () => _send(TerminalKey.delete)),
                        _pill('PgUp', () => _send(TerminalKey.pageUp)),
                        _pill('PgDn', () => _send(TerminalKey.pageDown)),
                        _pill('Home', () => _send(TerminalKey.home)),
                        _pill('End', () => _send(TerminalKey.end)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 修饰键组 ───

  /// Ctrl / Alt / Shift 三个键包在一个圆角矩形框内
  Widget _modGroup(ColorScheme cs) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modItem('Ctrl', 'ctrl', true, false, cs),
          Container(width: 1, height: 16, color: cs.outlineVariant),
          _modItem('Alt', 'alt', false, false, cs),
          Container(width: 1, height: 16, color: cs.outlineVariant),
          _modItem('Shift', 'shift', false, true, cs),
        ],
      ),
    );
  }

  Widget _modItem(String label, String id, bool first, bool last, ColorScheme cs) {
    final a = _mod == id;
    return GestureDetector(
      onTap: () => _tapMod(id),
      child: Container(
        height: 24,
        constraints: const BoxConstraints(minWidth: 32),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: a ? cs.primaryContainer : Colors.transparent,
          borderRadius: first
              ? const BorderRadius.horizontal(left: Radius.circular(6))
              : last
                  ? const BorderRadius.horizontal(right: Radius.circular(6))
                  : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: a ? FontWeight.bold : FontWeight.w500,
            color: a ? cs.onPrimaryContainer : cs.primary,
          ),
        ),
      ),
    );
  }

  // ─── 命令按键 ───

  /// 单次触发的按键
  Widget _pill(String label, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 24,
            constraints: BoxConstraints(minWidth: label.length <= 1 ? 24 : 36),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: label.length <= 1 ? 0 : 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.primary),
            ),
          ),
        ),
      ),
    );
  }

  /// 带长按重复的按键（方向键用），长按1秒后每100ms持续触发
  Widget _repeatPill(String label, VoidCallback onTrigger) {
    return _RepeatBtnWidget(label: label, onTrigger: onTrigger);
  }
}

class _RepeatBtnWidget extends StatefulWidget {
  final String label;
  final VoidCallback onTrigger;

  const _RepeatBtnWidget({required this.label, required this.onTrigger});

  @override
  State<_RepeatBtnWidget> createState() => _RepeatBtnWidgetState();
}

class _RepeatBtnWidgetState extends State<_RepeatBtnWidget> {
  Timer? _timer;
  bool _holding = false;

  void _start() {
    _holding = true;
    widget.onTrigger();
    Future.delayed(const Duration(seconds: 1), () {
      if (!_holding || !mounted) return;
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!_holding || !mounted) return;
        widget.onTrigger();
      });
    });
  }

  void _stop() {
    _holding = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTapDown: (_) => _start(),
        onTapUp: (_) => _stop(),
        onTapCancel: _stop,
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: 24,
            constraints: BoxConstraints(minWidth: widget.label.length <= 1 ? 24 : 36),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: widget.label.length <= 1 ? 0 : 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              widget.label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.primary),
            ),
          ),
        ),
      ),
    );
  }
}
