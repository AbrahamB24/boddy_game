// The guided tutorial for brand-new players (rebuilt 2026-08-20, user design).
//
// WHY THIS EXISTS: a fresh account starts with zero creatures, and creatures
// ARE the workforce — workshopPower() sums the stats of creatures assigned to
// workshops, so with none the wood rate and the build rate are both exactly 0.
// Every screen reads as broken and nothing tells the player why.
//
// ── The script ────────────────────────────────────────────────
// This is a fully guided script: at every step exactly ONE control is lit
// (see intro_spotlight.dart), everything else is dimmed and dead, and the
// game bends its rules so no step can dead-end:
//
//   1. pickStarter      — choose the starter monster
//   2. firstNode        — win the first overworld node; cannot be lost
//                         (enemies fight at kJumpstartEnemyStatMult)
//   3. buildHealingHut  — build the Healing Hut
//   4. assignHealer     — station a monster at the Healing Hut
//   5. healStarter      — heal the starter: costs goods, but is INSTANT
//                         while the tutorial runs
//   6. firstCapture     — hunt: the wild cannot be K.O.'d and a missed QTE
//                         tap just restarts the ring — the catch always lands
//   7. secondNode       — win the second overworld node; cannot be lost,
//                         same mechanism as firstNode. Done.
//
// Ends here on purpose (user 2026-08-20): later concepts (resource buildings,
// research, etc.) get their own steps once designed, rather than dragging
// forward the old script's stale ones (they referenced systems — a tech-trial
// map, a Castle worker slot — that no longer exist).
//
// ── The jumpstart and why it can't touch the base values ──────
// docs/balancing.md anchors Era I at 5–7 days and 5–8 catches/day. Those are
// RATES. The tutorial shifts the curve by a constant (its whole runtime is
// minutes) and the anchors don't notice. Permanently lowering e.g.
// kCaptureBaseSeconds would TILT the curve and break both anchors. So
// everything here is a *temporary multiplier applied on top of* the balanced
// values, never a replacement for them — which is also why these constants
// live here and not in gather_math/capture_math.

/// Master switch (user request 2026-07-17). ON since 2026-09-21: the chain,
/// its jumpstart and its milestone hooks have been complete for a while, and
/// the last two things holding the switch down are now done too — the guide
/// card and the spotlight wear the cream kit like the rest of the app, and a
/// brand-new account actually gets a starting step written
/// (SettlementService._createProfileRow; without it the tutorial was
/// unreachable no matter what this said).
///
/// While false, SettlementController.load() reads the persisted step as
/// [IntroStep.done] IN MEMORY ONLY — nothing is written back, so this can go
/// back to false at any time and every account resumes exactly where its
/// `profiles.intro_step` says. Turning it on cannot drag a veteran in: a
/// NULL column reads as done (see SettlementService.loadIntroStep), and
/// load()'s own self-heal ends the chain for anyone who has already beaten a
/// region boss. Dev Mode's "restart intro" remains the manual override.
const bool kIntroEnabled = true;

/// Steps of the tutorial, in order. Persisted as the index on
/// `profiles.intro_step`; anything out of range reads as [done] so an older
/// or newer client can never trap a player in a step it doesn't know.
enum IntroStep {
  welcome,
  pickStarter,
  firstNode,
  buildHealingHut,
  buildRoad,
  assignHealer,
  healStarter,
  firstCapture,
  secondNode,
  done;

  static IntroStep fromIndex(int index) =>
      (index >= 0 && index < IntroStep.values.length)
      ? IntroStep.values[index]
      : IntroStep.done;

  /// True while the tutorial is still running — this is also exactly the
  /// window in which the jumpstart (acceleration + bent rules) applies.
  bool get isActive => this != IntroStep.done;

  /// The step reached after finishing this one.
  IntroStep get next =>
      this == IntroStep.done ? done : IntroStep.values[index + 1];
}

/// Where a step's call-to-action sends the player. The card itself owns no
/// navigation — the settlement screen maps these onto its existing routes
/// (and, for [healingHut]/[mainHall], opens the building's dialog directly:
/// the tutorial routes the player rather than hoping they find the building).
enum IntroDestination { collection, map, trips, build, healingHut }

/// One step's player-facing content.
class IntroCard {
  final String title;
  final String body;

  /// Null for steps the player completes right where they already are.
  final String? ctaLabel;
  final IntroDestination? destination;

  const IntroCard({
    required this.title,
    required this.body,
    this.ctaLabel,
    this.destination,
  });
}

