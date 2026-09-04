import 'package:board_backend_api/backend_api.dart';
import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../home_screen.dart';

/// Narrow presentation port for the live First Playable.
///
/// It exposes only public Authority data that the UI must render. Gameplay
/// legality, membership authorization and persistence remain server-owned.
abstract interface class LiveFirstPlayableAuthority {
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  });

  String? get latestCreatedRoomCode;

  Future<AuthorityPublicRoomSnapshot> refreshLobby();
}

final class ClientLiveFirstPlayableAuthority
    implements LiveFirstPlayableAuthority {
  const ClientLiveFirstPlayableAuthority(this.client);

  final FirstPlayableAuthorityClient client;

  @override
  String? get latestCreatedRoomCode => client.latestCreatedRoomCode;

  @override
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) => client.perform(action, input: input);

  @override
  Future<AuthorityPublicRoomSnapshot> refreshLobby() =>
      client.refreshConfirmedRoom();
}

enum _LiveStep {
  home,
  create,
  join,
  lobby,
  board,
  property,
  auction,
  reconnect,
}

class LiveFirstPlayableApp extends StatefulWidget {
  const LiveFirstPlayableApp({required this.authority, super.key});

  final LiveFirstPlayableAuthority authority;

  @override
  State<LiveFirstPlayableApp> createState() => _LiveFirstPlayableAppState();
}

class _LiveFirstPlayableAppState extends State<LiveFirstPlayableApp> {
  final _roomCodeController = TextEditingController();
  final _bidController = TextEditingController(text: '10');
  _LiveStep _step = _LiveStep.home;
  _LobbyView? _lobby;
  String? _roomCode;
  String? _safeError;
  bool _busy = false;

  @override
  void dispose() {
    _roomCodeController.dispose();
    _bidController.dispose();
    super.dispose();
  }

