import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';

class VerticalBoardB extends StatefulWidget {
  const VerticalBoardB({
    required this.currentPosition,
    super.key,
    this.highlightedPosition,
    this.onInspectPosition,
    this.height = 380,
  }) : assert(currentPosition >= 0 && currentPosition < 40),
       assert(
         highlightedPosition == null ||
             (highlightedPosition >= 0 && highlightedPosition < 40),
       );

  final int currentPosition;
  final int? highlightedPosition;
  final ValueChanged<int>? onInspectPosition;
  final double height;

  @override
  State<VerticalBoardB> createState() => _VerticalBoardBState();
}

class _VerticalBoardBState extends State<VerticalBoardB> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant VerticalBoardB oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPosition != widget.currentPosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _followCurrent());
    }
  }

  void _followCurrent() {
    if (!mounted || !_controller.hasClients) return;
    const tileExtent = 68.0;
    final target =
        (widget.currentPosition * tileExtent) -
        (_controller.position.viewportDimension / 2) +
        (tileExtent / 2);
    final offset = target
        .clamp(
          _controller.position.minScrollExtent,
          _controller.position.maxScrollExtent,
        )
        .toDouble();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _controller.jumpTo(offset);
    } else {
      _controller.animateTo(
        offset,
        duration: AppMotion.page,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.highlightedPosition;
    final summary = destination == null
        ? 'Tablero vertical de 40 posiciones PLACEHOLDER. Ficha en la posición ${widget.currentPosition + 1}.'
        : 'Tablero vertical de 40 posiciones PLACEHOLDER. Ficha en la posición ${widget.currentPosition + 1}. Destino confirmado ${destination + 1}.';

    return Semantics(
      container: true,
      label: summary,
      excludeSemantics: widget.onInspectPosition == null,
      explicitChildNodes: widget.onInspectPosition != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MiniMap(
            currentPosition: widget.currentPosition,
            highlightedPosition: destination,
          ),
          const SizedBox(height: AppSpacing.x3),
          SizedBox(
            height: widget.height,
            child: GameCard(
              padding: const EdgeInsets.all(AppSpacing.x2),
              background: AppPalette.greenSoft,
              child: ListView.separated(
                controller: _controller,
                itemCount: 40,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.x2),
                itemBuilder: (context, index) => _BoardTile(
                  index: index,
                  isCurrent: index == widget.currentPosition,
                  isDestination: index == destination,
                  onTap: widget.onInspectPosition == null
                      ? null
                      : () => widget.onInspectPosition!(index),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({
    required this.currentPosition,
    required this.highlightedPosition,
  });

  final int currentPosition;
  final int? highlightedPosition;

  @override
  Widget build(BuildContext context) {
    return GameCard(
      padding: const EdgeInsets.all(AppSpacing.x3),
      background: AppPalette.violetSoft,
      borderColor: AppPalette.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: List.generate(40, (index) {
              final current = index == currentPosition;
              final destination = index == highlightedPosition;
              return Expanded(
                child: Container(
                  key: ValueKey('b-map-$index'),
                  height: current
                      ? 22
                      : destination
                      ? 17
                      : 9,
                  margin: EdgeInsets.only(left: index == 0 ? 0 : 1),
                  decoration: BoxDecoration(
                    color: current
                        ? AppPalette.primary
                        : destination
                        ? AppPalette.coral
                        : AppPalette.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: (current || destination)
                        ? Border.all(color: AppPalette.ink, width: 1)
                        : null,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.x2),
          Row(
            children: [
              Expanded(
                child: Text(
                  'SALIDA',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Expanded(
                child: Text(
                  '${currentPosition + 1} / 40',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppPalette.violet,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'LA VUELTA',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({
    required this.index,
    required this.isCurrent,
    required this.isDestination,
    required this.onTap,
  });

  final int index;
  final bool isCurrent;
  final bool isDestination;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = [
      if (isCurrent) 'tu ficha',
      if (isDestination) 'destino confirmado',
    ].join(', ');
    final label = 'Casillero PLACEHOLDER ${index + 1}';

    final tile = Container(
      key: ValueKey('b-board-tile-$index'),
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: AppSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppPalette.greenSoft
            : isDestination
            ? AppPalette.coralSoft
            : AppPalette.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: isCurrent
              ? AppPalette.primary
              : isDestination
              ? AppPalette.coral
              : AppPalette.ink.withValues(alpha: 0.18),
          width: isCurrent || isDestination ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrent ? AppPalette.primary : AppPalette.violetSoft,
              shape: isCurrent ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: isCurrent
                  ? null
                  : BorderRadius.circular(AppRadius.control),
            ),
            child: isCurrent
                ? const Icon(
                    Icons.pets_rounded,
                    color: AppPalette.surface,
                    size: 19,
                  )
                : Text(
                    '${index + 1}',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (state.isNotEmpty)
                  Text(
                    state,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppPalette.inkSecondary),
                  ),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );

    if (onTap == null) return ExcludeSemantics(child: tile);
    return Semantics(
      button: true,
      label: state.isEmpty ? label : '$label, $state',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: tile,
      ),
    );
  }
}
