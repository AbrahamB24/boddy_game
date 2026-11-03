part of 'game_tuning.dart';

// Every tunable number in the game, declared once (user 2026-07-29). The game
// reads each through the getter that used to be its `const` — so no call site
// changed — and Dev Mode renders THIS list, so a dial can never exist in one
// place and not the other.
//
// Adding a dial is three lines: an id below, an entry in [kDials], and turning
// the old `const` into a getter at its original home. Nothing else.

/// The stable ids. Strings because they are the keys of the stored jsonb — a
/// rename here silently drops the saved value, so treat them as permanent.
abstract final class Dials {
  // ── Settlement ──
  static const baseExpeditionSlots = 'baseExpeditionSlots';
  static const baseCaravanSlots = 'baseCaravanSlots';
  static const baseBuildSlots = 'baseBuildSlots';
  static const baseQueueSlots = 'baseQueueSlots';
  static const buildingLevelGrowth = 'buildingLevelGrowth';
  static const buildPointsForHalfTime = 'buildPointsForHalfTime';
  static const breedingK = 'breedingK';
  static const energyFullSteps = 'energyFullSteps';
  static const energyFloorMultiplier = 'energyFloorMultiplier';
  static const energyBoostPerThousandSteps = 'energyBoostPerThousandSteps';
  static const energyMaxBoost = 'energyMaxBoost';
  static const energyFullHours = 'energyFullHours';
  static const healMaxCut = 'healMaxCut';
  static const tradeMaxDiscount = 'tradeMaxDiscount';
  static const goodsBuyMarkup = 'goodsBuyMarkup';
  static const barterFee = 'barterFee';
  static const baseStorage = 'baseStorage';
  static const baseGoldStorage = 'baseGoldStorage';

  // ── Kampagne ──
  static const battlesBeforeBoss = 'battlesBeforeBoss';
  static const bossLevelBonus = 'bossLevelBonus';
  static const maxPartySize = 'maxPartySize';
  static const partyStep2 = 'partyStep2';
  static const partyStep3 = 'partyStep3';
  static const partyStep4 = 'partyStep4';
  static const partyStep5 = 'partyStep5';
  static const partyStep6 = 'partyStep6';
  static const travelSecondsPerDanger = 'travelSecondsPerDanger';
  static const maxTripSeconds = 'maxTripSeconds';
  static const survivalBossEveryNFloors = 'survivalBossEveryNFloors';
  static const survivalGoldPerFloor = 'survivalGoldPerFloor';

  // ── Monster ──
  static const maxEras = 'maxEras';
  static const levelsPerEra = 'levelsPerEra';
  static const apCapacity1 = 'apCapacity1';
  static const apCapacity2 = 'apCapacity2';
  static const apCapacity3 = 'apCapacity3';
  static const apRegen1 = 'apRegen1';
  static const apRegen2 = 'apRegen2';
  static const apRegen3 = 'apRegen3';
  static const basicAttackApCost = 'basicAttackApCost';
  static const switchApCost = 'switchApCost';
  static const itemApCost = 'itemApCost';
  static const catchApCost = 'catchApCost';
  static const buffApCost = 'buffApCost';
  static const powerPerAp = 'powerPerAp';
  static const minAbilityApCost = 'minAbilityApCost';
  static const priorityPower = 'priorityPower';
  static const startApFirst = 'startApFirst';
  static const startApSecond = 'startApSecond';
  static const fieldSlots = 'fieldSlots';
  static const baseAccuracy = 'baseAccuracy';
  static const critBase = 'critBase';
  static const critSpeedDivisor = 'critSpeedDivisor';
  static const critMax = 'critMax';
  static const critMultiplier = 'critMultiplier';
  static const maxHitHpFraction = 'maxHitHpFraction';
  static const wildStatMult = 'wildStatMult';
  static const bossStatMult = 'bossStatMult';
  static const trainSecondsPerPower = 'trainSecondsPerPower';
  static const baseSigmaPct = 'baseSigmaPct';
  static const slopeSigmaPct = 'slopeSigmaPct';
  static const sigmaClampFactor = 'sigmaClampFactor';
  static const breedingFavoredChance = 'breedingFavoredChance';
  static const captureWildStatMult = 'captureWildStatMult';
  static const qteRoundSpeedup = 'qteRoundSpeedup';
  static const qteWindowCenter = 'qteWindowCenter';
  static const qteWindowCatchK = 'qteWindowCatchK';
  static const qteMaxWidthBonus = 'qteMaxWidthBonus';
  static const speciesMaturitySwing = 'speciesMaturitySwing';
  static const buffArmorPct = 'buffArmorPct';
  static const buffRagePct = 'buffRagePct';
  static const buffHastePct = 'buffHastePct';
  static const debuffBlindPct = 'debuffBlindPct';
  static const debuffSlowPct = 'debuffSlowPct';
  static const debuffWeakenPct = 'debuffWeakenPct';
  static const debuffExposePct = 'debuffExposePct';
  static const buffDurationTurns = 'buffDurationTurns';
  static const debuffDurationTurns = 'debuffDurationTurns';
  static const debuffRegressionPct = 'debuffRegressionPct';
  static const statusCureChanceBase = 'statusCureChanceBase';
  static const statusCureChanceStep = 'statusCureChanceStep';
  static const statusCureChanceCap = 'statusCureChanceCap';
}