/// Player-facing copy for [step] (null once the chain is [IntroStep.done]).
/// Written to teach the *why* along with the *what* — a new player has no way
/// to know that monsters are the workforce or that HP never regenerates.
IntroCard? introCardFor(IntroStep step) => switch (step) {
  IntroStep.welcome => const IntroCard(
    title: 'Welcome to Boddy Builder',
    body:
        'Grow a settlement, raise monsters, and send them out to fight, '
        'gather and explore.',
    ctaLabel: 'Let\'s go',
    destination: IntroDestination.collection,
  ),
  IntroStep.pickStarter => const IntroCard(
    title: 'Choose your first monster',
    body: 'You get to pick your starter monster — choose the one you like.',
    // No CTA of its own any more (user 2026-09-30: "Direkt den Button
    // anzeigen und den Text mit 'tap monsters to choose'") — the quick
    // menu's own Monsters tile is the lit target from the moment this step
    // begins, same hand-off firstNode gives the Map tile, rather than
    // needing an extra tap on this card first (see
    // SettlementScreen._soloQuickPadAnchor).
    destination: IntroDestination.collection,
  ),
  IntroStep.firstNode => const IntroCard(
    title: 'Your first battle',
    // Truncated after the first sentence (user 2026-09-02: "Ab 'a path of
    // .....' alles löschen") — the map itself (and its own one-time intro
    // overlay, see OverworldScreen._mapIntroOverlay) explains the path of
    // battles; this card only needs to say monsters fight too.
    body:
        'Your monsters can fight, too — and battles are where the biggest '
        'rewards come from.',
    // No CTA of its own (user 2026-09-02: "kein Button open the map,
    // sondern ich will, dass der User nun den Mapbutton sieht und diesen
    // drücken muss") — the quick menu's own Map tile is the lit target
    // instead (see SettlementScreen._soloQuickPadAnchor).
    destination: IntroDestination.map,
  ),
  IntroStep.buildHealingHut => const IntroCard(
    // Renamed from "Patch it up" (user 2026-09-30) — names the exact
    // building the step is actually about, the same way every other step's
    // title does.
    title: 'Heal your Monster',
    // Trimmed to the one fact this step needs (user 2026-09-30: "hier nur
    // kurz erklären, dass du verletzte Monster im Healing Hut behandeln
    // kannst und du dieses nun bauen sollst") — the Gold-speeds-construction
    // line this used to carry is gone; the site's own "Finish now" button
    // (building_detail_dialog's gold-rush action) still works, just
    // undocumented here now, by the same request.
    body:
        'Injured monsters can be treated at the Healing Hut. Build one '
        'now.',
    // No CTA of its own (user 2026-09-06, same reasoning as firstNode) —
    // the bottom build carousel itself is the lit target now (2026-09-18:
    // it replaced the quick menu's old Build tile), and it appears the
    // moment SettlementScreen._buildUnlocked flips true, already showing
    // its OWN row spotlight for this exact building.
    destination: IntroDestination.build,
  ),
  IntroStep.buildRoad => const IntroCard(
    title: 'Connect it with a road',
    // Shortened to just the rule itself (user 2026-09-30: "Nur schreiben,
    // dass Gebäude über Strassen mit dem Castle verbunden sein müssen,
    // damit diese funktionieren") — where exactly to place the road is no
    // longer this card's job now that the spot itself is fixed for the
    // player (see SettlementScreen's own placement lock for this step).
    body:
        'Buildings only work while a road links them back to your Castle. '
        'Lay one now.',
    // No CTA of its own (user 2026-09-06, same reasoning as buildHealingHut)
    // — the build carousel's own category-row spotlight is the lit target
    // now (2026-09-18), pointing at the Roads category specifically.
    destination: IntroDestination.build,
  ),
  IntroStep.assignHealer => const IntroCard(
    title: 'Station a monster there',
    // Leads with the general rule, not just this one hut (user 2026-09-30:
    // "schreiben, dass Gebäude meistens nur dann arbeiten, wenn Monster
    // darin arbeiten und sonst nicht funktionieren").
    body:
        'Most buildings only work once a monster is stationed inside — '
        'without one, they sit idle. Open the Healing Hut and post a '
        'monster to its medicine role.',
    // No CTA of its own (user 2026-09-06, same reasoning as buildHealingHut):
    // the Healing Hut ON THE MAP is the lit target instead — see
    // SettlementScreen._soloQuickPadAnchor.
    destination: IntroDestination.healingHut,
  ),
  IntroStep.healStarter => const IntroCard(
    title: 'Heal your monster',
    // Now names the resource cost as its own fact, not just folded into
    // "treatment costs goods" (user 2026-09-30: "erklären, dass Healing
    // immer Ressourcen verbraucht"). "Heal", not "Treat" (user 2026-09-30,
    // same request as the button it describes). No longer promises an
    // INSTANT finish (user 2026-10-01: "soll es zunächst geheilt werden wie
    // normal, d.h es braucht zeit. Aber ich muss es wieder mit gold
    // beschleunigen") — treatment now takes its real time even here, same as
    // the Healing Hut's own construction did, with the same gold pill to
    // skip the wait.
    body:
        'The hut is ready. Healing always consumes resources, scaled to '
        'the missing HP — a K.O. costs double. It takes real time to '
        'finish — gold can speed it up, same as the hut itself did.',
    ctaLabel: '🌿 Heal it now',
    destination: IntroDestination.healingHut,
  ),
  IntroStep.firstCapture => const IntroCard(
    title: 'Catch a second monster',
    // User's own line (2026-09-30): "Now its time to grow your Population.
    // Go out and catch your second Monster." Truncated there (user
    // 2026-10-01: "nur bis 'go out and catch your second monster'. Den
    // Rest löschen") — the mechanical how-a-hunt-works explanation that
    // used to follow is gone.
    body: "Now it's time to grow your population — go out and catch your "
        'second monster.',
    // No CTA of its own any more (user 2026-09-30: "Hier bereits den Trips
    // Button sichtbar machen und nur dieser darf anwählbar sein") — the
    // bottom quick pad's own Expedition button is the lit target instead,
    // same hand-off firstNode gives the Map tile (see
    // SettlementScreen._soloQuickPadAnchor).
    destination: IntroDestination.trips,
  ),
  IntroStep.secondNode => const IntroCard(
    title: 'Push on',
    body:
        'Two monsters now — one can rest while the other fights. Head back '
        'to the map and take the next battle on the path. Still an easy one: '
        'this is the last stretch of hand-holding.',
    ctaLabel: '🗺 Open the map',
    destination: IntroDestination.map,
  ),
  IntroStep.done => null,
};

