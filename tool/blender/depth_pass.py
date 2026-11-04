"""The DEPTH MAP of a building monsters walk into (the Castle, user
2026-11-03: "Manchmal sind sie über Gebäuden, obwohl sie dahinter sein
sollten").

Two halves were not enough: a monster in the yard stands in front of some
things in the back half and behind some in the front half. So every pixel of
the picture gets the depth of the ground BELOW what it shows — how far
forward on the map that thing stands — and the map, after drawing a monster
inside the building, draws the picture once more over it, but only where
that depth is in front of the monster's feet (settlement_map.dart,
_BuildingOccluder). A wall, a tower or a roof is a column standing on its
ground, so "its ground is in front of my feet" is exactly "it hides me".

    <art>_depth.png   8-bit grey, the picture's aspect, 1/DOWN of its size:
                      0 = nothing there; 1..255 = the ground below the
                      visible surface, 1 at the footprint diamond's BACK
                      corner, 255 at its FRONT corner — i.e.
                      (gx + gy) / (W + H) of the turned footprint.

One extra render per turn: every surface emits its own world position, one
sample, no light bounces — seconds, not minutes.
"""
import os
import struct
import zlib

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector


def _position_material():
    m = bpy.data.materials.get('__position')
    if m:
        return m
    m = bpy.data.materials.new('__position')
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    em = nt.nodes.new('ShaderNodeEmission')
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(geo.outputs['Position'], em.inputs['Color'])
    em.inputs['Strength'].default_value = 1.0
    nt.links.new(em.outputs['Emission'], out.inputs['Surface'])
    return m


def _png_gray(path, a):
    """A plain 8-bit greyscale PNG (no gamma chunk: the values are data)."""
    h, w = a.shape
    raw = b''.join(b'\x00' + a[y].tobytes() for y in range(h))

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 0, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)


def render_depth(dst, tmp_dir, W, H, down=4):
    """Render the position pass with the current camera and write <dst>.
    W, H: the footprint in tiles, centred on the origin, ground at z = 0."""
    sc = bpy.context.scene
    vl = bpy.context.view_layer
    cy = sc.cycles
    keep = dict(samples=cy.samples, denoise=cy.use_denoising,
                bounces=cy.max_bounces, filt=cy.filter_width,
                vt=sc.view_settings.view_transform, look=sc.view_settings.look,
                exp=sc.view_settings.exposure, fmt=sc.render.image_settings.file_format,
                depth=sc.render.image_settings.color_depth,
                mode=sc.render.image_settings.color_mode,
                path=sc.render.filepath, override=vl.material_override)
    cy.samples = 1
    cy.use_denoising = False
    cy.max_bounces = 0
    cy.filter_width = 0.01            # one surface per pixel, no blending
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    vl.material_override = _position_material()
    st = sc.render.image_settings
    st.file_format = 'OPEN_EXR'
    st.color_depth = '32'
    st.color_mode = 'RGBA'
    exr = os.path.join(tmp_dir, '__position.exr')
    sc.render.filepath = exr
    bpy.ops.render.render(write_still=True)

    cy.samples, cy.use_denoising, cy.max_bounces, cy.filter_width = (
        keep['samples'], keep['denoise'], keep['bounces'], keep['filt'])
    sc.view_settings.view_transform = keep['vt']
    sc.view_settings.look = keep['look']
    sc.view_settings.exposure = keep['exp']
    vl.material_override = keep['override']
    st.file_format, st.color_depth, st.color_mode = keep['fmt'], keep['depth'], keep['mode']
    sc.render.filepath = keep['path']

    img = bpy.data.images.load(exr)
    iw, ih = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(ih, iw, 4)[::-1]
    bpy.data.images.remove(img)

    # The camera is orthographic: a ground point's picture row is linear in
    # its x and y. Measure that line, and the footprint diamond's back and
    # front corners on it.
    def v(x, y):
        return world_to_camera_view(sc, sc.camera, Vector((x, y, 0.0))).y
    v0 = v(0, 0)
    ax, ay = v(1, 0) - v0, v(0, 1) - v0
    corners = [v(sx * W / 2, sy * H / 2) for sx in (-1, 1) for sy in (-1, 1)]
    back, front = max(corners), min(corners)   # v runs UP the picture
    vg = v0 + ax * px[..., 0] + ay * px[..., 1]
    frac = np.clip((back - vg) / (back - front), 0.0, 1.0)
    val = np.where(px[..., 3] > 0.5, 1 + np.round(frac * 254), 0).astype(np.uint8)

    # Shrink by taking the most FORWARD value of every block: an edge pixel
    # counts as the thing in front, and the picture's own alpha shapes it.
    hh, ww = -(-ih // down) * down, -(-iw // down) * down
    pad = np.zeros((hh, ww), np.uint8)
    pad[:ih, :iw] = val
    small = pad.reshape(hh // down, down, ww // down, down).max(axis=(1, 3))
    _png_gray(dst, small)
    print('DEPTH', dst, small.shape[1], 'x', small.shape[0])
