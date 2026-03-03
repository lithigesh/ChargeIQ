import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class AppLottieLoader extends StatelessWidget {
  const AppLottieLoader({
    super.key,
    this.size = 84,
    this.width,
    this.height,
    this.color,
    this.strokeWidth = 4.0,
    this.valueColor,
    this.semanticsLabel,
    this.semanticsValue,
    this.fit = BoxFit.contain,
  });

  final double size;
  final double? width;
  final double? height;
  final Color? color;
  final double strokeWidth;
  final Animation<Color?>? valueColor;
  final String? semanticsLabel;
  final String? semanticsValue;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? valueColor?.value;
    final resolvedWidth = width ?? size;
    final resolvedHeight = height ?? size;

    Widget animation = SizedBox(
      width: resolvedWidth,
      height: resolvedHeight,
      child: Lottie.asset(
        'assets/carr.json',
        fit: fit,
        repeat: true,
      ),
    );

    if (tint != null) {
      animation = ColorFiltered(
        colorFilter: ColorFilter.mode(tint, BlendMode.srcATop),
        child: animation,
      );
    }

    return Semantics(
      label: semanticsLabel ?? 'Loading',
      value: semanticsValue,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasBoundedWidth = constraints.hasBoundedWidth;
          final hasBoundedHeight = constraints.hasBoundedHeight;

          final baseWidth = hasBoundedWidth ? constraints.maxWidth : resolvedWidth;
          final baseHeight = hasBoundedHeight ? constraints.maxHeight : resolvedHeight;

          final safeBaseWidth = baseWidth <= 0 ? resolvedWidth : baseWidth;
          final safeBaseHeight = baseHeight <= 0 ? resolvedHeight : baseHeight;

          final widthScale = resolvedWidth / safeBaseWidth;
          final heightScale = resolvedHeight / safeBaseHeight;
          final visualScale = widthScale > heightScale ? widthScale : heightScale;

          return Align(
            alignment: Alignment.center,
            child: Transform.scale(
              scale: visualScale < 1 ? 1 : visualScale,
              child: SizedBox(
                width: safeBaseWidth,
                height: safeBaseHeight,
                child: animation,
              ),
            ),
          );
        },
      ),
    );
  }
}
