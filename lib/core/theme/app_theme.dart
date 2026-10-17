import 'package:flutter/material.dart';
import 'package:settings/settings.dart';

/// 应用主题定义与主题模式控制
///
/// 深浅色使用同一品牌种子色，避免两套配色割裂。
/// 主题模式保存在全局 [ValueNotifier] 中，不依赖 GetX 的依赖注入时机，
/// 因此在 `GetMaterialApp` 初始化阶段即可安全读取。
class AppTheme {
  /// 品牌种子色，与原有浅色主题保持一致
  static final Color _seed = Colors.primaries[3];

  /// 持久化键名
  static const String _settingKey = 'theme_mode';

  /// 当前主题模式，默认跟随系统
  static final ValueNotifier<ThemeMode> modeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static ThemeData get light => ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.light,
      );

  static ThemeData get dark => ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
      );

  /// 从本地存储读取主题模式，应用启动时调用一次
  static void load() {
    modeNotifier.value = _decode(_settingKey.setting.get() as String?);
  }

  /// 切换主题模式并持久化
  static void setMode(ThemeMode mode) {
    if (modeNotifier.value == mode) return;
    modeNotifier.value = mode;
    _settingKey.setting.set(mode.name);
  }

  /// 主题模式的界面文案
  static String modeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  static ThemeMode _decode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
