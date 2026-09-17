"""JSON (Dev Mode's own Abilities export) -> an editable .xlsx.

    python tool/export_abilities_xlsx.py ability_export.json abilities.xlsx

Column names are the exact DB column names AbilityDef.fromDefRow/toDefRow
already use (see lib/features/creatures/models/ability_def.dart) — so the
reverse tool (tool/import_abilities_xlsx.py) can round-trip a row with no
guessing about which English label maps to which enum member.

A second "Legend" sheet lists every valid string for the enum-like columns
(element, kind, target, inflict_main, inflict_debuff, self_buff,
self_penalty_stat) — copy-paste those exact spellings; anything else fails
to parse silently back into the wrong default when it's re-imported (see
each *.fromName's `orElse` fallback in the Dart source).
"""
import argparse
import json

from openpyxl import Workbook
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter

# Exact DB column order — matches AbilityDef.toDefRow()/fromDefRow().
COLUMNS = [
    'id', 'name', 'description', 'element', 'kind', 'target',
    'power', 'priority', 'heal_pct', 'lifesteal_pct',
    'inflict_main', 'inflict_main_chance', 'inflict_main_turns', 'inflict_main_value',
    'inflict_debuff', 'inflict_debuff_chance', 'inflict_debuff_turns', 'inflict_debuff_value',
    'self_buff', 'self_buff_turns', 'self_buff_value',
    'self_penalty_stat', 'self_penalty_mult', 'self_penalty_turns',
    'regen_value', 'regen_turns', 'recoil_value',
    'ap_cost', 'unlock_stage',
]

LEGEND = {
    'element': ['fire', 'water', 'plant', 'light', 'shadow', 'neutral'],
    'kind': ['damage', 'heal', 'buff'],
    'target': ['enemy', 'allEnemies', 'ally', 'allAllies', 'self'],
    'inflict_main (blank = none)': ['burn', 'frost', 'poison', 'fear', 'sleep'],
    'inflict_debuff (blank = none)': ['blind', 'speedDown', 'attackDown', 'defenseDown'],
    'self_buff (blank = none)': ['armor', 'rage', 'haste'],
    'self_penalty_stat (blank = none)': ['defense', 'speed'],
}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('src', help='JSON from Dev Mode Export > Abilities')
    ap.add_argument('out', help='.xlsx to write')
    args = ap.parse_args()

    with open(args.src, encoding='utf-8') as f:
        rows = json.load(f)

    wb = Workbook()
    ws = wb.active
    ws.title = 'Abilities'
    ws.append(COLUMNS)
    for cell in ws[1]:
        cell.font = Font(bold=True)
    ws.freeze_panes = 'A2'

    for ability_id in sorted(rows):
        row = rows[ability_id]
        ws.append([row.get(c) for c in COLUMNS])

    # Autosize columns roughly to their header/content width.
    for i, col in enumerate(COLUMNS, start=1):
        letter = get_column_letter(i)
        width = max(len(col), 10)
        ws.column_dimensions[letter].width = width + 2

    legend = wb.create_sheet('Legend')
    legend.append(['column', 'valid values (exact spelling)'])
    for cell in legend[1]:
        cell.font = Font(bold=True)
    for col, values in LEGEND.items():
        legend.append([col, ', '.join(values)])
    legend.column_dimensions['A'].width = 32
    legend.column_dimensions['B'].width = 60

    wb.save(args.out)
    print(f'wrote {args.out}: {len(rows)} abilities x {len(COLUMNS)} columns')


if __name__ == '__main__':
    main()
