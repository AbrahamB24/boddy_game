"""Generic rigid-voxel rig for ANY monster, plus a baker that writes the sheets the game reads.

A monster is a set of named parts (groups of objects), each voxelised ONCE on the shared grid and
parented to a pivot at its joint; an animation only moves and turns finished blocks. Parts form a
tree (chest -> head -> beak, shoulder -> wing, hip -> leg -> foot ...), so a pose is a set of small
deltas that add up down the tree.

    parts  = {name: (parent_name_or_None, pivot_xyz)}   # parents first; parent None = the root
    groups = {name: [objects]}                          # objects built with b.grp = name

Poses are functions pose(rig, t), t in [0, 1). They fill a Pose (add() sums layers) and call
rig.apply(pose). Rotations are in degrees on the part's pivot, the creature faces +x:
    rot y > 0 : the top tips FORWARD (head nods down); a tip pointing +x swings DOWN
    rot x     : roll; for a part hanging down on the +y side, rot x > 0 swings it OUT
    rot z     : yaw (turn left, towards +y)
Rigid blocks never appear, vanish or change colour, so nothing shimmers. Only tiny parts (eyes,
sparks) are ever scaled.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glimmergnaw_bake as gb  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

COLS = gb.COLS


# ── small animation maths ─────────────────────────────────────
def ramp(t, a, b):
    """0 before a, 1 after b, smooth between."""
    return gb.smooth((t - a) / (b - a)) if b != a else float(t >= a)


def pulse(t, a, b, c, d):
    """Rises a->b, holds, falls c->d."""
    return ramp(t, a, b) * (1 - ramp(t, c, d))


def breath(t, k=2, lag=0.0):
    """One inhale+exhale per 1/k of the clip: 0 at t=0 and t=1 (exhaled), 1 fully inhaled."""
    return 0.5 - 0.5 * math.cos(2 * math.pi * (k * t - lag))   # lag in breath CYCLES, so every clip starts and ends at the same value


def osc(t, f, ph=0.0):
    return math.sin(2 * math.pi * (f * t + ph))


def burst(t, t0, f, decay, amp=1.0):
    """A damped shake that starts at t0 (head shake, a recoil wobble)."""
    if t < t0:
        return 0.0
    u = t - t0
    return amp * math.exp(-decay * u) * math.sin(2 * math.pi * f * u)


def blink(t, t0, w=0.05):
    """0 open .. 1 closed, a quick lid-down and a slower lid-up."""
    u = (t - t0) / w
    if u < 0 or u > 2.2:
        return 0.0
    return math.sin(min(u, 1.0) * math.pi / 2) if u <= 1.0 else 1.0 - gb.smooth((u - 1.0) / 1.2)


class Pose:
    """Layers add up: p.add('head', rot=(0, 5, 0)) twice gives 10 degrees."""

    def __init__(self):
        self.d, self.rot, self.scale, self.gro = {}, {}, {}, {}

    def grow(self, name, dx=0.0, dy=0.0, dz=0.0):
        """Scale a part by 1 + delta per axis about its pivot. Layers add up. This is how breathing swells a
        single body mesh: it has no seam, no gap and no overlapping surface, so it can never flicker."""
        g = self.gro.setdefault(name, [0.0, 0.0, 0.0])
        g[0] += dx
        g[1] += dy
        g[2] += dz

    def add(self, name, d=(0, 0, 0), rot=(0, 0, 0)):
        a = self.d.setdefault(name, [0.0, 0.0, 0.0])
        b = self.rot.setdefault(name, [0.0, 0.0, 0.0])
        for i in range(3):
            a[i] += d[i]
            b[i] += rot[i]

    def set_scale(self, name, s):
        self.scale[name] = s

    def blend(self, other, w):
        """self * (1 - w) + other * w, part by part: a smooth transition between two poses (rest to walk, walk to rest)."""
        out = Pose()
        names = set(self.d) | set(other.d) | set(self.gro) | set(other.gro) | set(self.scale) | set(other.scale)
        for n in names:
            for src, dst in ((self.d, other.d), (self.rot, other.rot), (self.gro, other.gro)):
                pass
            a, b = self.d.get(n, [0.0] * 3), other.d.get(n, [0.0] * 3)
            out.d[n] = [x + (y - x) * w for x, y in zip(a, b)]
            a, b = self.rot.get(n, [0.0] * 3), other.rot.get(n, [0.0] * 3)
            out.rot[n] = [x + (y - x) * w for x, y in zip(a, b)]
            a, b = self.gro.get(n, [0.0] * 3), other.gro.get(n, [0.0] * 3)
            out.gro[n] = [x + (y - x) * w for x, y in zip(a, b)]

            def sv(p):
                s = p.scale.get(n)
                if s is None:
                    return None
                return tuple(s) if isinstance(s, tuple) else (s, s, s)
            sa, sb = sv(self), sv(other)
            if sa is not None or sb is not None:
                sa, sb = sa or (1, 1, 1), sb or (1, 1, 1)
                out.scale[n] = tuple(x + (y - x) * w for x, y in zip(sa, sb))
        return out


class Rig:
    def __init__(self, parts, groups):
        gb.tw.SMOOTH_MATS = True
        self.face = bpy.data.objects.new('face', None)
        self.root = bpy.data.objects.new('root', None)
        for e in (self.face, self.root):
            bpy.context.scene.collection.objects.link(e)
        self.root.parent = self.face
        self.piv, self.base, self.world, self.vox = {}, {}, {}, []
        for name, (parent, pivot) in parts.items():
            objs = groups.get(name, [])
            vox = None
            if objs:
                vox = tw.voxelise(objs)
                vox.name = 'vox_' + name
                self.vox.append(vox)
            if pivot is None:                                    # static part: rides on the root
                if vox:
                    vox.parent = self.root
                continue
            world = Vector(pivot)
            piv = bpy.data.objects.new('piv_' + name, None)
            bpy.context.scene.collection.objects.link(piv)
            if parent is None or parent == 'root':
                piv.parent = self.root
                piv.location = world
            else:
                piv.parent = self.piv[parent]
                piv.location = world - self.world[parent]
            piv.matrix_parent_inverse = Matrix.Identity(4)
            bpy.context.view_layer.update()
            if vox:
                vox.parent = piv
                vox.matrix_parent_inverse = piv.matrix_world.inverted()
            self.piv[name] = piv
            self.base[name] = piv.location.copy()
            self.world[name] = world
        self.mats = {m.name: m for m in bpy.data.materials}
        for n, m in self.mats.items():
            if n in ('white', 'dark', 'eyewhite') or 'glow' in n:
                continue
            b = m.node_tree.nodes['Principled BSDF']
            b.inputs['Emission Color'].default_value = b.inputs['Base Color'].default_value
            b.inputs['Emission Strength'].default_value = 0.30
        for n, m in self.mats.items():
            if n not in ('white', 'dark', 'eyewhite') and 'glow' not in n:
                gb.Rig.crease_shade(m)
                for nd in m.node_tree.nodes:
                    if nd.bl_idname == 'ShaderNodeAmbientOcclusion':
                        nd.samples = 24
                        nd.only_local = True         # shade only against the part's OWN geometry: a neighbouring part that
                                                     # moves can never switch dots or patches on and off
        self.emit0 = {}
        for n, m in self.mats.items():
            b = m.node_tree.nodes['Principled BSDF']
            self.emit0[n] = (tuple(b.inputs['Emission Color'].default_value), b.inputs['Emission Strength'].default_value)
        self.reset()

    def reset(self):
        self.root.location = (0, 0, 0)
        self.root.rotation_euler = (0, 0, 0)
        for n, p in self.piv.items():
            p.location = self.base[n]
            p.rotation_euler = (0, 0, 0)
            p.scale = (1, 1, 1)
        self.flash(0.0)

    def apply(self, pose):
        for name, d in pose.d.items():
            rot = pose.rot[name]
            ob = self.root if name == 'root' else self.piv.get(name)
            if ob is None:
                continue
            ob.location = Vector(d) if name == 'root' else self.base[name] + Vector(d)
            ob.rotation_euler = Euler([math.radians(a) for a in rot])
        for name, g in pose.gro.items():
            ob = self.piv.get(name)
            if ob is not None:
                ob.scale = (1 + g[0], 1 + g[1], 1 + g[2])
        for name, s in pose.scale.items():
            ob = self.piv.get(name)
            if ob is not None:
                ob.scale = (s, s, s) if isinstance(s, (int, float)) else s

    def flash(self, v):
        for n, m in self.mats.items():
            b = m.node_tree.nodes['Principled BSDF']
            if v > 0:
                b.inputs['Emission Color'].default_value = (1, 1, 1, 1)
                b.inputs['Emission Strength'].default_value = v
            else:
                b.inputs['Emission Color'].default_value = self.emit0[n][0]
                b.inputs['Emission Strength'].default_value = self.emit0[n][1]


# ── baking ────────────────────────────────────────────────────
def bake(build_rig, table, out, views='front', samples=24, scale=1.0, map_k=1.3, monster='monster', stage=0,
         shadow=(0.52, 0.40, -0.04), only=None, map_anims=('walk', 'idle'), headings=None):
    """build_rig() -> Rig (called fresh for each view). table: name -> (frames, fps, loop, pose)."""
    out = os.path.abspath(out)
    os.makedirs(out, exist_ok=True)
    tmp = os.path.join(out, '_frames')
    os.makedirs(tmp, exist_ok=True)
    gb.FW, gb.FH = int(560 * scale), int(448 * scale)
    gb.ANIMS = table
    for view in views.split(','):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        rig = build_rig()
        gb.engine(samples)
        cy = bpy.context.scene.cycles
        cy.use_adaptive_sampling = False     # adaptive sampling stops per pixel and per frame at different points = shimmer
        cy.seed = 7                          # one fixed noise pattern for every frame
        cy.use_animated_seed = False
        names = [n for n in table if not only or n in only]
        if view == 'map':
            shadow_obj = gb.contact_shadow(0)
            shadow_obj.scale = (shadow[0], shadow[1], 1)
            shadow_obj.location = (shadow[2], 0, 0.004)
            gb.shadow_catcher(3.4 * map_k)
            gb.lights(Vector((1, 1, 1)) * 5, Vector((0, 0, 0)), 0.3)
            rb.frame(1.7 * map_k, 1.7 * map_k, 5 / map_k, 0.80, 0.0, fit=False)
            sc = bpy.context.scene
            if scale != 1.0:
                sc.render.resolution_x = int(sc.render.resolution_x * scale)
                sc.render.resolution_y = int(sc.render.resolution_y * scale)
            meta = {'monster': monster, 'stage': stage, 'view': 'map', 'cols': COLS, 'frame_w': sc.render.resolution_x,
                    'frame_h': sc.render.resolution_y, 'headings': {'se': '+x', 'ne': '+y', 'nw': '-x', 'sw': '-y'}, 'anims': {}}
            for h, yaw in gb.HEADINGS.items():
                if headings and h not in headings:
                    continue
                rig.face.rotation_euler = (0, 0, math.radians(yaw))
                tbl = {k: table[k] for k in map_anims if k in table}
                gb.run_anims(rig, [k for k in tbl if not only or k in only], tbl, h, out, tmp, meta['anims'].setdefault(h, {}))
            with open(os.path.join(out, 'meta_map.json'), 'w') as f:
                json.dump(meta, f, indent=2)
        else:
            gb.shadow_catcher(5.0)
            shadow_obj = gb.contact_shadow(0)
            shadow_obj.scale = (shadow[0], shadow[1], 1)
            shadow_obj.location = (shadow[2], 0, 0.004)
            battle = {k: v for k, v in table.items() if k not in map_anims or k == 'idle'}
            gb.ANIMS = battle
            cam_loc = gb.battle_camera(rig, gb.VIEWS[view])
            gb.lights(cam_loc, Vector((0, 0, 0.5)), 0.25)
            meta = {'monster': monster, 'stage': stage, 'view': view, 'frame_w': gb.FW, 'frame_h': gb.FH, 'cols': COLS, 'anims': {}}
            gb.run_anims(rig, [n for n in battle if not only or n in only], battle, view, out, tmp, meta['anims'])
            with open(os.path.join(out, f'meta_{view}.json'), 'w') as f:
                json.dump(meta, f, indent=2)
            gb.ANIMS = table
    print('done', out)


def clearance(rig, table, body='body', ellipsoid=((0, 0, .36), (.31, .29, .30)), watch=('foot_p', 'foot_n'), limit=0.30, tilt=0.0,
              step=1, verbose=True):
    """No watched part may sink into the body. For every frame of every clip, count the share of each watched part's
    voxel corners that lie inside the body ellipsoid (in the body's own rest frame, so it follows scaling and tilt).
    Returns a list of (clip, frame, part, share) for every frame above rest-share + limit. Catches a foot that
    swings up into the belly and vanishes (user 2026-11-11)."""
    c = Vector(ellipsoid[0])
    r = Vector(ellipsoid[1])
    bv = next((v for v in rig.vox if v.name == 'vox_' + body), None)
    wv = {w: next((v for v in rig.vox if v.name == 'vox_' + w), None) for w in watch}

    def share(v):
        inv = bv.matrix_world.inverted()
        pts = v.data.vertices
        n = len(pts)
        inside = 0
        pick = max(1, n // 400)
        cnt = 0
        for i in range(0, n, pick):
            p = Matrix.Rotation(-tilt, 3, 'Y') @ (inv @ (v.matrix_world @ pts[i].co) - c)
            if (p.x / r.x) ** 2 + (p.y / r.y) ** 2 + (p.z / r.z) ** 2 < 0.90:
                inside += 1
            cnt += 1
        return inside / max(1, cnt)

    rig.reset()
    bpy.context.view_layer.update()
    rest = {w: share(v) for w, v in wv.items() if v}
    bad = []
    for name, (n, fps, loop, fn) in table.items():
        worst = {w: 0.0 for w in rest}
        for i in range(0, n, step):
            rig.reset()
            fn(rig, i / n)
            bpy.context.view_layer.update()
            for w, v in wv.items():
                if not v:
                    continue
                s = share(v)
                worst[w] = max(worst[w], s - rest[w])
                if s - rest[w] > limit:
                    bad.append((name, i, w, round(s, 2)))
        if verbose:
            print('clearance %-13s %s' % (name, '  '.join('%s +%.2f' % (w, worst[w]) for w in worst)), flush=True)
    rig.reset()
    return bad


# ── ground rule: nothing of a monster may ever go below the floor (user 2026-11-12) ────────────────
def _floor_cache(rig):
    import numpy as np
    if not hasattr(rig, '_vc'):
        rig._vc = []
        for ob in rig.vox:
            n = len(ob.data.vertices)
            a = np.empty(n * 3, dtype=np.float32)
            ob.data.vertices.foreach_get('co', a)
            rig._vc.append((ob, a.reshape(-1, 3)))
    return rig._vc


def lowest_z(rig):
    """Lowest world z of any voxel vertex of any part, in the rig's current pose."""
    import numpy as np
    bpy.context.view_layer.update()
    low = 1e9
    for ob, co in _floor_cache(rig):
        m = np.array(ob.matrix_world, dtype=np.float32)
        z = co @ m[2, :3] + m[2, 3]
        low = min(low, float(z.min()))
    return low


def ground_clamp(rig, floor):
    """After a pose: if anything sank below `floor`, lift the whole creature just enough. Skips fake rigs."""
    if not hasattr(rig, 'vox'):
        return
    d = floor - lowest_z(rig)
    if d > 0.002:
        rig.root.location = rig.root.location + Vector((0, 0, d))


def ground_report(rig, table, tol=0.004, verbose=True):
    """Every frame of every clip: how far below the rest-pose floor does anything reach? Returns the violations."""
    rig.reset()
    floor = lowest_z(rig)
    bad = []
    for name, (n, fps, loop, fn) in table.items():
        worst = 0.0
        for i in range(n + 1):
            rig.reset()
            fn(rig, min(i, n - 1) / n if i < n else 1.0)
            depth = floor - lowest_z(rig)
            worst = max(worst, depth)
            if depth > tol:
                bad.append((name, i, round(depth, 3)))
        if verbose:
            print('ground %-9s worst %.3f %s' % (name, worst, '' if worst <= tol else '   <-- BELOW GROUND'), flush=True)
    rig.reset()
    return bad
