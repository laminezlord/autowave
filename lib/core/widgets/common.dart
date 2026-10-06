import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../theme/app_theme.dart';

void showSnack(BuildContext context, String text) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(text)));
}

void showError(BuildContext context, Object e) => showSnack(context, friendlyError(e));

/// Primary button that shows a spinner while [onPressed] runs.
class BusyButton extends StatefulWidget {
  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final Color? background;
  final Color? foreground;

  const BusyButton({super.key, required this.label, required this.onPressed, this.icon, this.background, this.foreground});

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.foreground ?? Colors.white;
    return ElevatedButton(
      onPressed: widget.onPressed == null ? null : _run,
      style: widget.background == null
          ? null
          : ElevatedButton.styleFrom(backgroundColor: widget.background, foregroundColor: fg),
      child: _busy
          ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[Icon(widget.icon, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );
  }
}

class Stars extends StatelessWidget {
  final double rating;
  final double size;
  const Stars({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final v = rating - i;
        final icon = v >= 0.75 ? Icons.star_rounded : (v >= 0.25 ? Icons.star_half_rounded : Icons.star_outline_rounded);
        return Icon(icon, size: size, color: AppColors.star);
      }),
    );
  }
}

/// "★ 4.8 (126)" in one compact line.
class RatingInline extends StatelessWidget {
  final double avg;
  final int count;
  const RatingInline({super.key, required this.avg, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return const Text('New on AutoWave', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.go));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 17, color: AppColors.star),
        const SizedBox(width: 3),
        Text(avg.toStringAsFixed(1), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(width: 4),
        Text('($count ${count == 1 ? 'review' : 'reviews'})', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      ],
    );
  }
}

class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color background;
  final Color foreground;
  const InitialsAvatar({super.key, required this.name, this.size = 48, this.background = AppColors.signalSoft, this.foreground = AppColors.ink});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Text(_initials, style: TextStyle(fontFamily: AppText.display, fontWeight: FontWeight.w800, fontSize: size * 0.36, color: foreground)),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  final IconData? icon;
  const Pill({super.key, required this.text, required this.color, required this.background, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
          Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
            child: Icon(icon, size: 30, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppText.h3),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: AppText.body.copyWith(color: AppColors.muted)),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

/// White block with a hairline border. Radius 18 for content, sheets use 24.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final VoidCallback? onTap;
  final Color borderColor;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = Colors.white, this.onTap, this.borderColor = AppColors.line});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(18);
    return Material(
      color: color,
      borderRadius: r,
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(borderRadius: r, border: Border.all(color: borderColor)),
          child: child,
        ),
      ),
    );
  }
}

/// Banner shown on every screen in demo mode.
class DemoRibbon extends StatelessWidget {
  const DemoRibbon({super.key});

  @override
  Widget build(BuildContext context) {
    if (!backend.isDemo) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.signal,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: const Text('Demo mode: sample data, no real money',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)),
    );
  }
}

/// Small helper for the hairline-separated "label ... value" rows.
class KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  const KeyValueRow(this.label, this.value, {super.key, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body.copyWith(color: AppColors.muted))),
          Text(value, style: AppText.body.copyWith(color: AppColors.ink, fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }
}