/// The building each build-step waits for, keyed by step — used by the
/// settlement tick's completion hook (advance on FINISHED, not on placed)
/// and by the build menu to know which row to spotlight.
const Map<String, IntroStep> kIntroBuildSteps = {
  'healing_hut': IntroStep.buildHealingHut,
  'road': IntroStep.buildRoad,
};

/// The building type a build step wants, or null when [step] isn't one.
String? introBuildTarget(IntroStep step) {
  for (final entry in kIntroBuildSteps.entries) {
    if (entry.value == step) return entry.key;
  }
  return null;
}

// ── Jumpstart ────────────────────────────────────────────────
// Active for exactly as long as the tutorial is (IntroStep.isActive), so a
// player who quits after ten minutes keeps the whole boost — the window is
// progress-based, never wall-clock.

/// Multiplier on every waiting time while the tutorial runs: expedition
/// trips, crafting and construction. 0.02 collapses waits to seconds — the
/// tutorial is meant to be finished in one sitting (user requirement
/// 2026-07-17: "alles beschleunigt, damit ich es sofort beenden kann").
/// Healing is handled separately (instant-but-costed, see
/// CreaturesController.healAll).
const double kJumpstartTimeScale = 0.02;

/// Wild/gate enemies fight at this fraction of their stats during the
/// tutorial. 0.2 makes the first two overworld nodes and the catch fight
/// effectively unloseable — the script's promise is "this cannot fail", so
/// the numbers have to actually deliver that, not merely "kinder".
const double kJumpstartEnemyStatMult = 0.2;

// The tutorial's free construction power (kIntroBaseBuildPower) is GONE
// (user 2026-07-26). It existed for one reason: zero builders used to mean
// nothing ever built, so the Healing Hut step dead-ended with the starter
// K.O. and nobody assigned. Build points now buy a PERCENT off the authored
// time instead of being the whole budget, so an unstaffed site builds in
// exactly its authored time — and kJumpstartTimeScale still collapses that
// to seconds. Nothing left to prop up.

// kIntroMaxTripSeconds was DELETED 2026-10-02 — hunts no longer run on a
// clock at all (see Expedition.isStepGated), so there is no duration left
// to clamp. The tutorial's first hunt is shrunk in STEPS instead, by the
// same kJumpstartTimeScale below (see capture_math.dart's
// effectiveHuntSteps) — small enough that the gold-skip beat right after it
// (ExpeditionsScreen's 'hunt-skip-gold' spotlight) stays cheap.

/// Fish handed to a brand-new player. Buildings make it deliberately slowly
/// (workshop mult 0.12) because it is the region-dungeon entry cost — this is
/// a starter float, not an income, and it is dwarfed by the ~850 wood/day
/// target so it cannot dent the Era-I pace. It also covers the tutorial's
/// Healing Hut bill (a K.O.'d starter costs ~6–12 goods).
///
/// FISH ONLY (user 2026-09-20: "der Spieler startet mit Fisch und nicht mit
/// Fleisch, da Fleisch später erst kommt") — meat is region 2's luxury.
const double kJumpstartGiftFish = 20.0;

/// Gold handed to a brand-new player, so the Healing Hut step's own
/// "Gold speeds up construction — finish it now" button (1 gold) is
/// actually usable the moment it's shown (user 2026-10-01, screenshot of
/// that button next to "you have 0": "es braucht 1 gold, ich habe aber
/// keins. Bitte mit 20 Gold starten") — 20 leaves room beyond that one tap.
const double kJumpstartGiftGold = 20.0;

// The jumpstart's free "second monster" (kJumpstartFreeTechId = 'team_size_2')
// was REMOVED (user 2026-07-24): party size is now set by position on the
// linear path — the first five battles are always 1v1 and the second slot
// arrives at battle 6, so there is no early team-slot gift to hand out.

/// Applies [kJumpstartTimeScale] to a duration in seconds while [active].
double jumpstartTimeScale(bool active) => active ? kJumpstartTimeScale : 1.0;
