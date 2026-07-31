// GENERATOR (not a real test): serialises the LIVE bundled building roster
// (kFallbackBuildingDefs, the single source of truth in building_definitions
// .dart) to a Supabase upsert script via toDefRow(). Run with:
//   flutter test test/gen_building_sql_test.dart
// It writes building_roster.sql at the repo root.
//
// This used to reimplement the whole roster (cost/cap/era formulas) a SECOND
// time here, which silently drifted from the app's own roster (user 2026-07-25:
// the Hatchery + Breeding Hut role went missing in the SQL). It now reads the
// same map the app ships, so the SQL can never diverge from the code.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';

String _sql(List<BuildingDef> defs) {
  String q(String s) => "'${s.replaceAll("'", "''")}'";
  String jb(Object? v) => "${q(jsonEncode(v))}::jsonb";

  final cols = [
    'id', 'name', 'image_url', 'color', 'grid_w', 'grid_h', 'resource_cost',
    'construction_hours', 'era_ids', 'is_main_building', 'is_unique', 'is_road',
    'is_build_plot', 'required_tech_id', 'population', 'max_count', 'effects',
    'metadata',
  ];

  final rows = <String>[];
  for (final d in defs) {
    final r = d.toDefRow();
    final vals = [
      q(r['id'] as String),
      q(r['name'] as String),
      r['image_url'] == null ? 'NULL' : q(r['image_url'] as String),
      q(r['color'] as String),
      '${r['grid_w']}',
      '${r['grid_h']}',
      jb(r['resource_cost']),
      '${r['construction_hours']}',
      jb(r['era_ids']),
      '${r['is_main_building']}',
      '${r['is_unique']}',
      '${r['is_road']}',
      '${r['is_build_plot']}',
      r['required_tech_id'] == null
          ? 'NULL'
          : q(r['required_tech_id'] as String),
      '${r['population']}',
      '${r['max_count']}',
      jb(r['effects']),
      jb(r['metadata']),
    ].join(', ');
    rows.add('  ($vals)');
  }

  return '''
-- ═══════════════════════════════════════════════════════════════════════════
-- Bøddy — building roster, generated from kFallbackBuildingDefs.
-- Paste into the Supabase SQL editor. REPLACES every building def.
-- ${defs.length} buildings.
-- ═══════════════════════════════════════════════════════════════════════════
-- Ensure every column toDefRow() writes exists (idempotent — mirrors migration
-- 0024_def_tables.sql). Fixes "column metadata does not exist".
alter table public.building_defs
  add column if not exists image_url          text,
  add column if not exists color              text,
  add column if not exists grid_w             int  not null default 1,
  add column if not exists grid_h             int  not null default 1,
  add column if not exists resource_cost      jsonb not null default '{}'::jsonb,
  add column if not exists construction_hours double precision not null default 0,
  add column if not exists era_ids            jsonb not null default '[]'::jsonb,
  add column if not exists is_main_building   boolean not null default false,
  add column if not exists is_unique          boolean not null default false,
  add column if not exists is_road            boolean not null default false,
  add column if not exists is_build_plot      boolean not null default false,
  add column if not exists required_tech_id   text,
  add column if not exists population         int not null default 0,
  add column if not exists max_count          int not null default 0,
  add column if not exists effects            jsonb not null default '[]'::jsonb,
  add column if not exists metadata           jsonb not null default '{}'::jsonb;

begin;
delete from public.building_defs;
insert into public.building_defs
  (${cols.join(', ')})
values
${rows.join(',\n')};
commit;
''';
}

void main() {
  test('generate building roster SQL from the live roster', () {
    final defs = kFallbackBuildingDefs.values.toList();
    File('building_roster.sql').writeAsStringSync(_sql(defs));
    // ignore: avoid_print
    print('Wrote building_roster.sql with ${defs.length} buildings.');
    expect(defs.length, greaterThan(40));
  });
}
