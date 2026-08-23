enum PresetTone { standard, experimental }

class PresetViewData {
  const PresetViewData({
    required this.id,
    required this.title,
    required this.durationLabel,
    required this.endConditionLabel,
    required this.differenceSummary,
    this.tone = PresetTone.standard,
  });

  final String id;
  final String title;
  final String durationLabel;
  final String endConditionLabel;
  final String differenceSummary;
  final PresetTone tone;
}

class LobbySeatViewData {
  const LobbySeatViewData({
    required this.id,
    required this.displayName,
    required this.isReady,
    this.isHost = false,
    this.isBot = false,
    this.isSelf = false,
  });

  final String id;
  final String displayName;
  final bool isReady;
  final bool isHost;
  final bool isBot;
  final bool isSelf;
}
