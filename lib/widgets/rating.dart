import 'package:flutter/material.dart';
import '../theme/tokens.dart';

const Color kStarColor = Color(0xFFF59F00);

/// 可点的 5 星自评。再点一次当前星级可以清零。
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 24,
    this.color = kStarColor,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final n = i + 1;
        final active = n <= value;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(n == value ? 0 : n),
          child: Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(
              active ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: active ? color : context.faint,
            ),
          ),
        );
      }),
    );
  }
}

/// 只读星条，用于列表展示
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.value, this.size = 13, this.color = kStarColor});

  final int value;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < value ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: i < value ? color : context.faint,
        ),
      ),
    );
  }
}
