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

/// Master switch (user request 2026-07-17): the guided tutorial is fully
/// built but currently OFF. While false, SettlementController.load() reads
/// the persisted step as [IntroStep.done] IN MEMORY ONLY — nothing is
/// written back, so flipping this to true resumes every account exactly
/// where its `profiles.intro_step` says. Dev Mode's "restart intro" still
/// works as a manual override for testing while the switch is off.
const bool kIntroEnabled = false;

/// Steps of the tutorial, in order. Persisted as the index on
/// `profiles.intro_step`; anything out of range reads as [done] so an older
/// or newer client can never trap a player in a step it doesn't know.
enum IntroStep {
  pickStarter,
  firstNode,
  buildHealingHut,
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
enum IntroDestination {
  collection,
  map,
  trips,
  build,
  healingHut,
}

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
  IntroStep.pickStarter => const IntroCard(
    title: 'Choose your first monster',
    body:
        'Nothing in your settlement is producing yet — and that is not a bug. '
        'Monsters are your workforce: they gather, build, research and fight. '
        'Without one, every rate is zero. Pick your starter to begin.',
    ctaLabel: 'Choose starter',
    destination: IntroDestination.collection,
  ),
  IntroStep.firstNode => const IntroCard(
    title: 'Your first battle',
    body:
        'A path of numbered battles leads out from your settlement — win one '
        'and the next unlocks. This first one is yours to learn on: the foe '
        'is deliberately weak, so go meet it and see how fighting works.',
    ctaLabel: '🗺 Open the map',
    destination: IntroDestination.map,
  ),
  IntroStep.buildHealingHut => const IntroCard(
    title: 'Patch it up',
    body:
        'That fight cost your monster some HP — and HP never comes back on '
        'its own. Healing is what the Healing Hut is for. Build one now.',
    ctaLabel: '🏕 Build the Healing Hut',
    destination: IntroDestination.build,
  ),
  IntroStep.assignHealer => const IntroCard(
    title: 'Station a monster there',
    body:
        'The hut works faster with someone tending it. Open the Healing Hut '
        'and post a monster to its medicine role — a stationed worker keeps '
        'the hut running even while you are away.',
    ctaLabel: '🏥 Open the Healing Hut',
    destination: IntroDestination.healingHut,
  ),
  IntroStep.healStarter => const IntroCard(
    title: 'Heal your monster',
    body:
        'The hut is ready. Treatment costs goods, scaled to the missing HP — '
        'a K.O. costs double. While the tutorial runs it finishes instantly; '
        'later it takes real time, so retreating beats fainting.',
    ctaLabel: '🌿 Treat it now',
    destination: IntroDestination.healingHut,
  ),
  IntroStep.firstCapture => const IntroCard(
    title: 'Catch a second monster',
    body:
        'One monster cannot fight and run a settlement at the same time. '
        'Hunt in Verdant Hollow: fight the wild down — the lower its HP, the '
        'bigger the golden band — then take the catch window and tap as the '
        'ring crosses the band. Right now it cannot faint and will not flee: '
        'take as many tries as you need.',
    ctaLabel: '🗺 Open the map',
    destination: IntroDestination.map,
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

/// Hunt trips are capped at this during the tutorial. Even scaled by
/// kJumpstartTimeScale a hunt is ~40s of dead waiting; the tutorial's catch
/// should be reachable immediately.
const int kIntroMaxTripSeconds = 12;

/// Fish/fur handed to a brand-new player. Buildings make these deliberately
/// slowly (workshop mult 0.12) because they are the region-dungeon entry cost
/// — this is a starter float, not an income, and it is dwarfed by the ~850
/// wood/day target so it cannot dent the Era-I pace. It also covers the
/// tutorial's Healing Hut bill (a K.O.'d starter costs ~6–12 goods).
const double kJumpstartGiftFish = 20.0;
const double kJumpstartGiftFur = 20.0;

// The jumpstart's free "second monster" (kJumpstartFreeTechId = 'team_size_2')
// was REMOVED (user 2026-07-24): party size is now set by position on the
// linear path — the first five battles are always 1v1 and the second slot
// arrives at battle 6, so there is no early team-slot gift to hand out.

/// Applies [kJumpstartTimeScale] to a duration in seconds while [active].
double jumpstartTimeScale(bool active) => active ? kJumpstartTimeScale : 1.0;
