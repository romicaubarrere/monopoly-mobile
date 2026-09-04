import 'package:board_game_core/game_core.dart';

final class FirstPlayableRulesCatalogRepositoryViolation implements Exception {
  const FirstPlayableRulesCatalogRepositoryViolation(this.code);

  final String code;

  @override
  String toString() => 'FirstPlayableRulesCatalogRepositoryViolation: $code';
}

/// Server-owned catalog boundary for the First Playable Authority.
///
/// Flutter sends only the room preset identifier. New rooms are pinned to the
/// server's active immutable catalog; every later room/game load resolves that
/// exact persisted [rulesVersion]. Unknown or inconsistent persisted material
/// fails closed before an Engine planner runs.
abstract interface class FirstPlayableRulesCatalogRepository {
  RulesCatalog catalogForNewRoom({required String presetId});

  RulesCatalog catalogForRoom({
    required String rulesVersion,
    required String presetId,
  });

  RulesCatalog catalogForGame(PublicGameState state);
}

/// Immutable in-process registry suitable for a server composition root.
///
/// A production bootstrap may construct this registry from signed/bundled
/// server assets. Catalog JSON is deliberately not accepted over HTTP or from
/// public Firestore documents.
final class PinnedFirstPlayableRulesCatalogRepository
    implements FirstPlayableRulesCatalogRepository {
  PinnedFirstPlayableRulesCatalogRepository({
    required String activeRulesVersion,
    required Iterable<RulesCatalog> catalogs,
  }) : _activeRulesVersion = activeRulesVersion,
       _catalogs = _index(catalogs) {
    if (!_catalogs.containsKey(activeRulesVersion)) {
      throw const FirstPlayableRulesCatalogRepositoryViolation(
        'activeRulesCatalogUnavailable',
      );
    }
  }

  final String _activeRulesVersion;
  final Map<String, RulesCatalog> _catalogs;

  @override
  RulesCatalog catalogForNewRoom({required String presetId}) {
    final catalog = _catalogs[_activeRulesVersion]!;
    _requirePreset(catalog, presetId);
    return catalog;
  }

  @override
  RulesCatalog catalogForRoom({
    required String rulesVersion,
    required String presetId,
  }) {
    final catalog = _requireCatalog(rulesVersion);
    _requirePreset(catalog, presetId);
    return catalog;
  }

  @override
  RulesCatalog catalogForGame(PublicGameState state) {
    final catalog = _requireCatalog(state.header.rulesVersion);
    if (state.board['boardId'] != catalog.boardDefinition.boardId ||
        state.board['boardDefinitionVersion'] !=
            catalog.boardDefinitionVersion) {
      throw const FirstPlayableRulesCatalogRepositoryViolation(
        'persistedBoardCatalogMismatch',
      );
    }
    final presetId = state.presetConfig['presetId'];
    if (presetId is! String || presetId.isEmpty) {
      throw const FirstPlayableRulesCatalogRepositoryViolation(
        'persistedPresetInvalid',
      );
    }
    final expected = ResolvedPresetConfig.freeze(
      _requirePreset(catalog, presetId),
      catalog.presetCatalogVersion,
    ).toCanonicalJson();
    if (CanonicalDomainJson.encode(state.presetConfig) != expected) {
      throw const FirstPlayableRulesCatalogRepositoryViolation(
        'persistedPresetCatalogMismatch',
      );
    }
    return catalog;
  }

  RulesCatalog _requireCatalog(String rulesVersion) {
    final catalog = _catalogs[rulesVersion];
    if (catalog == null) {
      throw const FirstPlayableRulesCatalogRepositoryViolation(
        'rulesCatalogUnavailable',
      );
    }
    return catalog;
  }

  static PresetDefinition _requirePreset(
    RulesCatalog catalog,
    String presetId,
  ) {
    try {
      return catalog.preset(presetId);
    } on RulesCatalogViolation {
      throw const FirstPlayableRulesCatalogRepositoryViolation(
        'presetCatalogUnavailable',
      );
    }
  }

  static Map<String, RulesCatalog> _index(Iterable<RulesCatalog> catalogs) {
    final result = <String, RulesCatalog>{};
    for (final catalog in catalogs) {
      if (result.containsKey(catalog.rulesVersion)) {
        throw const FirstPlayableRulesCatalogRepositoryViolation(
          'duplicateRulesCatalogVersion',
        );
      }
      result[catalog.rulesVersion] = catalog;
    }
    return Map.unmodifiable(result);
  }
}
