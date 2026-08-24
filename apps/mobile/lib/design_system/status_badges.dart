import 'package:flutter/material.dart';

import 'tokens.dart';

enum ConnectionBadgeState { online, unstable, reconnecting, offline }

class PlayerChip extends StatelessWidget {
  const PlayerChip({
    required this.name,
    super.key,
    this.isSelf = false,
    this.statusLabel,
    this.onTap,
  });

  final String name;
  final bool isSelf;
  final String? statusLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: BoxConstraints(
        minHeight: onTap == null ? 0 : AppSizes.minTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: AppSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        border: Border.all(color: AppPalette.ink, width: 1.2),
        borderRadius: BorderRadius.circular(AppRadius.control),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            offset: Offset(2, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSelf ? Icons.person : Icons.person_outline,
            size: 18,
            color: AppPalette.ink,
          ),
          const SizedBox(width: AppSpacing.x2),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
            ),
          ),
          if (statusLabel case final label?) ...[
            const SizedBox(width: AppSpacing.x2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.inkSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );

    final semanticsLabel = [name, if (isSelf) 'vos', ?statusLabel].join(', ');

    if (onTap == null) {
      return Semantics(label: semanticsLabel, child: content);
    }

    return Semantics(
      label: semanticsLabel,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class TurnBadge extends StatelessWidget {
  const TurnBadge({required this.label, super.key, this.isCurrent = false});

  final String label;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return _StatusBadge(
      icon: isCurrent ? Icons.casino : Icons.schedule,
      label: label,
      background: isCurrent ? AppPalette.mustard : AppPalette.kraft,
      foreground: AppPalette.ink,
      semanticLabel: isCurrent ? 'Turno actual, $label' : 'Turno, $label',
    );
  }
}

class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({required this.state, super.key, this.label});

  final ConnectionBadgeState state;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final presentation = switch (state) {
      ConnectionBadgeState.online => (
        Icons.wifi,
        AppPalette.bottleGreen,
        'Conectado',
      ),
      ConnectionBadgeState.unstable => (
        Icons.signal_wifi_statusbar_connected_no_internet_4,
        AppPalette.mustard,
        'Conexión inestable',
      ),
      ConnectionBadgeState.reconnecting => (
        Icons.sync,
        AppPalette.wornBlue,
        'Reconectando',
      ),
      ConnectionBadgeState.offline => (
        Icons.wifi_off,
        AppPalette.danger,
        'Sin conexión',
      ),
    };
    final effectiveLabel = label ?? presentation.$3;

    return _StatusBadge(
      icon: presentation.$1,
      label: effectiveLabel,
      background: presentation.$2,
      foreground: AppPalette.surface,
      semanticLabel: effectiveLabel,
    );
  }
}

class BotBadge extends StatelessWidget {
  const BotBadge({super.key, this.temporary = false, this.label});

  final bool temporary;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = label ?? (temporary ? 'Bot temporal' : 'Bot');

    return _StatusBadge(
      icon: Icons.smart_toy_outlined,
      label: effectiveLabel,
      background: temporary ? AppPalette.wornBlue : AppPalette.kraft,
      foreground: temporary ? AppPalette.surface : AppPalette.ink,
      semanticLabel: effectiveLabel,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: AppPalette.ink, width: 1.2),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: AppSpacing.x1),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
