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
        return _Btn(
          label: ch.toUpperCase(),
          onTap: () {
            _send(key, ctrl: true);
            setState(() => _mod = '');
          },
        );
      }).toList();
    }
    if (_mod == 'alt') {
      return [
        _Btn(
          label: 'Enter',
          onTap: () {
            _send(TerminalKey.enter, alt: true);
            setState(() => _mod = '');
          },
        ),
      ];
    }
    if (_mod == 'shift') {
      // Shift 方向键：W A S D
      return 'wasd'.split('').map((ch) {
        final key = TerminalKey.values.firstWhere(
          (k) => k.name == 'key${ch.toUpperCase()}',
          orElse: () => TerminalKey.keyA,
        );
        return _Btn(
          label: ch.toUpperCase(),
          onTap: () {
            _send(key, shift: true);
            setState(() => _mod = '');
          },
        );
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
                _ModGroup(active: _mod, onTap: _tapMod),
                const SizedBox(width: 8),
                // 滑动命令键
                Expanded(
                  child: SizedBox(
                    height: 24,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _Btn(label: 'Esc', onTap: () => _send(TerminalKey.escape)),
                        _Btn(label: 'Tab', onTap: () => _send(TerminalKey.tab)),
                        _Btn(label: '↑', onTap: () => _send(TerminalKey.arrowUp)),
                        _Btn(label: '↓', onTap: () => _send(TerminalKey.arrowDown)),
                        _Btn(label: '←', onTap: () => _send(TerminalKey.arrowLeft)),
                        _Btn(label: '→', onTap: () => _send(TerminalKey.arrowRight)),
                        _Btn(label: 'Del', onTap: () => _send(TerminalKey.delete)),
                        _Btn(label: 'PgUp', onTap: () => _send(TerminalKey.pageUp)),
                        _Btn(label: 'PgDn', onTap: () => _send(TerminalKey.pageDown)),
                        _Btn(label: 'Home', onTap: () => _send(TerminalKey.home)),
                        _Btn(label: 'End', onTap: () => _send(TerminalKey.end)),
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
}

/// Ctrl / Alt / Shift 修饰键组，包在一个圆角矩形框内
class _ModGroup extends StatelessWidget {
  final String active;
  final void Function(String) onTap;

  const _ModGroup({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
    final a = active == id;
    return GestureDetector(
      onTap: () => onTap(id),
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
            color: a ? cs.onPrimaryContainer : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

/// 药丸形按键，大圆角，单字符时宽高相等呈正圆
class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _Btn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
