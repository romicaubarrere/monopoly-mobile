import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import 'room_entry_components.dart';
import 'room_entry_models.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({
    required this.roomCode,
    required this.seats,
    required this.preset,
    required this.isHost,
    required this.isSelfReady,
    required this.canStart,
    this.onCopyRoomCode,
    this.onShareRoomCode,
    this.onToggleReady,
    this.onStartGame,
    this.isPending = false,
    this.errorMessage,
    super.key,
  });

  final String roomCode;
  final List<LobbySeatViewData> seats;
  final PresetViewData preset;
  final bool isHost;
  final bool isSelfReady;
  final bool canStart;
  final VoidCallback? onCopyRoomCode;
  final VoidCallback? onShareRoomCode;
  final ValueChanged<bool>? onToggleReady;
  final VoidCallback? onStartGame;
  final bool isPending;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 375;
            final gutter = compact ? AppSpacing.x3 : AppSpacing.x5;

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      AppSpacing.x5,
                      gutter,
                      AppSpacing.x4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const StampBadge(
                              label: 'Sala',
                              color: AppPalette.burgundy,
                              angle: -0.025,
                            ),
                            const SizedBox(width: AppSpacing.x3),
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  'La sala está armada',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        height: 1.05,
                                      ),
                                ),
                              ),
                            ),
                            const InkDoodle(size: 30),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.x4),
                        _RoomCodePanel(
                          roomCode: roomCode,
                          onCopy: isPending ? null : onCopyRoomCode,
                          onShare: isPending ? null : onShareRoomCode,
                        ),
                        const SizedBox(height: AppSpacing.x6),
                        _SectionHeading(
                          label: 'Jugadores',
                          countLabel: seats.isEmpty ? null : '${seats.length}',
                        ),
                        const SizedBox(height: AppSpacing.x3),
                        if (seats.isEmpty)
                          const InlineStatusMessage(
                            message: 'Esperando que se una alguien más.',
                          )
                        else
                          ...seats.map(
                            (seat) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.x2,
                              ),
                              child: _LobbySeatRow(seat: seat),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.x6),
                        const _SectionHeading(label: 'Preset'),
                        const SizedBox(height: AppSpacing.x3),
                        PresetOptionCard(
                          preset: preset,
                          isSelected: true,
                          onSelected: null,
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: AppSpacing.x4),
                          InlineStatusMessage(
                            message: errorMessage!,
                            isError: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _LobbyFooter(
                  gutter: gutter,
                  isHost: isHost,
                  isSelfReady: isSelfReady,
                  canStart: canStart,
                  isPending: isPending,
                  onToggleReady: onToggleReady,
                  onStartGame: onStartGame,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label, this.countLabel});

  final String label;
  final String? countLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppPalette.bottleGreen,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        if (countLabel != null) ...[
          const SizedBox(width: AppSpacing.x2),
          StampBadge(
            label: countLabel!,
            color: AppPalette.wornBlue,
            angle: 0.02,
          ),
        ],
      ],
    );
  }
}

class _RoomCodePanel extends StatelessWidget {
  const _RoomCodePanel({required this.roomCode, this.onCopy, this.onShare});

  final String roomCode;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;

  String get _displayCode {
    final clean = roomCode.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (clean.length <= 3) return clean;
    return '${clean.substring(0, 3)} ${clean.substring(3)}';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PaperPanel(
          background: AppPalette.surface,
          borderColor: AppPalette.burgundy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'CÓDIGO DE SALA',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppPalette.burgundy,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const StampBadge(
                    label: 'Compartí',
                    color: AppPalette.wornBlue,
                    angle: 0.025,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x3),
              Semantics(
                label:
                    'Código de sala ${_displayCode.replaceAll(' ', ', ')}',
                child: Text(
                  _displayCode,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    height: 1.05,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              Wrap(
                spacing: AppSpacing.x2,
                runSpacing: AppSpacing.x2,
                children: [
                  OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copiar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Compartir'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Positioned(
          right: 32,
          top: -7,
          child: TapeMark(width: 58, angle: 0.06),
        ),
      ],
    );
  }
}

class _LobbySeatRow extends StatelessWidget {
  const _LobbySeatRow({required this.seat});

  final LobbySeatViewData seat;

  @override
  Widget build(BuildContext context) {
    final statusText = seat.isReady ? 'Listo' : 'Falta confirmar';
    final statusIcon = seat.isReady
        ? Icons.check_circle_rounded
        : Icons.schedule_rounded;
    final statusColor = seat.isReady
        ? AppPalette.bottleGreen
        : AppPalette.inkSecondary;

    return Semantics(
      label:
          '${seat.displayName}${seat.isSelf ? ', vos' : ''}${seat.isHost ? ', host' : ''}${seat.isBot ? ', bot' : ''}. $statusText.',
      child: PaperPanel(
        background: AppPalette.surface,
        borderColor: seat.isReady
            ? AppPalette.bottleGreen
            : AppPalette.inkSecondary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x3,
        ),
        child: Row(
          children: [
            Icon(
              seat.isBot
                  ? Icons.smart_toy_outlined
                  : Icons.person_outline_rounded,
              semanticLabel: null,
              color: AppPalette.wornBlue,
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Wrap(
                spacing: AppSpacing.x2,
                runSpacing: AppSpacing.x1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    seat.displayName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (seat.isSelf) const _SmallBadge(label: 'VOS'),
                  if (seat.isHost) const _SmallBadge(label: 'HOST'),
                  if (seat.isBot) const _SmallBadge(label: 'BOT'),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Icon(statusIcon, color: statusColor, semanticLabel: null),
          ],
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: AppPalette.kraft,
        borderRadius: BorderRadius.circular(AppRadius.sign),
        border: Border.all(color: AppPalette.inkSecondary),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _LobbyFooter extends StatelessWidget {
  const _LobbyFooter({
    required this.gutter,
    required this.isHost,
    required this.isSelfReady,
    required this.canStart,
    required this.isPending,
    required this.onToggleReady,
    required this.onStartGame,
  });

  final double gutter;
  final bool isHost;
  final bool isSelfReady;
  final bool canStart;
  final bool isPending;
  final ValueChanged<bool>? onToggleReady;
  final VoidCallback? onStartGame;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? action;
    final String label;

    if (isHost) {
      action = canStart && !isPending ? onStartGame : null;
      label = isPending ? 'Iniciando…' : 'Empezar partida';
    } else {
      action = !isPending && onToggleReady != null
          ? () => onToggleReady!(!isSelfReady)
          : null;
      label = isPending
          ? 'Confirmando…'
          : isSelfReady
          ? 'Dejar de estar listo'
          : 'Estoy listo';
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        gutter,
        AppSpacing.x3,
        gutter,
        AppSpacing.x4,
      ),
      decoration: const BoxDecoration(
        color: AppPalette.canvas,
        border: Border(
          top: BorderSide(color: AppPalette.inkSecondary, width: 0.5),
        ),
      ),
      child: PaperPanel(
        background: AppPalette.surface,
        borderColor: AppPalette.bottleGreen,
        padding: const EdgeInsets.all(AppSpacing.x2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(onPressed: action, child: Text(label)),
            if (isHost && !canStart && !isPending) ...[
              const SizedBox(height: AppSpacing.x2),
              Text(
                'La partida se habilita cuando el estado de la sala lo permita.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppPalette.inkSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
