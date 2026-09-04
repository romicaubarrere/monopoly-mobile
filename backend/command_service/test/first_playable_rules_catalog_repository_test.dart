import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

void main() {
  test(
    'new room pins the active server catalog and persisted rooms resolve it',
    () {
      final catalog = syntheticRollCatalog();
      final repository = _repository(catalog);

      expect(repository.catalogForNewRoom(presetId: 'express'), same(catalog));
      expect(
        repository.catalogForRoom(
          rulesVersion: catalog.rulesVersion,
          presetId: 'express',
        ),
        same(catalog),
      );
    },
  );

  test('unknown rules version or preset fails closed', () {
    final repository = _repository(syntheticRollCatalog());

    expect(
      () => repository.catalogForRoom(
        rulesVersion: 'unknown-rules',
        presetId: 'express',
      ),
      _violation('rulesCatalogUnavailable'),
    );
    expect(
      () => repository.catalogForNewRoom(presetId: 'client-invented'),
      _violation('presetCatalogUnavailable'),
    );
  });

  test('game load rejects a mutated frozen preset before Engine', () {
    final catalog = syntheticRollCatalog();
    final repository = _repository(catalog);
    final state = syntheticRollState();
    final mutatedPreset = <String, Object?>{
      ...state.presetConfig,
      'startingValue': 999999,
    };

    expect(
      () => repository.catalogForGame(_replacePreset(state, mutatedPreset)),
      _violation('persistedPresetCatalogMismatch'),
    );
  });

  test(
    'duplicate and unavailable active versions are rejected at bootstrap',
    () {
      final catalog = syntheticRollCatalog();
      expect(
        () => PinnedFirstPlayableRulesCatalogRepository(
          activeRulesVersion: catalog.rulesVersion,
          catalogs: <RulesCatalog>[catalog, catalog],
        ),
        _violation('duplicateRulesCatalogVersion'),
      );
      expect(
        () => PinnedFirstPlayableRulesCatalogRepository(
          activeRulesVersion: 'missing-rules',
          catalogs: <RulesCatalog>[catalog],
        ),
        _violation('activeRulesCatalogUnavailable'),
      );
    },
  );
}

PinnedFirstPlayableRulesCatalogRepository _repository(RulesCatalog catalog) =>
    PinnedFirstPlayableRulesCatalogRepository(
      activeRulesVersion: catalog.rulesVersion,
      catalogs: <RulesCatalog>[catalog],
    );

Matcher _violation(String code) => throwsA(
  isA<FirstPlayableRulesCatalogRepositoryViolation>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

PublicGameState _replacePreset(
  PublicGameState state,
  Map<String, Object?> presetConfig,
) => PublicGameState(
  header: state.header,
  presetConfig: presetConfig,
  roundState: state.roundState,
  turnState: state.turnState,
  players: state.players,
  seatControllers: state.seatControllers,
  board: state.board,
  ownership: state.ownership,
  bank: state.bank,
  freeParkingPot: state.freeParkingPot,
  deckPublicState: state.deckPublicState,
  pendingDecision: state.pendingDecision,
  activeAuction: state.activeAuction,
  activeTrade: state.activeTrade,
  debtCase: state.debtCase,
  result: state.result,
  lastMutation: state.lastMutation,
);
