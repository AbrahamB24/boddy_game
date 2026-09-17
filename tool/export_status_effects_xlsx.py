"""The status-effect catalog (lib/features/creatures/models/status_effects.dart)
as an .xlsx — NOT a DB export, this is fixed code, so there is no matching
JSON to feed it from and no import path back. Edit lib/features/creatures/
models/status_effects.dart directly for changes; this file is a readable
reference only.

    python tool/export_status_effects_xlsx.py status_effects.xlsx
"""
import argparse

from openpyxl import Workbook
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter


def _sheet(wb, title, headers, rows):
    ws = wb.create_sheet(title)
    ws.append(headers)
    for cell in ws[1]:
        cell.font = Font(bold=True)
    for row in rows:
        ws.append(row)
    for i, h in enumerate(headers, start=1):
        letter = get_column_letter(i)
        width = max(len(str(h)), *(len(str(r[i - 1])) for r in rows)) if rows else len(str(h))
        ws.column_dimensions[letter].width = width + 2
    ws.freeze_panes = 'A2'
    return ws


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('out', help='.xlsx to write')
    args = ap.parse_args()

    wb = Workbook()
    wb.remove(wb.active)

    _sheet(
        wb, 'Main status',
        ['status', 'emoji', 'duration_turns', 'dot_pct_of_max_hp', 'attack_mult',
         'speed_mult', 'skip_chance', 'notes'],
        [
            ['burn', '🔥', 3, '5% flat', 0.80, 1.0, 0.0, ''],
            ['frost', '❄️', 2, '0', 1.0, 0.60, 0.10, ''],
            ['poison', '☠️', 4, '6% + 2%*turns_active (6/8/10/12%)', 1.0, 1.0, 0.0,
             'escalates each of its own turns, 0-indexed'],
            ['fear', '😨', 3, '0', 1.0, 1.0, 0.25, ''],
            ['sleep', '😴', 2, '0', 1.0, 1.0, 0.85,
             'only one main status active at a time (mutually exclusive)'],
        ],
    )

    _sheet(
        wb, 'Secondary debuffs',
        ['debuff', 'emoji', 'duration_turns', 'effect'],
        [
            ['blind', '👁️', 2, 'accuracy x0.75'],
            ['speedDown', '🐌', 2, 'speed x0.70'],
            ['attackDown', '💤', 2, 'attack x0.75'],
            ['defenseDown', '🪓', 2, 'defense x0.70'],
        ],
    )
    wb['Secondary debuffs'].append([])
    wb['Secondary debuffs'].append(
        ['note', '', '', 'stack independently of the main status AND of each '
                         'other (e.g. a burned target can also be blinded)'])

    _sheet(
        wb, 'Self buffs',
        ['buff', 'emoji', 'duration_turns', 'effect'],
        [
            ['armor', '🛡️', 2, 'defense x1.30'],
            ['rage', '💢', 2, 'attack x1.25'],
            ['haste', '⏱️', 2, 'speed x1.30'],
        ],
    )
    wb['Self buffs'].append([])
    wb['Self buffs'].append(
        ['note', '', '', 'a combatant can hold all 3 at once; reapplying one '
                         'REFRESHES its duration rather than stacking magnitude'])

    _sheet(
        wb, 'Self penalty (per-ability)',
        ['stat', 'notes'],
        [
            ['defense', 'e.g. Power Surge (kraftakt): x0.90, 1 turn'],
            ['speed', "e.g. Gaia's Wrath (gaia_zorn): x0.70, 1 turn"],
        ],
    )
    wb['Self penalty (per-ability)'].append([])
    wb['Self penalty (per-ability)'].append([
        'note', 'no fixed catalog value — each ability sets its own mult/turns '
                '(self_penalty_mult / self_penalty_turns in the Abilities workbook); '
                'always applies, no chance roll',
    ])

    wb.save(args.out)
    print(f'wrote {args.out}')


if __name__ == '__main__':
    main()