/// Compact number for the "what this means" lines: no trailing .0, one decimal.
String _n(double v) {
  if (!v.isFinite) return '∞';
  if (v.abs() >= 1000) return v.round().toString();
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.round().toString() : r.toString();
}

/// A hyperbolic "half at K" curve read back as the cut it buys — the shape the
/// build-time and breeding-time dials share.
String _halfAtK(double k) => k <= 0
    ? 'Jeder Punkt halbiert sofort — vermutlich zu tief.'
    : '−50 % bei ${_n(k)} · −80 % bei ${_n(k * 4)} · −90 % bei ${_n(k * 9)}';

/// EVERY dial. Order inside a section is the order the menu shows.
final List<Dial> kDials = [
  // ══ Settlement ═══════════════════════════════════════════════
  Dial(
    id: Dials.baseExpeditionSlots,
    group: TuningGroup.settlement,
    section: 'Slots ohne Gebäude',
    label: 'Expeditionen',
    help: 'Wie viele Expeditionen ohne jedes Gebäude laufen können.',
    def: 0,
    kind: DialKind.count,
    felt: (v) => v <= 0
        ? 'Ohne Scout Post keine Expedition — der Scout Post ist die ganze '
              'Quelle.'
        : '${_n(v)} Expedition${v == 1 ? '' : 'en'} auch ganz ohne Scout Post.',
  ),
  Dial(
    id: Dials.baseCaravanSlots,
    group: TuningGroup.settlement,
    section: 'Slots ohne Gebäude',
    label: 'Karawanen',
    help: 'Wie viele Handelskarawanen ohne Karawanserei unterwegs sein können.',
    // 0 since 2026-07-29 — the author's own setting, taken over as the start
    // value so both roads follow one rule: the building IS the supply.
    def: 0,
    kind: DialKind.count,
    felt: (v) => v <= 0
        ? 'Ohne Karawanserei kein Handel.'
        : '${_n(v)} Karawane${v == 1 ? '' : 'n'} auch ohne Karawanserei.',
  ),
  Dial(
    id: Dials.baseBuildSlots,
    group: TuningGroup.settlement,
    section: 'Slots ohne Gebäude',
    label: 'Baustellen',
    help: 'Wie viele Gebäude gleichzeitig gebaut werden können.',
    def: 1,
    kind: DialKind.count,
  ),
  Dial(
    id: Dials.baseQueueSlots,
    group: TuningGroup.settlement,
    section: 'Slots ohne Gebäude',
    label: 'Bau-Warteschlange',
    help:
        'Wie viele Bauten vorgemerkt werden können, bevor ein Gebäude '
        'weitere freischaltet.',
    def: 0,
    kind: DialKind.count,
  ),
  Dial(
    id: Dials.buildingLevelGrowth,
    group: TuningGroup.settlement,
    section: 'Gebäude-Level',
    label: 'Zuwachs pro Level',
    help:
        'Gilt für JEDEN Effekt, der keinen eigenen Wachstumswert hat. '
        'Der grösste Hebel der ganzen Wirtschaft.',
    def: 0.5,
    kind: DialKind.percent,
    felt: (v) =>
        'Level 1 ×1 · Level 5 ×${_n(1 + v * 4)} · '
        'Level 10 ×${_n(1 + v * 9)}',
  ),
  Dial(
    id: Dials.buildPointsForHalfTime,
    group: TuningGroup.settlement,
    section: 'Bauzeit',
    label: 'Baupunkte für halbe Bauzeit',
    help:
        'Baupunkte kürzen die im Gebäude hinterlegte Bauzeit. Ohne Deckel, '
        'aber mit abnehmendem Ertrag.',
    // Was 100 (user 2026-09-28: "ein Monster mit Stat 114 alleine bereits 66%
    // Zeitreduktion" — that was the breeding dial below, same curve, weaker
    // mult; raised here too so a single elite builder lands near the same
    // ~30 %, not ~35-40 %). At mult 0.5 a stat-114 worker makes 57 points;
    // 140 puts that at ≈29 %, and ten of them at ≈80 %, never free.
    def: 140,
    min: 1,
    felt: _halfAtK,
  ),
  Dial(
    id: Dials.breedingK,
    group: TuningGroup.settlement,
    section: 'Paaren & Brüten',
    label: 'Power für halbe Dauer',
    help:
        'Wie stark die Arbeiter in Zuchthütte und Brutstätte die Dauer '
        'kürzen. Dieselbe Kurve wie bei der Bauzeit.',
    // Was 60 (user 2026-09-28: "ein Monster mit Stat 114 alleine bereits 66%
    // Zeitreduktion … könnten über 10 angestellt werden"). The role's mult is
    // 1, so power IS the stat — a single strong breeder was already two
    // thirds of the way to a free mating, and ten of them left almost
    // nothing of the timer. 260 puts one stat-114 breeder at ≈30 % and ten of
    // them at ≈81 %: a full Breeding Hut is dramatic, not instant.
    def: 260,
    min: 1,
    felt: _halfAtK,
  ),
  Dial(
    id: Dials.energyFullSteps,
    group: TuningGroup.settlement,
    section: 'Energie',
    label: 'Schritte für 100%',
    help:
        'Wie viele Schritte die Energie von 0 auf 100% füllen. Die '
        'Schritte darüber zählen weniger (siehe Bonus pro 1000 '
        'Extraschritte).',
    def: 5000,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.energyFloorMultiplier,
    group: TuningGroup.settlement,
    section: 'Energie',
    label: 'Rate bei leerer Energie',
    help:
        'Wie viel die Siedlung noch leistet, wenn die Energie auf 0 '
        'gesunken ist.',
    def: 0.0,
    kind: DialKind.percent,
    felt: (v) => 'Bei leerer Energie läuft alles mit ${_n(v * 100)} %.',
  ),
  Dial(
    id: Dials.energyBoostPerThousandSteps,
    group: TuningGroup.settlement,
    section: 'Energie',
    label: 'Bonus pro 1000 Extraschritte',
    help:
        'Über die 100%-Schwelle hinaus: wie viel zusätzliche Energie je '
        '1000 weitere Schritte.',
    def: 0.05,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.energyMaxBoost,
    group: TuningGroup.settlement,
    section: 'Energie',
    label: 'Bonus-Obergrenze',
    help:
        'Die maximale Extra-Energie über 100% hinaus. Weitere Schritte '
        'verfallen, bis die Energie wieder unter dem Maximum liegt.',
    def: 0.25,
    kind: DialKind.percent,
    felt: (v) {
      final full = GameTuning.i.raw(Dials.energyFullSteps);
      final perThousand = GameTuning.i.raw(Dials.energyBoostPerThousandSteps);
      final stepsForMax = perThousand <= 0
          ? null
          : full + 1000 * (v / perThousand);
      return stepsForMax == null
          ? 'Maximal ${_n(100 + v * 100)} % Energie.'
          : 'Maximal ${_n(100 + v * 100)} % Energie, erreicht mit '
                '${_n(stepsForMax)} Schritten aus leerem Zustand.';
    },
  ),
  Dial(
    id: Dials.energyFullHours,
    group: TuningGroup.settlement,
    section: 'Energie',
    label: 'Stunden von 100% bis 0',
    help:
        'Wie lange 100% Energie reichen, wenn nicht gelaufen wird. Die '
        'Energie sinkt gleichmässig — die Maximalenergie hält '
        'entsprechend länger.',
    def: 24,
    min: 0.1,
    felt: (v) {
      final maxPct = 100 + GameTuning.i.raw(Dials.energyMaxBoost) * 100;
      return '100 % reichen ${_n(v)} h, die Maximalenergie '
          '(${_n(maxPct)} %) ${_n(v * maxPct / 100)} h.';
    },
  ),
  Dial(
    id: Dials.healMaxCut,
    group: TuningGroup.settlement,
    section: 'Heilen',
    label: 'Maximale Verkürzung',
    help: 'Deckel über Gebäude-Effekt UND Heilerposten zusammen.',
    def: 0.9,
    kind: DialKind.percent,
    felt: (v) =>
        'Eine 10-h-Behandlung dauert bestenfalls '
        '${_n(10 * (1 - v))} h.',
  ),
  Dial(
    id: Dials.tradeMaxDiscount,
    group: TuningGroup.settlement,
    section: 'Handel',
    label: 'Maximale Spannen-Kürzung',
    help: 'Deckel über Handelszentrum-Level UND Händlerposten zusammen.',
    def: 0.6,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.goodsBuyMarkup,
    group: TuningGroup.settlement,
    section: 'Handel',
    label: 'Kaufaufschlag',
    help:
        'Zurückkaufen kostet so viel mal das, was der Verkauf eingebracht '
        'hat. Unter 1 wäre eine Gelddruckmaschine.',
    def: 2.5,
    min: 1,
    felt: (v) => 'Für 100 verkauft → ${_n(100 * v)} zum Zurückkaufen.',
  ),
  Dial(
    id: Dials.barterFee,
    group: TuningGroup.settlement,
    section: 'Handel',
    label: 'Tauschgebühr',
    help: 'Was beim Ware-gegen-Ware-Tausch verloren geht.',
    def: 0.25,
    kind: DialKind.percent,
    felt: (v) => 'Von 100 Einheiten Wert kommen ${_n(100 * (1 - v))} an.',
  ),

  Dial(
    id: Dials.baseStorage,
    group: TuningGroup.settlement,
    section: 'Lager',
    label: 'Ohne Lagergebäude je Ressource',
    help:
        'Wie viel die Siedlung von JEDER Ware halten kann, bevor ein '
        'Lagergebäude dazukommt. Darüber stoppt die Produktion.',
    def: 500,
    min: 1,
    felt: (v) => 'Ein Lager mit +500 macht daraus ${_n(v + 500)}.',
  ),
  Dial(
    id: Dials.baseGoldStorage,
    group: TuningGroup.settlement,
    section: 'Lager',
    label: 'Ohne Goldlager',
    help: 'Wie viel Gold die Siedlung ohne Goldlager halten kann.',
    def: 2000,
    min: 1,
  ),

  // ══ Kampagne ═════════════════════════════════════════════════
  Dial(
    id: Dials.battlesBeforeBoss,
    group: TuningGroup.campaign,
    section: 'Pfad',
    label: 'Kämpfe bis zum Boss (nur Fallback-Pfad)',
    help:
        'Wie viele normale Kämpfe eine generierte Region hat, bevor der '
        'Boss kommt. Gilt nur für den Fallback-Pfad — eine im Pfad-Editor '
        'autorierte Region endet dort, wo ihr Boss-Knoten steht.',
    def: 18,
    kind: DialKind.count,
    min: 1,
    felt: (v) =>
        'Eine Fallback-Region ist ${_n(v + 1)} Kämpfe lang (inkl. Boss).',
  ),
  Dial(
    id: Dials.bossLevelBonus,
    group: TuningGroup.campaign,
    section: 'Pfad',
    label: 'Boss-Levelbonus',
    help:
        'Wie viele Level ein Boss über dem normalen Gegner dieser Stelle '
        'liegt.',
    def: 3,
    kind: DialKind.count,
  ),
  Dial(
    id: Dials.maxPartySize,
    group: TuningGroup.campaign,
    section: 'Gruppengrösse',
    label: 'Grösste Gruppe',
    help: 'Harte Obergrenze, egal wie weit die Schwellen unten reichen.',
    def: 6,
    kind: DialKind.count,
    min: 1,
  ),
  // ── Survival (user 2026-09-06) ──
  // Own endless mode: fixed 6er-Team, Kämpfe ohne Rückkehr in die Siedlung,
  // Schwierigkeit an einem eigenen Etagen-Zähler statt an battlesCleared.
  Dial(
    id: Dials.survivalBossEveryNFloors,
    group: TuningGroup.campaign,
    section: 'Survival',
    label: 'Boss alle N Etagen',
    help:
        'Jede so vielte Etage im Survival-Modus ist ein Boss (stärkere '
        'Werte, mehr XP) statt eines normalen Gegners.',
    def: 5,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.survivalGoldPerFloor,
    group: TuningGroup.campaign,
    section: 'Survival',
    label: 'Gold pro Etage',
    help:
        'Jede NEUE Rekord-Etage zahlt diesen Wert mal ihre Etagennummer '
        '(der erste Lauf bis Etage N also die Dreieckszahl 1+2+…+N). '
        'Etagen, die schon ein früherer Lauf geschafft hat, zahlen nur 1 '
        'Gold (seit 2026-11-02, sonst war Survival eine endlose Goldquelle).',
    def: 15,
    kind: DialKind.decimal,
    min: 0,
  ),
  Dial(
    id: Dials.partyStep2,
    group: TuningGroup.campaign,
    section: 'Gruppengrösse',
    label: '2 Monster ab Kampf',
    help: 'Ab dieser Kampfnummer darf ein Monster mehr mit.',
    def: 6,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.partyStep3,
    group: TuningGroup.campaign,
    section: 'Gruppengrösse',
    label: '3 Monster ab Kampf',
    help: 'Ab dieser Kampfnummer darf ein Monster mehr mit.',
    def: 15,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.partyStep4,
    group: TuningGroup.campaign,
    section: 'Gruppengrösse',
    label: '4 Monster ab Kampf',
    help: 'Ab dieser Kampfnummer darf ein Monster mehr mit.',
    def: 20,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.partyStep5,
    group: TuningGroup.campaign,
    section: 'Gruppengrösse',
    label: '5 Monster ab Kampf',
    help: 'Ab dieser Kampfnummer darf ein Monster mehr mit.',
    def: 26,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.partyStep6,
    group: TuningGroup.campaign,
    section: 'Gruppengrösse',
    label: '6 Monster ab Kampf',
    help: 'Ab dieser Kampfnummer darf ein Monster mehr mit.',
    def: 32,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.travelSecondsPerDanger,
    group: TuningGroup.campaign,
    section: 'Reise',
    label: 'Anreise',
    help:
        'Hinweg + Rückweg zu einem Gebiet. Wird durch Scout-Post-Arbeiter '
        'gekürzt.',
    def: 300,
    kind: DialKind.minutes,
    felt: (v) => '${_n(v / 60)} min reine Reisezeit.',
  ),
  Dial(
    id: Dials.maxTripSeconds,
    group: TuningGroup.campaign,
    section: 'Reise',
    label: 'Längste Expedition',
    help: 'Harter Deckel, damit keine Expedition unbegrenzt lang wird.',
    def: 24 * 3600,
    kind: DialKind.hours,
    min: 60,
  ),

  // ══ Monster ══════════════════════════════════════════════════
  Dial(
    id: Dials.maxEras,
    group: TuningGroup.monster,
    section: 'Level',
    label: 'Anzahl Regionen',
    help: 'Zusammen mit den Leveln pro Region ergibt das die Levelgrenze.',
    def: 8,
    kind: DialKind.count,
    min: 1,
    felt: (v) => 'Max-Level ${_n(v * GameTuning.i.raw(Dials.levelsPerEra))}.',
  ),
  Dial(
    id: Dials.levelsPerEra,
    group: TuningGroup.monster,
    section: 'Level',
    label: 'Level pro Region',
    help: 'Wie viele Level eine erreichte Region freischaltet.',
    def: 10,
    kind: DialKind.count,
    min: 1,
    felt: (v) => 'Max-Level ${_n(v * GameTuning.i.raw(Dials.maxEras))}.',
  ),
  // AP capacity and regen, per evolution stage. Six plain numbers instead of
  // two half-redundant constants plus two hidden lists — the gap between a
  // stage's capacity and its regen IS the tactical dial ("So muss ich taktisch
  // arbeiten und kann nicht immer alles benutzen"), so both belong in view.
  Dial(
    id: Dials.apCapacity1,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Vorrat',
    label: '1. Form',
    help: 'Wie viele AP ein unentwickeltes Monster ansparen kann.',
    def: 4,
    kind: DialKind.count,
    min: 1,
    felt: (v) =>
        'Regeneriert ${_n(GameTuning.i.raw(Dials.apRegen1))} pro Zug '
        '— es bleiben ${_n(v - GameTuning.i.raw(Dials.apRegen1))} zum Sparen.',
  ),
  Dial(
    id: Dials.apCapacity2,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Vorrat',
    label: '2. Form',
    help: 'Vorrat nach der ersten Entwicklung.',
    def: 6,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.apCapacity3,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Vorrat',
    label: '3. Form',
    help: 'Vorrat der Endform. Zugleich das harte AP-Maximum im Spiel.',
    def: 8,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.apRegen1,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Regeneration',
    label: '1. Form',
    help: 'AP zu Beginn jedes eigenen Zuges. Bewusst unter dem Vorrat.',
    // 2, not 3 (user 2026-09-07: "Stufe 1 regeneriert 2 AP") — leaves 2 of
    // the 4-AP-Vorrat to bank per turn, same headroom-under-capacity ratio
    // every stage now keeps (see apRegen2/3 below).
    def: 2,
    kind: DialKind.count,
  ),
  Dial(
    id: Dials.apRegen2,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Regeneration',
    label: '2. Form',
    help: 'AP zu Beginn jedes eigenen Zuges.',
    // 3, not 4 (user 2026-09-07: "Stufe 2 3AP").
    def: 3,
    kind: DialKind.count,
  ),
  Dial(
    id: Dials.apRegen3,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Regeneration',
    label: '3. Form',
    help: 'AP zu Beginn jedes eigenen Zuges.',
    // 4, not 5 (user 2026-09-07: "Stufe 3 regeneriert 4AP" — said as "Stufe
    // 4", but there are only 3 evolution stages; matches the same pattern
    // apRegen1/2 set).
    def: 4,
    kind: DialKind.count,
  ),
  Dial(
    id: Dials.basicAttackApCost,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Kosten',
    label: 'Standardangriff kostet',
    help:
        'Der Angriff, den jedes Monster immer hat. Explizit gesetzt (nicht '
        'mehr aus Power abgeleitet — user 2026-09-08), daher trifft dieser '
        'Wert IMMER exakt zu.',
    def: 2,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.switchApCost,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Kosten',
    label: 'Auswechseln kostet',
    help: 'Ein Monster gegen eines von der Bank tauschen.',
    def: 2,
    kind: DialKind.count,
  ),
  Dial(
    id: Dials.itemApCost,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Kosten',
    label: 'Item benutzen kostet',
    help: 'Ein Item im Kampf einsetzen (heilen/buffen).',
    def: 1,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.catchApCost,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Kosten',
    label: 'Fangversuch kostet',
    help:
        'Ein Fangversuch bei einem Hunt-Fund. Gleich teuer wie ein '
        'Standardangriff (user 2026-09-11), damit Fangen eine echte '
        'Wahl gegen Angreifen ist statt der dominanten Gratis-Aktion.',
    def: 2,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.buffApCost,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Kosten',
    label: 'Buff kostet mindestens',
    help:
        'Der günstigste Preis einer stärkenden Fähigkeit. Ein starker Buff '
        'kostet nach seiner Power mehr — das hier ist der Boden. Auf 1 '
        'gesenkt (user 2026-09-08: "damit es einige mit nur 1 AP gibt"), '
        'damit ein schwacher, kurzer Buff wirklich nur 1 AP kostet statt am '
        'Boden festzukleben.',
    def: 1,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.powerPerAp,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Kosten',
    label: 'Power pro AP',
    help:
        'Wieviel Power ein Aktionspunkt kauft. Der Umrechnungskurs für JEDE '
        'Fähigkeit: Kosten = (Power der Fähigkeit) ÷ diesem Wert. Kleiner = '
        'alles wird teurer.',
    def: 13,
    kind: DialKind.count,
    min: 1,
    felt: (v) =>
        'Der teuerste bezahlbare Move hat '
        '${_n(v * GameTuning.i.raw(Dials.apCapacity3))} Power '
        '(${_n(GameTuning.i.raw(Dials.apCapacity3))} AP × ${_n(v)}).',
  ),
  Dial(
    id: Dials.minAbilityApCost,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Kosten',
    label: 'Fähigkeit kostet mindestens',
    help:
        'Der Boden für jede Fähigkeit ausser Buffs — auch eine schwache soll '
        'einen Zug wert sein. Auf 1 gesenkt (user 2026-09-08), damit ein '
        'schwacher Debuff (ein Damage-Move mit wenig/keiner eigenen Power, '
        'nur der Debuff-Chance) auch wirklich nur 1 AP kostet.',
    def: 1,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.priorityPower,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Kosten',
    label: 'Power pro Prioritätsstufe',
    help:
        'Was Vorziehen im Zugfenster wert ist. Wird wie Effekt-Power auf die '
        'Fähigkeit gerechnet und über «Power pro AP» in AP umgesetzt.',
    def: 15,
    kind: DialKind.count,
  ),
  Dial(
    id: Dials.startApFirst,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Kosten',
    label: 'Start-AP wer beginnt',
    help: 'Wer zuerst dran ist, startet bewusst mit weniger.',
    def: 2,
    kind: DialKind.count,
  ),
  Dial(
    id: Dials.startApSecond,
    group: TuningGroup.monster,
    section: 'Aktionspunkte · Kosten',
    label: 'Start-AP wer folgt',
    help: 'Ausgleich dafür, den zweiten Zug zu haben.',
    def: 3,
    kind: DialKind.count,
  ),
  Dial(
    id: Dials.fieldSlots,
    group: TuningGroup.monster,
    section: 'Kampf',
    label: 'Monster gleichzeitig im Feld',
    help: 'Pro Seite. Der Rest der Gruppe wartet auf der Bank.',
    def: 3,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.baseAccuracy,
    group: TuningGroup.monster,
    section: 'Kampf',
    label: 'Grund-Treffchance',
    help: 'Wird mit der Genauigkeit des Monsters multipliziert.',
    def: 0.92,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.critBase,
    group: TuningGroup.monster,
    section: 'Kampf',
    label: 'Krit-Grundchance',
    help: 'Chance auf einen kritischen Treffer bei Tempo 0.',
    def: 0.0625,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.critSpeedDivisor,
    group: TuningGroup.monster,
    section: 'Kampf',
    label: 'Tempo pro Krit-Prozentpunkt',
    help: 'Je tiefer, desto stärker zahlt Tempo auf die Kritchance ein.',
    def: 5000,
    min: 1,
    felt: (v) =>
        v <= 0 ? '—' : 'Tempo 200 gibt +${_n(200 / v * 100)} Prozentpunkte.',
  ),
  Dial(
    id: Dials.critMax,
    group: TuningGroup.monster,
    section: 'Kampf',
    label: 'Krit-Deckel',
    help: 'Höchste erreichbare Kritchance.',
    def: 0.10,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.critMultiplier,
    group: TuningGroup.monster,
    section: 'Kampf',
    label: 'Krit-Schaden',
    help: 'Womit ein kritischer Treffer multipliziert wird.',
    def: 1.5,
    felt: (v) => '${_n((v - 1) * 100)} % mehr Schaden.',
  ),
  Dial(
    id: Dials.maxHitHpFraction,
    group: TuningGroup.monster,
    section: 'Kampf',
    label: 'Schaden pro Treffer höchstens',
    help: 'Anteil der max. HP des Ziels. Verhindert One-Shots. 0 = aus.',
    // Off by default (user 2026-08-29: "es soll keine Grenze geben") — at a
    // big enough level gap this cap made every move a fight's attacker had
    // land on the exact SAME clamped number regardless of its own power,
    // which read as "power does nothing" instead of as the anti-one-shot
    // floor it actually was.
    def: 0.0,
    kind: DialKind.percent,
    felt: (v) => v <= 0 ? '—' : 'Mindestens ${_n(1 / v)} Treffer bis zum K.O.',
  ),
  Dial(
    id: Dials.wildStatMult,
    group: TuningGroup.monster,
    section: 'Kampf',
    label: 'Wildes Monster',
    help: 'Womit die Werte eines wilden Gegners multipliziert werden.',
    def: 0.85,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.bossStatMult,
    group: TuningGroup.monster,
    section: 'Kampf',
    label: 'Boss',
    help: 'Womit die Werte eines Bosses multipliziert werden.',
    def: 1.20,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.trainSecondsPerPower,
    group: TuningGroup.monster,
    section: 'Kampfschule',
    label: 'Lernzeit pro Powerpunkt',
    help:
        'Sekunden Trainingszeit pro Powerpunkt der Fähigkeit (Damage + '
        'Effekte).',
    def: 40,
    kind: DialKind.decimal,
    min: 0,
    felt: (v) => v <= 0
        ? 'Jede Fähigkeit wäre sofort gelernt.'
        : 'Eine Fähigkeit mit 40 Power dauert ${_n(40 * v / 60)} Minuten.',
  ),
  Dial(
    id: Dials.baseSigmaPct,
    group: TuningGroup.monster,
    section: 'Gene',
    label: 'Streuung Startwert',
    help: 'Wie stark der Startwert eines Stats vom Artdurchschnitt abweicht.',
    def: 0.08,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.slopeSigmaPct,
    group: TuningGroup.monster,
    section: 'Gene',
    label: 'Streuung Wachstum',
    help: 'Wie stark der Zuwachs pro Level vom Artdurchschnitt abweicht.',
    def: 0.06,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.sigmaClampFactor,
    group: TuningGroup.monster,
    section: 'Gene',
    label: 'Ausreisser-Grenze',
    help: 'Wie viele Standardabweichungen ein Gen höchstens abweichen darf.',
    def: 2.0,
    min: 0.1,
    felt: (v) =>
        'Streuung ${_n(GameTuning.i.raw(Dials.baseSigmaPct) * 100)} % '
        '→ höchstens ±${_n(GameTuning.i.raw(Dials.baseSigmaPct) * v * 100)} %.',
  ),
  Dial(
    id: Dials.breedingFavoredChance,
    group: TuningGroup.monster,
    section: 'Gene',
    label: 'Vererbung vom besseren Elternteil',
    help:
        'Chance, dass ein Gen vom stärkeren statt vom schwächeren Elternteil '
        'kommt.',
    def: 0.60,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.speciesMaturitySwing,
    group: TuningGroup.monster,
    section: 'Rollen',
    label: 'Frühstarter ↔ Spätzünder Ausschlag',
    help:
        'Wie stark der Frühstarter/Spätzünder-Regler eine Art\'s Signature-'
        'Stat(s) zwischen Startwert und Wachstum verschiebt (user 2026-09-07: '
        '"gerne fände ich es schön, wenn es slow starter gibt, welche dafür '
        'aber mehr wachsen als andere"). 0 = Regler wirkungslos.',
    def: 0.35,
    kind: DialKind.percent,
    felt: (v) => v <= 0
        ? 'Regler wirkungslos — jede Art rollt wie ohne Frühstarter/'
              'Spätzünder.'
        : '${_n(v * 100)} % vom Gewichts-Überschuss des Signature-Stats '
              'wandert bei vollem Ausschlag zwischen Start und Wachstum hin '
              'und her.',
  ),
  Dial(
    id: Dials.captureWildStatMult,
    group: TuningGroup.monster,
    section: 'Fangen',
    label: 'Wildes Monster beim Fangen',
    help:
        'Eigener Wert für die Fangbegegnung — sie soll leichter sein als ein '
        'normaler Kampf.',
    def: 0.75,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.qteRoundSpeedup,
    group: TuningGroup.monster,
    section: 'Fangen',
    label: 'Tempo pro Runde',
    help:
        'Womit die Dauer des Fangbalkens jede Runde multipliziert wird — '
        'unter 100 % wird es schneller.',
    def: 0.80,
    kind: DialKind.percent,
    felt: (v) => 'Runde 3 läuft auf ${_n(v * v * v * 100)} % der Startdauer.',
  ),
  Dial(
    id: Dials.qteWindowCenter,
    group: TuningGroup.monster,
    section: 'Fangen',
    label: 'Mitte des Trefferfensters',
    help: 'Wo im Balken das grüne Fenster sitzt.',
    def: 0.35,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.qteWindowCatchK,
    group: TuningGroup.monster,
    section: 'Fangen',
    label: 'Fangrate für halbes Bonusfenster',
    help:
        'Je tiefer, desto schneller macht eine hohe Fangrate das Fenster '
        'breit.',
    def: 100,
    min: 1,
  ),
  Dial(
    id: Dials.qteMaxWidthBonus,
    group: TuningGroup.monster,
    section: 'Fangen',
    label: 'Grösstes Bonusfenster',
    help: 'Wie breit das Trefferfenster bei unendlicher Fangrate maximal wird.',
    def: 1.2,
  ),
  // ── Effekte · Buffs & Debuffs (user 2026-09-08: "Buffs und Debuffs sollen
  //    sich wirklich lohnen") — every magnitude/duration a buff or secondary
  //    debuff falls back to when the ability that applied it doesn't author
  //    its own (see status_effects.dart). Raised from the old flat 25-30 %/
  //    2 turns baked into the code before this dial existed.
  Dial(
    id: Dials.buffArmorPct,
    group: TuningGroup.monster,
    section: 'Effekte · Buffs & Debuffs',
    label: 'Panzerung (Armor) gibt',
    help:
        'Verteidigung, die "Panzerung" dem Nutzer gibt, wenn die Fähigkeit '
        'selbst keinen eigenen Wert vorgibt.',
    def: 0.40,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.buffRagePct,
    group: TuningGroup.monster,
    section: 'Effekte · Buffs & Debuffs',
    label: 'Kampfrausch (Rage) gibt',
    help:
        'Angriff, den "Kampfrausch" dem Nutzer gibt, wenn die Fähigkeit '
        'selbst keinen eigenen Wert vorgibt.',
    def: 0.35,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.buffHastePct,
    group: TuningGroup.monster,
    section: 'Effekte · Buffs & Debuffs',
    label: 'Hast (Haste) gibt',
    help:
        'Tempo, das "Hast" dem Nutzer gibt, wenn die Fähigkeit selbst '
        'keinen eigenen Wert vorgibt.',
    def: 0.40,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.debuffBlindPct,
    group: TuningGroup.monster,
    section: 'Effekte · Buffs & Debuffs',
    label: 'Blenden (Blind) nimmt',
    help:
        'Trefferchance, die das Ziel verliert, wenn die Fähigkeit selbst '
        'keinen eigenen Wert vorgibt.',
    def: 0.35,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.debuffSlowPct,
    group: TuningGroup.monster,
    section: 'Effekte · Buffs & Debuffs',
    label: 'Verlangsamen (Slowed) nimmt',
    help:
        'Tempo, das das Ziel verliert, wenn die Fähigkeit selbst keinen '
        'eigenen Wert vorgibt.',
    def: 0.40,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.debuffWeakenPct,
    group: TuningGroup.monster,
    section: 'Effekte · Buffs & Debuffs',
    label: 'Schwächen (Weakened) nimmt',
    help:
        'Angriff, den das Ziel verliert, wenn die Fähigkeit selbst keinen '
        'eigenen Wert vorgibt.',
    def: 0.35,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.debuffExposePct,
    group: TuningGroup.monster,
    section: 'Effekte · Buffs & Debuffs',
    label: 'Blossstellen (Exposed) nimmt',
    help:
        'Verteidigung, die das Ziel verliert, wenn die Fähigkeit selbst '
        'keinen eigenen Wert vorgibt.',
    def: 0.40,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.buffDurationTurns,
    group: TuningGroup.monster,
    section: 'Effekte · Buffs & Debuffs',
    label: 'Eigen-Buff hält',
    help:
        'Wie viele eigene Runden ein Selbst-Buff (Panzerung/Kampfrausch/'
        'Hast) hält, wenn die Fähigkeit selbst keine eigene Dauer vorgibt.',
    def: 3,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.debuffDurationTurns,
    group: TuningGroup.monster,
    section: 'Effekte · Buffs & Debuffs',
    label: 'Debuff hält',
    help:
        'Wie viele eigene Runden des Ziels ein Sekundär-Debuff (Blenden/'
        'Verlangsamen/Schwächen/Blossstellen) hält, wenn die Fähigkeit '
        'selbst keine eigene Dauer vorgibt.',
    def: 3,
    kind: DialKind.count,
    min: 1,
  ),
  Dial(
    id: Dials.debuffRegressionPct,
    group: TuningGroup.monster,
    section: 'Effekte · Buffs & Debuffs',
    label: 'Regression nimmt (Angriff+Verteidigung+Tempo)',
    help:
        'Wie viel Angriff, Verteidigung UND Tempo das Ziel zugleich '
        'verliert, wenn die Fähigkeit selbst keinen eigenen Wert vorgibt — '
        'die "Deevolution"-Attacken.',
    def: 0.25,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.statusCureChanceBase,
    group: TuningGroup.monster,
    section: 'Effekte · Status',
    label: 'Heilchance ab der 1. Runde',
    help:
        'Chance am Ende jeder Runde, einen Hauptstatus (Burn/Freeze/'
        'Poison/…) VORZEITIG zu verlieren — steigt jede Runde um die '
        'Schritt-Chance, bis zur Obergrenze (user 2026-09-15: "in jeder '
        'Runde wird die Chance grösser").',
    def: 0.12,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.statusCureChanceStep,
    group: TuningGroup.monster,
    section: 'Effekte · Status',
    label: 'Heilchance-Zuwachs pro Runde',
    help: 'Wie viel die Heilchance jede weitere Runde zulegt.',
    def: 0.12,
    kind: DialKind.percent,
  ),
  Dial(
    id: Dials.statusCureChanceCap,
    group: TuningGroup.monster,
    section: 'Effekte · Status',
    label: 'Heilchance-Obergrenze',
    help:
        'Die Heilchance wächst nie über diesen Wert hinaus, egal wie '
        'lange der Status schon aktiv ist.',
    def: 0.85,
    kind: DialKind.percent,
  ),
];
