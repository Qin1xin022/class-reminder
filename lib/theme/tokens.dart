import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────
/// 设计令牌（Design Tokens）
/// 界面里不直接写死颜色，而是用"语义化"的名字：
/// bg=页面底色 card=卡片底色 sub=次要文字 faint=最淡文字
/// 换主题/换深浅色时只改这里，全 App 自动跟随。
/// ─────────────────────────────────────────────────────────────

/// 可选主题色（设置页里那一排圆点）
const List<(String, Color)> kThemeSeeds = [
  ('经典蓝', Color(0xFF4C6FFF)),
  ('湖水青', Color(0xFF00A896)),
  ('青草绿', Color(0xFF2E9E5B)),
  ('森林绿', Color(0xFF2B8A3E)),
  ('蜜柑橙', Color(0xFFF76707)),
  ('蔷薇红', Color(0xFFE64980)),
  ('葡萄紫', Color(0xFF7048E8)),
  ('咖啡棕', Color(0xFF8D6E63)),
  ('石墨灰', Color(0xFF5C677D)),
];

const Color kDefaultSeed = Color(0xFF4C6FFF);

extension ToneX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// 当前主题色
  Color get primary => Theme.of(this).colorScheme.primary;

  /// 由主题色派生的渐变（同色相：深 → 浅）。
  /// 头图这类"大面积色块"统一走它，换任何主题色都自动相配，
  /// 不再写死某一种绿/蓝。
  LinearGradient get brandGradient {
    final hsl = HSLColor.fromColor(primary);
    if (isDark) {
      // 深色模式下压暗，白字才够对比
      final a = hsl
          .withLightness(0.17)
          .withSaturation(hsl.saturation * 0.85)
          .toColor();
      final b = hsl.withLightness(0.30).toColor();
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [a, b],
      );
    }
    final a = hsl
        .withLightness((hsl.lightness - 0.04).clamp(0.20, 0.62))
        .toColor();
    final b = hsl
        .withLightness((hsl.lightness + 0.24).clamp(0.0, 0.68))
        .withSaturation((hsl.saturation * 0.82).clamp(0.0, 1.0))
        .toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [a, b],
    );
  }

  /// 页面背景
  Color get bg => isDark ? const Color(0xFF111318) : const Color(0xFFF5F6FA);

  /// 卡片 / 输入框底色
  Color get card => isDark ? const Color(0xFF1D2027) : Colors.white;

  /// 次要文字（副标题、说明）
  Color get sub => isDark ? const Color(0xFFA8ADB8) : Colors.black54;

  /// 最淡文字（角标、时间戳）
  Color get faint => isDark ? const Color(0xFF6B7280) : Colors.black38;

  /// 分割线
  Color get divider => isDark ? const Color(0xFF2C313C) : const Color(0xFFE8EAF0);

  /// 主文字（标题），一般用默认即可，深色下是白
  Color get text => isDark ? const Color(0xFFE8EAF0) : Colors.black87;
}