  Future<FirstPlayableAuthorityResult?> _perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _safeError = null;
    });
    try {
      final result = await widget.authority.perform(action, input: input);
      if (!mounted) return result;
      if (!result.accepted) {
        setState(() {
          _safeError = result.safeErrorCode ?? result.outcome.name;
        });
      }
      return result;
    } on Object {
      if (mounted) setState(() => _safeError = 'authorityBindingUnavailable');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _refreshLobby() async {
    try {
      final snapshot = await widget.authority.refreshLobby();
      final lobby = _LobbyView.fromSnapshot(snapshot);
      if (!mounted) return false;
      setState(() {
        _lobby = lobby;
        _safeError = null;
      });
      return true;
    } on Object {
      if (mounted) setState(() => _safeError = 'roomSnapshotUnavailable');
      return false;
    }
  }

  Future<void> _refreshLobbyAction() async {
    await _refreshLobby();
  }

  Future<void> _createRoom() async {
    final result = await _perform(FirstPlayableAuthorityAction.createRoom);
    if (result?.accepted != true) return;
    final code = widget.authority.latestCreatedRoomCode;
    if (code == null) {
      setState(() => _safeError = 'authorityRoomCodeUnavailable');
      return;
    }
    _roomCode = code;
    if (await _refreshLobby() && mounted) {
      setState(() => _step = _LiveStep.lobby);
    }
  }

  Future<void> _joinRoom() async {
    final code = _roomCodeController.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      setState(() => _safeError = 'invalidRoomCode');
      return;
    }
    final result = await _perform(
      FirstPlayableAuthorityAction.joinRoom,
      input: code,
    );
    if (result?.accepted != true) return;
    _roomCode = code;
    if (await _refreshLobby() && mounted) {
      setState(() => _step = _LiveStep.lobby);
    }
  }

  Future<void> _setReady() async {
    final result = await _perform(FirstPlayableAuthorityAction.setReady);
    if (result?.accepted == true) await _refreshLobby();
  }

  Future<void> _startGame() async {
    final result = await _perform(FirstPlayableAuthorityAction.startGame);
    if (result?.accepted == true && mounted) {
      setState(() => _step = _LiveStep.board);
    }
  }

  Future<void> _roll() async {
    final result = await _perform(FirstPlayableAuthorityAction.roll);
    if (result?.accepted == true && mounted) {
      setState(() => _step = _LiveStep.property);
    }
  }

  Future<void> _buy() async {
    final result = await _perform(FirstPlayableAuthorityAction.buyProperty);
    if (result?.accepted == true && mounted) {
      setState(() => _step = _LiveStep.reconnect);
    }
  }

  Future<void> _decline() async {
    final result = await _perform(FirstPlayableAuthorityAction.declineProperty);
    if (result?.accepted == true && mounted) {
      setState(() => _step = _LiveStep.auction);
    }
  }

  Future<void> _bid() async {
    await _perform(
      FirstPlayableAuthorityAction.placeBid,
      input: _bidController.text.trim(),
    );
  }

  Future<void> _passAuction() async {
    final result = await _perform(FirstPlayableAuthorityAction.passAuction);
    if (result?.accepted == true && mounted) {
      setState(() => _step = _LiveStep.reconnect);
    }
  }

  Future<void> _reconnect() async {
    final result = await _perform(FirstPlayableAuthorityAction.reconnect);
    if (result?.accepted == true && mounted) {
      setState(() => _step = _LiveStep.board);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        switch (_step) {
          _LiveStep.home => HomeScreen(
            onCreateRoom: () => setState(() => _step = _LiveStep.create),
            onJoinRoom: () => setState(() => _step = _LiveStep.join),
          ),
          _LiveStep.create => _Stage(
            key: const ValueKey('live-create'),
            label: 'ARMAR SALA',
            title: 'Creá una mesa',
            body: const Text(
              'El código aparece sólo después del ACK de Authority.',
            ),
            primaryLabel: 'Crear sala',
            onPrimary: _createRoom,
            onBack: () => setState(() => _step = _LiveStep.home),
          ),
          _LiveStep.join => _Stage(
            key: const ValueKey('live-join'),
            label: 'ENTRAR',
            title: 'Sumate con el código',
            body: TextField(
              key: const ValueKey('live-room-code-input'),
              controller: _roomCodeController,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Código de sala',
                border: OutlineInputBorder(),
              ),
            ),
            primaryLabel: 'Unirse',
            onPrimary: _joinRoom,
            onBack: () => setState(() => _step = _LiveStep.home),
          ),
          _LiveStep.lobby => _buildLobby(),
          _LiveStep.board => _Stage(
            key: const ValueKey('live-board'),
            label: 'TU TURNO',
            title: 'La vuelta está en marcha',
            body: const GameCard(
              child: Text(
                'El movimiento se aplica únicamente cuando Authority confirma el Roll.',
              ),
            ),
            primaryLabel: 'Tirar dados',
            onPrimary: _roll,
          ),
          _LiveStep.property => _Stage(
            key: const ValueKey('live-property'),
            label: 'PROPIEDAD',
            title: 'Decisión confirmada',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const GameCard(
                  child: Text(
                    'Los datos económicos vienen del snapshot confirmado. El contenido DEC-065 sigue fuera de este VP0.',
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                OutlinedButton(
                  onPressed: _busy ? null : _decline,
                  child: const Text('No comprar · abrir subasta'),
                ),
              ],
            ),
            primaryLabel: 'Comprar',
            onPrimary: _buy,
          ),
          _LiveStep.auction => _Stage(
            key: const ValueKey('live-auction'),
            label: 'SUBASTA',
            title: 'Subasta autoritativa',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _bidController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tu puja',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                OutlinedButton(
                  onPressed: _busy ? null : _passAuction,
                  child: const Text('Pasar'),
                ),
              ],
            ),
            primaryLabel: 'Pujar',
            onPrimary: _bid,
          ),
          _LiveStep.reconnect => _Stage(
            key: const ValueKey('live-reconnect'),
            label: 'RECONECTAR',
            title: 'Recuperá el estado confirmado',
            body: const GameCard(
              child: Text(
                'Reconnect reutiliza la identidad durable del comando incierto y reemplaza el snapshot local.',
              ),
            ),
            primaryLabel: 'Reconciliar',
            onPrimary: _reconnect,
          ),
        },
        if (_safeError != null)
          Positioned(
            left: AppSpacing.x3,
            right: AppSpacing.x3,
            bottom: AppSpacing.x3,
            child: Material(
              color: AppPalette.coralSoft,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.x3),
                child: Text(
                  'Authority · $_safeError',
                  key: const ValueKey('live-safe-error'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        if (_busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              key: ValueKey('live-authority-pending'),
            ),
          ),
      ],
    );
  }

  Widget _buildLobby() {
    final lobby = _lobby;
    if (lobby == null) {
      return _Stage(
        key: const ValueKey('live-lobby-loading'),
        label: 'LOBBY',
        title: 'Sincronizando la mesa',
        body: const Text('Esperando el snapshot público confirmado.'),
        primaryLabel: 'Actualizar lobby',
        onPrimary: _refreshLobbyAction,
      );
    }
    final actor = lobby.members.firstWhere(
      (member) => member.playerId == lobby.actorPlayerId,
    );
    return _Stage(
      key: const ValueKey('live-lobby'),
      label: 'LOBBY',
      title: 'La mesa está casi lista',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _roomCode == null ? 'SALA CONFIRMADA' : 'CÓDIGO · $_roomCode',
                  key: const ValueKey('live-authoritative-room-code'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.x3),
                for (final member in lobby.members) ...[
                  _LobbyMemberRow(member: member),
                  const SizedBox(height: AppSpacing.x2),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refreshLobbyAction,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Actualizar lobby'),
          ),
          if (!actor.ready) ...[
            const SizedBox(height: AppSpacing.x3),
            OutlinedButton.icon(
              onPressed: _busy ? null : _setReady,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Estoy lista'),
            ),
          ],
          if (lobby.actorPlayerId == lobby.hostPlayerId) ...[
            const SizedBox(height: AppSpacing.x3),
            FilledButton(
              onPressed: _busy ? null : _startGame,
              child: const Text('Empezar partida'),
            ),
          ],
        ],
      ),
      primaryLabel: 'Actualizar lobby',
      onPrimary: _refreshLobbyAction,
      hidePrimary: true,
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.label,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.onBack,
    this.hidePrimary = false,
    super.key,
  });

  final String label;
  final String title;
  final Widget body;
  final String primaryLabel;
  final Future<void> Function() onPrimary;
  final VoidCallback? onBack;
  final bool hidePrimary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: key,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (onBack != null)
                    IconButton(
                      onPressed: onBack,
                      tooltip: 'Volver',
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  Expanded(
                    child: GamePill(label: label, color: AppPalette.violet),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x4),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.x4),
              body,
              if (!hidePrimary) ...[
                const SizedBox(height: AppSpacing.x5),
                FilledButton(
                  onPressed: () => onPrimary(),
                  child: Text(primaryLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _LobbyView {
  const _LobbyView({
    required this.actorPlayerId,
    required this.hostPlayerId,
    required this.members,
  });

  factory _LobbyView.fromSnapshot(AuthorityPublicRoomSnapshot snapshot) {
    final value = snapshot.snapshot;
    final actorPlayerId = value['actorPlayerId'];
    final hostPlayerId = value['hostPlayerId'];
    final rawMembers = value['members'];
    if (actorPlayerId is! String ||
        actorPlayerId.isEmpty ||
        hostPlayerId is! String ||
        hostPlayerId.isEmpty ||
        rawMembers is! List<Object?>) {
      throw const FormatException('invalidPublicLobbySnapshot');
    }
    final members = rawMembers
        .map((raw) {
          if (raw is! Map<String, Object?>) {
            throw const FormatException('invalidPublicLobbyMember');
          }
          final playerId = raw['playerId'];
          final ready = raw['ready'];
          final kind = raw['kind'];
          if (playerId is! String ||
              playerId.isEmpty ||
              ready is! bool ||
              kind is! String ||
              kind.isEmpty) {
            throw const FormatException('invalidPublicLobbyMember');
          }
          return _LobbyMember(playerId: playerId, ready: ready, kind: kind);
        })
        .toList(growable: false);
    if (members.isEmpty ||
        !members.any((member) => member.playerId == actorPlayerId) ||
        !members.any((member) => member.playerId == hostPlayerId)) {
      throw const FormatException('invalidPublicLobbyMembership');
    }
    return _LobbyView(
      actorPlayerId: actorPlayerId,
      hostPlayerId: hostPlayerId,
      members: members,
    );
  }

  final String actorPlayerId;
  final String hostPlayerId;
  final List<_LobbyMember> members;
}

final class _LobbyMember {
  const _LobbyMember({
    required this.playerId,
    required this.ready,
    required this.kind,
  });

  final String playerId;
  final bool ready;
  final String kind;
}

class _LobbyMemberRow extends StatelessWidget {
  const _LobbyMemberRow({required this.member});

  final _LobbyMember member;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${member.playerId}. ${member.ready ? 'Listo' : 'No listo'}.',
      child: Container(
        key: ValueKey('live-member-${member.playerId}'),
        padding: const EdgeInsets.all(AppSpacing.x2),
        decoration: BoxDecoration(
          color: member.ready ? AppPalette.greenSoft : AppPalette.coralSoft,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            Icon(
              member.ready
                  ? Icons.check_circle_rounded
                  : Icons.hourglass_bottom_rounded,
              color: member.ready ? AppPalette.primary : AppPalette.coral,
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                '${member.playerId} · ${member.kind} · ${member.ready ? 'Listo' : 'No listo'}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
