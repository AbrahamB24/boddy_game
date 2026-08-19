/// The building art that SHIPS WITH THE APP.
///
/// ── Why bundled and not uploaded (user 2026-08-12) ──
/// "baue die Gebäude einmal in das Game ein oder muss ich was bei supabase
/// machen?" — the answer is: nothing at Supabase. Every era-I building is
/// rendered by tool/blender/render_building.py from a model in this repo, so
/// the picture and the thing that made it belong in the same commit. Shipping
/// them as assets means a fresh install, a new device and a wiped database all
/// show the same settlement, and the art can never be a version behind the
/// model that produced it.
///
/// image_url stays exactly as it was for everything NOT listed here — the
/// upload path in Dev Mode is untouched and still the only way to get a
/// picture onto a building this file does not cover.
///
/// ── A bundled picture WINS over image_url ──
/// The same call the roads made, for the same reason. A def carrying an older
/// uploaded PNG would otherwise silently keep drawing it, and the new art
/// would look like it had never shipped — which is precisely what happened to
/// the road tiles (user 2026-08-09: "es sind noch die alten Strassen"). One
/// picture per building has to come from one place, and the place that is
/// version-controlled alongside the model is the right one.
library;

import 'building_art_box.dart';
import 'building_definitions.dart';

export 'building_art_box.dart' show kBundledArtBox;

/// The ids that have a picture in `assets/images/buildings/`.
///
/// Every entry is a `--preset` in tool/blender/render_building.py under the
/// SAME name, rendered at the footprint the def declares — that is what makes
/// `artBaseWidth: 1.0, artAnchorX: 0.5, artLift: 0.0` (the defaults) correct
/// without any per-building dialling in: frame() puts the footprint diamond
/// flush against the picture's left, right and bottom edges.
const Set<String> kBundledBuildingArt = {
  'refinery_e2',
  'training_grounds',
  'thinker_circle',
  'castle',
  'breeding_hut',
  'small_house',
  'large_house',
  'small_wood_camp',
  'small_stone_camp',
  'large_wood_camp',
  'large_stone_camp',
  'storehouse',
  'gold_vault',
  'builder_camp',
  'healing_hut',
  'scout_post',
  'trading_post',
  'caravanserai',
  'hatchery',
  'lux_fish',
  'lux_fur',
  'church',
  'marketplace',
};

/// The three placement numbers to use for [def]: the ones the RENDERER
/// measured when the picture ships with the app, the def's own otherwise.
///
/// ── The picture is not the tile (user 2026-08-12) ──
/// "die Burg schneidet das healing hut ab". The render frame used to be the
/// footprint diamond exactly, so anything leaning past it — a roof eave, a
/// spire, a castle turret — was cut off against a straight vertical edge. It
/// grows sideways now to hold the whole model, which means the diamond sits
/// somewhere INSIDE the picture rather than being equal to it, and these three
/// numbers say where. See [kBundledArtBox] and `artPlacement` in
/// data/iso_grid.dart.
///
/// A def's own artBaseWidth/artAnchorX/artLift still apply to everything not
/// bundled — the Dev Mode upload path is untouched.
({double baseWidth, double anchorX, double lift}) artBoxOf(BuildingDef def) {
  final b = kBundledArtBox[def.id];
  return b == null
      ? (
          baseWidth: def.artBaseWidth,
          anchorX: def.artAnchorX,
          lift: def.artLift,
        )
      : (baseWidth: b.$1, anchorX: b.$2, lift: b.$3);
}

/// The asset path for [defId], or null when nothing is bundled for it.
///
/// Null is the ordinary case, not a failure: the roster has 89 buildings and
/// twenty of them are modelled so far. Callers fall back to image_url and then
/// to the decorative box, in that order.
String? buildingAsset(String? defId) =>
    defId != null && kBundledBuildingArt.contains(defId)
    ? 'assets/images/buildings/$defId.webp'
    : null;
