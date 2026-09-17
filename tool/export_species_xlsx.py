"""JSON (Dev Mode's own Arten export) -> an editable .xlsx.

    python tool/export_species_xlsx.py species_export.json monsters.xlsx

One row per species, flattened: every stat's 3-stage base plus its shared
growth as its own column (SpeciesDef.stats — see
lib/features/creatures/models/species_def.dart), the 3 evolution stages'
names/art, and the ability set as one semicolon-joined cell
("id:unlockStage; id:unlockStage; ...") rather than a second sheet — five
abilities per species is easy enough to read and edit inline, and it keeps
one species to one row.

`role` is split into its two authored halves (SpeciesDef.roleArchetype /
.roleWorkPriorities) since the raw "archetype|prio1,prio2" encoding is not
something you'd want to hand-edit as one string.
"""
import argparse
import json

from openpyxl import Workbook
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter

# Same order CreatureStat is declared in (creature_enums.dart) — combat
# stats first, then the work-role stats, then the two utility ones.
STATS = [
    'hp', 'attack', 'defense', 'speed', 'catchRate',
    'gathering', 'production', 'construction', 'crafting', 'breeding',
    'medicine', 'trade', 'logistics', 'carry',
]

HEAD = [
    'id', 'name', 'description', 'element', 'rarity',
    'role_archetype', 'role_work_priorities',
    'catch_rate', 'evo_level_1', 'evo_level_2', 'tier',
]
STAGE_COLS = [
    f'stage{n}_{field}'
    for n in range(3)
    for field in ('name', 'image_url', 'back_image_url')
]
STAT_COLS = [
    f'{s}_{field}' for s in STATS for field in ('base0', 'base1', 'base2', 'growth')
]
COLUMNS = HEAD + STAT_COLS + STAGE_COLS + ['abilities']

LEGEND = {
    'element': ['fire', 'water', 'plant', 'light', 'shadow'],
    'rarity': ['common', 'uncommon', 'rare', 'epic', 'legendary'],
    'role_work_priorities (comma-separated CreatureStat names)': STATS,
    'abilities format': ['ability_id:unlock_stage; ability_id:unlock_stage; ...  '
                         '(unlock_stage 0/1/2 — see the Abilities workbook for ids)'],
}


def role_parts(role: str) -> tuple[str, str]:
    parts = (role or '').split('|')
    archetype = parts[0]
    priorities = parts[1] if len(parts) > 1 else ''
    return archetype, priorities


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('src', help='JSON from Dev Mode Export > Arten')
    ap.add_argument('out', help='.xlsx to write')
    args = ap.parse_args()

    with open(args.src, encoding='utf-8') as f:
        rows = json.load(f)

    wb = Workbook()
    ws = wb.active
    ws.title = 'Species'
    ws.append(COLUMNS)
    for cell in ws[1]:
        cell.font = Font(bold=True)
    ws.freeze_panes = 'C2'

    for species_id in sorted(rows):
        row = rows[species_id]
        archetype, priorities = role_parts(row.get('role', ''))
        stages = row.get('stages') or []
        stats = row.get('stats') or {}

        out = [
            row.get('id'), row.get('name'), row.get('description'),
            row.get('element'), row.get('rarity'),
            archetype, priorities,
            row.get('catch_rate'), row.get('evo_level_1'), row.get('evo_level_2'),
            row.get('tier'),
        ]
        for s in STATS:
            curve = stats.get(s) or {}
            base = curve.get('stage_base') or [None, None, None]
            base = (base + [None, None, None])[:3]
            out.extend(base)
            out.append(curve.get('growth'))
        for n in range(3):
            stage = stages[n] if n < len(stages) else {}
            out.extend([stage.get('name'), stage.get('image_url'), stage.get('back_image_url')])
        abilities = row.get('abilities') or []
        out.append('; '.join(f"{a['id']}:{a.get('unlock_stage', 0)}" for a in abilities))

        ws.append(out)

    for i, col in enumerate(COLUMNS, start=1):
        letter = get_column_letter(i)
        width = 30 if 'image_url' in col else (24 if col == 'abilities' else max(len(col), 9))
        ws.column_dimensions[letter].width = width + 1

    legend = wb.create_sheet('Legend')
    legend.append(['column', 'valid values / format'])
    for cell in legend[1]:
        cell.font = Font(bold=True)
    for col, values in LEGEND.items():
        legend.append([col, ', '.join(values)])
    legend.column_dimensions['A'].width = 42
    legend.column_dimensions['B'].width = 70

    wb.save(args.out)
    print(f'wrote {args.out}: {len(rows)} species x {len(COLUMNS)} columns')


if __name__ == '__main__':
    main()
