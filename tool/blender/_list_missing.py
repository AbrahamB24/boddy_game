import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icon_lib as L
import icons3d_a, icons3d_b, icons3d_c, icons3d_d
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'images', 'icons'))
have = {f[:-5] for f in os.listdir(root) if f.endswith('.webp')}
print('MISSING', sorted(have - set(L.REG)))
print('EXTRA', sorted(set(L.REG) - have))
print('COUNT', len(L.REG))
