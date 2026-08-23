import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/tokens.dart';
import 'room_entry_components.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({
    required this.onJoinRoom,
    this.initialCode = '',
    this.isPending = false,
    this.errorMessage,
    super.key,
  });

  final ValueChanged<String>? onJoinRoom;
  final String initialCode;
  final bool isPending;
  final String? errorMessage;

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCode.toUpperCase());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _normalizedCode => _controller.text.trim().toUpperCase();

  bool get _canJoin =>
      _normalizedCode.length == 6 &&
      !widget.isPending &&
      widget.onJoinRoom != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 375;
            final gutter = compact ? AppSpacing.x3 : AppSpacing.x5;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                gutter,
                AppSpacing.x6,
                gutter,
                AppSpacing.x8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Entrá con el código de sala',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    'Son seis caracteres. Si algo falla, el código queda escrito para que puedas corregirlo o reintentar.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.inkSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  TextField(
                    controller: _controller,
                    enabled: !widget.isPending,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(6),
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                    ],
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submitIfEligible(),
                    decoration: InputDecoration(
                      labelText: 'Código de sala',
                      hintText: 'ABC123',
                      helperText: 'Podés pegarlo directamente.',
                      errorText: widget.errorMessage == null
                          ? null
                          : 'Revisá el mensaje debajo.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                    ),
                  ),
                  if (widget.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.x3),
                    InlineStatusMessage(
                      message: widget.errorMessage!,
                      isError: true,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.x5),
                  FilledButton(
                    onPressed: _canJoin ? _submitIfEligible : null,
                    child: Text(
                      widget.isPending ? 'Entrando…' : 'Unirse a sala',
                    ),
                  ),
                  if (!_canJoin && !widget.isPending) ...[
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      'Ingresá los 6 caracteres para continuar.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppPalette.inkSecondary),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _submitIfEligible() {
    if (!_canJoin) return;
    widget.onJoinRoom?.call(_normalizedCode);
  }
}
