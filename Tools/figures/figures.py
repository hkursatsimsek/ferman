# Unit art for FERMAN (D24, D25): cast-metal miniatures modelled from primitives, rendered from
# straight above with Cycles, and written into the app's asset catalog under the names `UnitArt`
# expects. Run headless with a pinned Blender (see README.md):
#
#     blender --background --factory-startup --python Tools/figures/figures.py -- \
#         --atlas App/Ferman/Assets.xcassets/Units.spriteatlas \
#         [--terrain App/Ferman/Assets.xcassets/Terrain] [--contact-sheet sheet.png] [--only okcu]
#
# Scene units are canvas points: the camera frames a 48 x 48 point square, the figure's base is centred
# on the origin, the figure faces +Y (up on screen) and +Z points at the camera. Everything the lamp does
# is rotationally symmetric about Z (a sun straight down and a sky that only depends on elevation), so a
# figure stays correctly lit however SpriteKit turns it (ART-DIRECTION §3).
#
# Only Blender's bundled Python and numpy are used; PNGs are encoded here, without metadata, so the same
# Blender build writes the same bytes every run.

import argparse
import math
import os
import struct
import sys
import tempfile
import zlib

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

CANVAS = 48.0
PIXELS_PER_POINT = 6  # rendered at 6 px/pt, box-filtered down to 3x (/2) and 2x (/3)
SCALES = {3: 2, 2: 3}  # asset scale -> downsampling factor
INK = (0x0F, 0x16, 0x1B)
UNIT_TYPES = ["mizrakci", "okcu", "suvari", "kalkan"]
POSES = ["base", "strike", "brace", "fallen"]
TEAMS = {"brass": "round", "iron": "octagonal"}  # material -> base shape (D24: shape, not colour, tells teams)


# MARK: - Colour

def srgb_to_linear(value):
    value = value / 255.0
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def linear(hex_value):
    return tuple(srgb_to_linear((hex_value >> shift) & 0xFF) for shift in (16, 8, 0))


def encode_srgb(values):
    values = np.clip(values, 0.0, 1.0)
    return np.where(values <= 0.0031308, values * 12.92, 1.055 * np.power(values, 1 / 2.4) - 0.055)


# MARK: - PNG

def write_png(path, rgba):
    """8-bit straight-alpha RGBA, top row first, sRGB chunk, no timestamps."""
    height, width, _ = rgba.shape
    raw = b"".join(b"\x00" + rgba[row].tobytes() for row in range(height))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"sRGB", b"\x00")
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as handle:
        handle.write(data)


def to_png_bytes(premultiplied):
    """Premultiplied linear float RGBA -> straight sRGB uint8, flipped so the top row comes first."""
    alpha = premultiplied[..., 3:4]
    colour = np.where(alpha > 1e-6, premultiplied[..., :3] / np.maximum(alpha, 1e-6), 0.0)
    out = np.concatenate([encode_srgb(colour), np.clip(alpha, 0, 1)], axis=-1)
    return np.flipud(np.round(out * 255).astype(np.uint8)).copy()


def downsample(premultiplied, factor):
    height, width, _ = premultiplied.shape
    return premultiplied.reshape(height // factor, factor, width // factor, factor, 4).mean(axis=(1, 3))


def write_imageset(folder, name, premultiplied_hi):
    imageset = os.path.join(folder, name + ".imageset")
    os.makedirs(imageset, exist_ok=True)
    for stale in os.listdir(imageset):
        if stale.endswith(".png"):
            os.remove(os.path.join(imageset, stale))
    entries = []
    for scale in sorted(SCALES):
        filename = f"{name}@{scale}x.png"
        write_png(os.path.join(imageset, filename), to_png_bytes(downsample(premultiplied_hi, SCALES[scale])))
        entries.append(f'    {{ "filename" : "{filename}", "idiom" : "universal", "scale" : "{scale}x" }}')
    contents = '{\n  "images" : [\n' + ",\n".join(entries) + '\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n'
    with open(os.path.join(imageset, "Contents.json"), "w") as handle:
        handle.write(contents)


# MARK: - Image operations (premultiplied linear RGBA, numpy)

def dilate(alpha, radius):
    """Max filter over a disc — the silhouette grown by `radius` pixels."""
    grown = alpha.copy()
    reach = int(math.ceil(radius))
    height, width = alpha.shape
    padded = np.pad(alpha, reach)
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            distance = math.hypot(dx, dy)
            if distance > radius + 0.5:
                continue
            weight = min(1.0, radius + 0.5 - distance)
            shifted = padded[reach + dy : reach + dy + height, reach + dx : reach + dx + width]
            grown = np.maximum(grown, shifted * weight)
    return grown


def outlined(image, radius, strength=0.92):
    """An ink edge around the figure (ART-DIRECTION §3): what separates a metal figure from the sand when
    their luminance is 1:1."""
    edge = dilate(image[..., 3], radius) * strength
    ink = np.array(linear((INK[0] << 16) | (INK[1] << 8) | INK[2]))
    under = np.zeros_like(image)
    under[..., :3] = ink * edge[..., None]
    under[..., 3] = edge
    return image + under * (1 - image[..., 3:4])


def dulled(image, amount=0.7, grey=0.25):
    """A knocked-over figure loses the lamp."""
    out = image.copy()
    luminance = (out[..., 0] * 0.2126 + out[..., 1] * 0.7152 + out[..., 2] * 0.0722)[..., None]
    out[..., :3] = (out[..., :3] * (1 - grey) + luminance * grey) * amount
    return out


def shadow_from(catcher, opacity):
    """The shadow catcher's alpha, recoloured to ink at the art direction's opacity."""
    alpha = np.clip(catcher[..., 3] * opacity, 0, 1)
    ink = np.array(linear((INK[0] << 16) | (INK[1] << 8) | INK[2]))
    out = np.zeros_like(catcher)
    out[..., :3] = ink * alpha[..., None]
    out[..., 3] = alpha
    return out


# MARK: - Scene

class Stage:
    def __init__(self, workdir):
        self.workdir = workdir
        self.counter = 0
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 96
        scene.cycles.use_adaptive_sampling = False
        scene.cycles.use_denoising = False
        scene.cycles.seed = 1799
        scene.cycles.max_bounces = 6
        scene.cycles.glossy_bounces = 3
        scene.cycles.sample_clamp_indirect = 4.0
        scene.cycles.pixel_filter_type = "BLACKMAN_HARRIS"
        scene.cycles.filter_width = 1.5
        scene.render.film_transparent = True
        scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = "OPEN_EXR"
        scene.render.image_settings.color_depth = "32"
        scene.render.image_settings.exr_codec = "ZIP"
        scene.view_settings.view_transform = "Standard"
        self.scene = scene
        self._camera()
        self._lamp()
        self.materials = Materials()
        self.catcher = self._catcher()

    def _camera(self):
        data = bpy.data.cameras.new("camera")
        data.type = "ORTHO"
        data.clip_start = 1
        data.clip_end = 400
        camera = bpy.data.objects.new("camera", data)
        camera.location = (0, 0, 200)
        self.scene.collection.objects.link(camera)
        self.scene.camera = camera
        self.camera = camera

    def frame(self, width, height, center=(0.0, 0.0)):
        self.scene.render.resolution_x = int(round(width * PIXELS_PER_POINT))
        self.scene.render.resolution_y = int(round(height * PIXELS_PER_POINT))
        self.camera.data.ortho_scale = max(width, height)
        self.camera.location = (center[0], center[1], 200)

    def _lamp(self):
        # One lamp straight above: a soft sun for the key light and its contact shadows, and a sky that
        # is bright at the zenith and dark at the horizon — so a surface's brightness depends only on how
        # much it faces up, which makes the highest parts (helmet, shield boss, horse's back) the brightest.
        sun_data = bpy.data.lights.new("lamp", type="SUN")
        sun_data.energy = 3.2
        sun_data.angle = math.radians(22)
        sun_data.color = (1.0, 0.95, 0.86)
        sun = bpy.data.objects.new("lamp", sun_data)
        self.scene.collection.objects.link(sun)

        world = bpy.data.worlds.new("room")
        self.scene.world = world
        nodes = world.node_tree.nodes
        links = world.node_tree.links
        nodes.clear()
        coordinates = nodes.new("ShaderNodeTexCoord")
        separate = nodes.new("ShaderNodeSeparateXYZ")
        clamp = nodes.new("ShaderNodeMath")
        clamp.operation = "MAXIMUM"
        clamp.inputs[1].default_value = 0.0
        power = nodes.new("ShaderNodeMath")
        power.operation = "POWER"
        # Not too sharp a falloff: a leaned shield is metal facing 30–40° off the zenith and must still
        # find some lamp in it, or it goes black.
        power.inputs[1].default_value = 1.6
        scale = nodes.new("ShaderNodeMath")
        scale.operation = "MULTIPLY_ADD"
        scale.inputs[1].default_value = 1.0
        scale.inputs[2].default_value = 0.05
        background = nodes.new("ShaderNodeBackground")
        background.inputs["Color"].default_value = (0.86, 0.9, 0.95, 1)
        output = nodes.new("ShaderNodeOutputWorld")
        links.new(coordinates.outputs["Generated"], separate.inputs[0])
        links.new(separate.outputs["Z"], clamp.inputs[0])
        links.new(clamp.outputs[0], power.inputs[0])
        links.new(power.outputs[0], scale.inputs[0])
        links.new(scale.outputs[0], background.inputs["Strength"])
        links.new(background.outputs[0], output.inputs["Surface"])

    def _catcher(self):
        mesh = bpy.data.meshes.new("table")
        builder = bmesh.new()
        bmesh.ops.create_grid(builder, x_segments=1, y_segments=1, size=120)
        builder.to_mesh(mesh)
        builder.free()
        table = bpy.data.objects.new("table", mesh)
        table.is_shadow_catcher = True
        table.hide_render = True
        self.scene.collection.objects.link(table)
        return table

    def clear_models(self):
        keep = {self.camera, self.catcher} | {obj for obj in self.scene.objects if obj.type == "LIGHT"}
        for obj in list(self.scene.objects):
            if obj not in keep:
                bpy.data.objects.remove(obj, do_unlink=True)
        for mesh in list(bpy.data.meshes):
            if mesh.users == 0:
                bpy.data.meshes.remove(mesh)

    def models(self):
        return [obj for obj in self.scene.objects if obj.type in {"MESH", "EMPTY"} and obj is not self.catcher]

    def render(self, shadow=False):
        """Renders the models (or, with `shadow`, only the shadow they cast on the table) and returns
        premultiplied linear RGBA, bottom row first."""
        meshes = [obj for obj in self.models() if obj.type == "MESH"]
        for obj in meshes:
            obj.visible_camera = not shadow
        self.catcher.hide_render = not shadow
        self.counter += 1
        path = os.path.join(self.workdir, f"render-{self.counter}.exr")
        self.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(path, check_existing=False)
        image.colorspace_settings.name = "Non-Color"
        width, height = image.size
        pixels = np.array(image.pixels[:], dtype=np.float64).reshape(height, width, 4)
        bpy.data.images.remove(image)
        os.remove(path)
        for obj in meshes:
            obj.visible_camera = True
        self.catcher.hide_render = True
        return pixels


# MARK: - Materials

class Materials:
    def __init__(self):
        self.brass = self._metal(
            "brass", colour=(0.62, 0.43, 0.17), roughness=0.34, patina=(0.08, 0.2, 0.15), patina_amount=1.0)
        self.iron = self._metal(
            "iron", colour=(0.2, 0.195, 0.19), roughness=0.58, patina=(0.05, 0.045, 0.04), patina_amount=0.7)
        # The top of a base is the cast "ground" the figure stands on: rough and darker, so the flat face
        # doesn't mirror the lamp and outshine the figure standing on it.
        self.brass_ground = self._metal(
            "brass-ground", colour=(0.3, 0.21, 0.09), roughness=0.78, patina=(0.06, 0.14, 0.1), patina_amount=1.0,
            grain_strength=0.5)
        self.iron_ground = self._metal(
            "iron-ground", colour=(0.1, 0.098, 0.095), roughness=0.85, patina=(0.04, 0.035, 0.03), patina_amount=0.7,
            grain_strength=0.5)
        self.polished = self._metal(
            "polished", colour=(0.8, 0.6, 0.27), roughness=0.22, patina=(0.08, 0.2, 0.15), patina_amount=0.0)
        self.groove = self._dielectric("groove", colour=linear(0x1A1C1A), roughness=0.9)
        self.wood = self._dielectric("wood", colour=(0.05, 0.04, 0.033), roughness=0.7)
        self.feather = self._dielectric("feather", colour=linear(0xD6D0C2), roughness=0.8)
        self.foliage = self._dielectric("foliage", colour=linear(0x29342D), roughness=0.9, variation=0.45)
        self.stone = self._dielectric("stone", colour=linear(0x4A4D49), roughness=0.8, variation=0.25)

    @staticmethod
    def _new(name):
        material = bpy.data.materials.new(name)
        tree = material.node_tree
        tree.nodes.clear()
        return material, tree.nodes, tree.links

    def _metal(self, name, colour, roughness, patina, patina_amount, grain_strength=0.08):
        # Cast metal: the recesses keep a patina (verdigris in brass, black scale in iron) — found with
        # ambient occlusion, broken up with noise so it doesn't read as a gradient.
        material, nodes, links = self._new(name)
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        output = nodes.new("ShaderNodeOutputMaterial")
        occlusion = nodes.new("ShaderNodeAmbientOcclusion")
        occlusion.samples = 16
        occlusion.inputs["Distance"].default_value = 1.6
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 0.45
        noise.inputs["Detail"].default_value = 6
        recess = nodes.new("ShaderNodeMapRange")
        recess.inputs["From Min"].default_value = 0.5
        recess.inputs["From Max"].default_value = 0.92
        recess.inputs["To Min"].default_value = patina_amount
        recess.inputs["To Max"].default_value = 0.0
        broken = nodes.new("ShaderNodeMath")
        broken.operation = "MULTIPLY"
        mask = nodes.new("ShaderNodeMath")
        mask.operation = "MULTIPLY"
        mask.inputs[1].default_value = 1.4
        mask.use_clamp = True
        colour_mix = nodes.new("ShaderNodeMix")
        colour_mix.data_type = "RGBA"
        colour_mix.inputs["A"].default_value = (*colour, 1)
        colour_mix.inputs["B"].default_value = (*patina, 1)
        metal_mix = nodes.new("ShaderNodeMapRange")
        metal_mix.inputs["To Min"].default_value = 1.0
        metal_mix.inputs["To Max"].default_value = 0.2
        rough_mix = nodes.new("ShaderNodeMapRange")
        rough_mix.inputs["To Min"].default_value = roughness
        rough_mix.inputs["To Max"].default_value = 0.85
        grain = nodes.new("ShaderNodeTexNoise")
        grain.inputs["Scale"].default_value = 3.0
        grain.inputs["Detail"].default_value = 4
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = grain_strength

        links.new(occlusion.outputs["AO"], recess.inputs["Value"])
        links.new(recess.outputs["Result"], broken.inputs[0])
        links.new(noise.outputs["Fac"], broken.inputs[1])
        links.new(broken.outputs[0], mask.inputs[0])
        links.new(mask.outputs[0], colour_mix.inputs["Factor"])
        links.new(mask.outputs[0], metal_mix.inputs["Value"])
        links.new(mask.outputs[0], rough_mix.inputs["Value"])
        links.new(colour_mix.outputs["Result"], shader.inputs["Base Color"])
        links.new(metal_mix.outputs["Result"], shader.inputs["Metallic"])
        links.new(rough_mix.outputs["Result"], shader.inputs["Roughness"])
        links.new(grain.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], shader.inputs["Normal"])
        links.new(shader.outputs[0], output.inputs["Surface"])
        return material

    def _dielectric(self, name, colour, roughness, variation=0.0):
        material, nodes, links = self._new(name)
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        shader.inputs["Roughness"].default_value = roughness
        output = nodes.new("ShaderNodeOutputMaterial")
        if variation > 0:
            noise = nodes.new("ShaderNodeTexNoise")
            noise.inputs["Scale"].default_value = 0.8
            noise.inputs["Detail"].default_value = 3
            shade = nodes.new("ShaderNodeMix")
            shade.data_type = "RGBA"
            shade.inputs["A"].default_value = (*(c * (1 - variation) for c in colour), 1)
            shade.inputs["B"].default_value = (*(min(1.0, c * (1 + variation)) for c in colour), 1)
            links.new(noise.outputs["Fac"], shade.inputs["Factor"])
            links.new(shade.outputs["Result"], shader.inputs["Base Color"])
        else:
            shader.inputs["Base Color"].default_value = (*colour, 1)
        links.new(shader.outputs[0], output.inputs["Surface"])
        return material


# MARK: - Primitives (all in points)

def _link(name, builder, material, smooth=True):
    mesh = bpy.data.meshes.new(name)
    if smooth:
        for face in builder.faces:
            face.smooth = True
    builder.to_mesh(mesh)
    builder.free()
    for each in material if isinstance(material, (list, tuple)) else [material]:
        mesh.materials.append(each)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def ellipsoid(material, center, radii, rotation=(0, 0, 0), segments=32):
    builder = bmesh.new()
    matrix = (
        Matrix.Translation(Vector(center))
        @ Matrix.Rotation(math.radians(rotation[2]), 4, "Z")
        @ Matrix.Rotation(math.radians(rotation[1]), 4, "Y")
        @ Matrix.Rotation(math.radians(rotation[0]), 4, "X")
        @ Matrix.Diagonal((*radii, 1))
    )
    bmesh.ops.create_uvsphere(builder, u_segments=segments, v_segments=segments // 2, radius=1, matrix=matrix)
    return _link("ellipsoid", builder, material)


def sphere(material, center, radius, segments=24):
    return ellipsoid(material, center, (radius, radius, radius), segments=segments)


def tube(material, points, radii, segments=14, caps=True):
    """A tube along a polyline, radius per point — spear shafts, bows, limbs, necks, tails."""
    points = [Vector(p) for p in points]
    if isinstance(radii, (int, float)):
        radii = [radii] * len(points)
    builder = bmesh.new()
    rings = []
    normal = None
    for index, point in enumerate(points):
        if index == 0:
            tangent = points[1] - points[0]
        elif index == len(points) - 1:
            tangent = points[-1] - points[-2]
        else:
            tangent = points[index + 1] - points[index - 1]
        tangent.normalize()
        if normal is None:
            reference = Vector((0, 0, 1)) if abs(tangent.z) < 0.9 else Vector((1, 0, 0))
            normal = tangent.cross(reference).normalized()
        else:
            normal = (normal - tangent * normal.dot(tangent)).normalized()
        binormal = tangent.cross(normal)
        ring = []
        for step in range(segments):
            angle = 2 * math.pi * step / segments
            offset = (normal * math.cos(angle) + binormal * math.sin(angle)) * radii[index]
            ring.append(builder.verts.new(point + offset))
        rings.append(ring)
    for first, second in zip(rings, rings[1:]):
        for step in range(segments):
            following = (step + 1) % segments
            builder.faces.new((first[step], first[following], second[following], second[step]))
    obj_faces = []
    if caps:
        obj_faces.append(builder.faces.new(list(reversed(rings[0]))))
        obj_faces.append(builder.faces.new(rings[-1]))
    for face in builder.faces:
        face.smooth = face not in obj_faces
    bmesh.ops.recalc_face_normals(builder, faces=builder.faces[:])
    return _link("tube", builder, material, smooth=False)


def arc_points(center, radius, start, end, z, steps=18):
    return [
        (
            center[0] + radius * math.cos(math.radians(start + (end - start) * step / steps)),
            center[1] + radius * math.sin(math.radians(start + (end - start) * step / steps)),
            z,
        )
        for step in range(steps + 1)
    ]


def cone(material, base, tip, radius, segments=16):
    base, tip = Vector(base), Vector(tip)
    axis = tip - base
    builder = bmesh.new()
    rotation = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    matrix = Matrix.Translation((base + tip) / 2) @ rotation
    bmesh.ops.create_cone(
        builder, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=0,
        depth=axis.length, matrix=matrix)
    return _link("cone", builder, material, smooth=False)


def plinth(material, ground, shape, radius=None, height=1.6):
    """The cast base (D24): round for the player, octagonal for the enemy, with a bevelled top edge
    that catches the lamp as a rim of the team's metal."""
    builder = bmesh.new()
    if shape == "round":
        radius = radius or 8.8
        segments, bevel_segments, bevel = 64, 3, 0.5
        rotation = Matrix.Identity(4)
    else:
        radius = radius or 9.6
        segments, bevel_segments, bevel = 8, 1, 0.55
        rotation = Matrix.Rotation(math.pi / 8, 4, "Z")
    bmesh.ops.create_cone(
        builder, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius, depth=height,
        matrix=Matrix.Translation((0, 0, height / 2)) @ rotation)
    top_edges = [edge for edge in builder.edges if all(vertex.co.z > height - 1e-4 for vertex in edge.verts)]
    bmesh.ops.bevel(
        builder, geom=top_edges, offset=bevel, segments=bevel_segments, profile=0.5, affect="EDGES")
    top = height - 1e-4
    for face in builder.faces:
        is_top = all(v.co.z >= top for v in face.verts)
        face.smooth = shape == "round" and abs(face.normal.z) < 0.999 and not is_top
        face.material_index = 1 if is_top else 0
    return _link("plinth", builder, [material, ground], smooth=False)


def curved_plate(material, axis_y, radius, span, height, lean, z0, thickness=0.9, steps=20):
    """A shield: a strip of a vertical cylinder around (0, axis_y), `span` degrees either side of +Y,
    leaned back by `lean` degrees about its bottom edge so the lamp and the camera see its face."""
    builder = bmesh.new()
    grid = []
    rows = 6
    for row in range(rows + 1):
        h = height * row / rows
        line = []
        for step in range(steps + 1):
            angle = math.radians(-span + 2 * span * step / steps)
            x = radius * math.sin(angle)
            y = axis_y + radius * math.cos(angle)
            # Lean the plate back toward the bearer: its top moves -Y as it rises.
            lean_r = math.radians(lean)
            outward = Vector((math.sin(angle), math.cos(angle), 0))
            point = Vector((x, y, z0)) - outward * (h * math.sin(lean_r)) + Vector((0, 0, h * math.cos(lean_r)))
            line.append(builder.verts.new(point))
        grid.append(line)
    for lower, upper in zip(grid, grid[1:]):
        for step in range(steps):
            builder.faces.new((lower[step], lower[step + 1], upper[step + 1], upper[step]))
    bmesh.ops.recalc_face_normals(builder, faces=builder.faces[:])
    grid = [[vertex.co.copy() for vertex in line] for line in grid]
    obj = _link("shield", builder, material)
    solidify = obj.modifiers.new("thickness", "SOLIDIFY")
    solidify.thickness = thickness
    solidify.offset = 0
    return obj, grid


# MARK: - Figures

class Figure:
    def __init__(self, material):
        self.m = material

    def soldier(self, y=0.0, width=12.5, armoured=True, crest=True, lean=0.0, crouch=1.0, turn=0.0,
                right_hand=None, left_hand=None, hood=False):
        """A foot soldier cast in one piece: legs, torso, pauldrons, helmet; arms reach the given hands."""
        m = self.m
        z = crouch
        spin = Matrix.Rotation(math.radians(turn), 3, "Z")

        def at(x, dy, height):
            return tuple(spin @ Vector((x, dy, 0)) + Vector((0, y + lean * height / 14, height * z)))

        for side in (-1, 1):
            tube(m, [at(side * 1.6, 0.2, 6.2), at(side * 1.9, side * 0.6 + 0.3, 1.6)], [1.3, 1.1])
        ellipsoid(m, at(0, 0, 7.2), (width * 0.3, 2.5, 4.0), rotation=(0, 0, turn))
        # From above a soldier is a broad oval of shoulders with the head a little forward of it; a head
        # on separate round pauldrons reads as three beads instead.
        ellipsoid(m, at(0, -0.2, 9.9), (width * 0.5, 3.0, 1.7), rotation=(0, 0, turn))
        shoulder = width / 2 - 1.4
        for side in (-1, 1):
            if armoured:
                ellipsoid(m, at(side * shoulder, -0.1, 10.4), (2.0, 2.7, 1.3), rotation=(0, side * 22, turn))
        head = at(0, 0.9, 12.2)
        if hood:
            ellipsoid(m, head, (2.2, 2.4, 2.2), rotation=(0, 0, turn))
            cone(m, at(0, -0.6, 12.8), at(0, -3.0, 11.0), 1.4)
        else:
            ellipsoid(m, head, (2.3, 2.5, 2.3), rotation=(0, 0, turn))
            cone(m, at(0, 0.9, 13.6), at(0, 0.9, 15.6), 1.3)
            if crest:
                ellipsoid(m, at(0, 0.2, 14.3), (0.55, 2.9, 0.9), rotation=(0, 0, turn))
        for side, hand in ((1, right_hand), (-1, left_hand)):
            if hand is None:
                hand = at(side * (shoulder + 0.4), 1.2, 6.8)
            elbow = Vector(at(side * (shoulder + 1.4), -0.4, 8.2)).lerp(Vector(hand), 0.35)
            tube(m, [at(side * shoulder, 0.1, 10.1), elbow, hand], [1.05, 0.95, 0.85])
            sphere(m, hand, 1.0)
        return at


def spearman(fig, pose):
    m = fig.m
    if pose == "strike":
        at = fig.soldier(y=0.8, lean=1.6, right_hand=(3.4, 6.2, 9.4), left_hand=(2.8, 10.4, 9.8))
        butt, tip = Vector((3.2, -5.5, 8.6)), Vector((3.2, 22.0, 10.6))
    elif pose == "brace":
        at = fig.soldier(y=-1.2, width=13.5, crouch=0.84, turn=-14, right_hand=(1.6, 1.2, 5.6),
                         left_hand=(1.4, 6.0, 6.8))
        butt, tip = Vector((1.2, -8.5, 1.8)), Vector((1.4, 21.5, 9.0))
    else:
        at = fig.soldier(right_hand=(3.6, 1.6, 8.6), left_hand=(3.0, 6.2, 10.2))
        butt, tip = Vector((3.4, -9.0, 7.4)), Vector((3.4, 19.5, 12.4))
    direction = (tip - butt).normalized()
    tube(m, [butt, tip - direction * 2.6], [0.62, 0.55])
    ellipsoid(m, tuple(tip - direction * 1.4), (0.95, 2.6, 0.45), rotation=(-math.degrees(math.asin(direction.z)), 0, 0))
    tube(m, [tip - direction * 3.0, tip - direction * 2.4], 0.8)


def archer(fig, pose):
    m = fig.m
    bow_z = 10.6
    # Wider than the base and ahead of it, so the "D" never merges with the base's rim.
    center, radius, start, end = (0.0, 2.8), 10.6, 20, 160
    grip = (center[0], center[1] + radius, bow_z)
    tips = [arc_points(center, radius, start, end, bow_z, 1)[index] for index in (0, 1)]
    if pose == "strike":
        draw = (0.4, 0.2, bow_z + 0.2)
    elif pose == "brace":
        draw = (0.3, 4.6, bow_z)
    else:
        draw = None
    fig.soldier(y=0.8, width=10.5, armoured=False, crest=False, hood=True,
                left_hand=grip, right_hand=draw or (2.9, 4.6, 9.4))
    # Quiver across the back, fletchings showing.
    tube(m, [(-2.8, -3.2, 5.0), (-3.9, -3.9, 12.6)], [1.35, 1.5])
    for offset in (-0.6, 0.1, 0.8):
        ellipsoid(m, (-3.9 + offset, -4.1 + offset * 0.3, 13.4), (0.35, 0.9, 0.5), rotation=(20, 0, 30))
    # The bow, canted flat so it reads as a "D" from above — the archer's whole identity.
    limb = arc_points(center, radius, start, end, bow_z, 20)
    radii = [0.55 + 0.5 * math.sin(math.pi * index / 20) for index in range(21)]
    tube(m, limb, radii)
    string_to = draw or tuple(Vector(tips[0]).lerp(Vector(tips[1]), 0.5))
    tube(m, [tips[0], string_to, tips[1]], 0.26, segments=6)
    if draw:
        shaft_end = (draw[0], grip[1] + 2.4, bow_z + 0.2)
        tube(m, [draw, shaft_end], 0.34, segments=8)
        cone(m, shaft_end, (draw[0], grip[1] + 4.4, bow_z + 0.2), 0.8)


def cavalry(fig, pose):
    m = fig.m
    reach = pose in {"strike", "brace"}
    stretch = 1.06 if pose == "brace" else 1.0
    # Horse: barrel, shoulders and hindquarters, neck and head reaching forward; the tail behind.
    ellipsoid(m, (0, 0.2, 8.6), (3.7, 8.2 * stretch, 3.3))
    ellipsoid(m, (0, 4.6 * stretch, 9.0), (3.9, 3.9, 3.4))
    ellipsoid(m, (0, -5.0 * stretch, 9.0), (4.2, 4.2, 3.4))
    neck_top = (0, 13.0, 13.2) if reach else (0, 11.4, 14.6)
    tube(m, [(0, 6.0 * stretch, 10.6), neck_top], [2.5, 1.7])
    tube(m, [(0, neck_top[1] - 1.0, neck_top[2] + 1.1), (0, neck_top[1] + 0.4, neck_top[2] + 0.9)], 0.7)
    muzzle = (0, neck_top[1] + 5.4, neck_top[2] - 2.2) if reach else (0, neck_top[1] + 5.0, neck_top[2] - 2.0)
    tube(m, [(0, neck_top[1] - 0.6, neck_top[2] + 0.6), muzzle], [1.8, 1.1])
    for side in (-1, 1):
        cone(m, (side * 0.8, neck_top[1] - 0.3, neck_top[2] + 1.6), (side * 1.0, neck_top[1] - 0.9, neck_top[2] + 3.0), 0.55)
    tube(m, [(0, -9.0 * stretch, 10.2), (0, -12.0 * stretch, 8.8), (0, -13.8 * stretch, 5.2)], [1.2, 0.9, 0.5])
    for side, forward in ((-1, 1), (1, 1), (-1, -1), (1, -1)):
        hip = (side * 1.8, forward * 5.0 * stretch, 7.2)
        foot_y = forward * (5.6 if pose != "brace" else 7.4) * stretch
        tube(m, [hip, (side * 1.8, foot_y, 1.6)], [1.1, 0.7])
    # Saddle cloth and a small rider — a circle on the horse's back, as the art direction asks.
    ellipsoid(m, (0, -0.6, 11.6), (4.0, 3.2, 0.6))
    rider_y = 0.6 if reach else -0.4
    lean = 1.2 if reach else 0.0
    ellipsoid(m, (0, rider_y, 14.2), (3.0, 2.0, 2.8))
    for side in (-1, 1):
        sphere(m, (side * 2.9, rider_y + 0.1 + lean * 0.3, 15.6), 1.4)
    ellipsoid(m, (0, rider_y + 0.5 + lean, 17.8), (2.1, 2.3, 2.0))
    ellipsoid(m, (0, rider_y + 0.3 + lean, 17.3), (2.6, 2.8, 0.4))
    ellipsoid(m, (0, rider_y + 0.1 + lean, 19.6), (0.45, 2.2, 0.6))
    # Lance: held high at rest, levelled past the horse's head to strike or charge.
    if reach:
        hand = (3.4, rider_y + 1.6, 14.6)
        butt, tip = Vector((3.6, -8.0, 15.2)), Vector((3.2, 21.5, 13.6))
    else:
        hand = (3.6, rider_y + 1.0, 14.8)
        butt, tip = Vector((4.4, -4.0, 9.6)), Vector((4.9, 9.5, 27.0))
    tube(m, [(2.9, rider_y + 0.1, 15.4), hand], [0.9, 0.8])
    sphere(m, hand, 0.9)
    direction = (tip - butt).normalized()
    tube(m, [butt, tip - direction * 2.0], 0.5)
    cone(m, tuple(tip - direction * 2.2), tuple(tip), 0.75)
    left = (-3.2, rider_y + 1.6, 13.6)
    tube(m, [(-2.9, rider_y + 0.1, 15.4), left], [0.9, 0.8])
    sphere(m, left, 0.9)


def shield_bearer(fig, pose):
    m = fig.m
    if pose == "strike":
        push, span, lean, radius, body_y = 2.4, 60, 54, 11.0, -2.6
    elif pose == "brace":
        push, span, lean, radius, body_y = 0.8, 74, 60, 12.0, -3.6
    else:
        push, span, lean, radius, body_y = 0.0, 60, 54, 11.0, -3.4
    # The widest figure (ART-DIRECTION §3): the shield spans past the base on both sides.
    axis_y = 10.2 + push - radius
    fig.soldier(y=body_y, width=13.0, lean=1.2 if pose == "strike" else 0.0, crouch=0.9 if pose == "brace" else 1.0,
                left_hand=(-3.0, body_y + 5.2 + push * 0.6, 7.2), right_hand=(5.8, body_y + 2.4, 8.4))
    plate, grid = curved_plate(m, axis_y=axis_y, radius=radius, span=span, height=12.0, lean=lean, z0=1.8)
    # Rim and boss: the parts of the shield that catch the lamp.
    tube(m, grid[-1], 0.6, segments=8)
    tube(m, [line[0] for line in grid], 0.55, segments=8)
    tube(m, [line[-1] for line in grid], 0.55, segments=8)
    middle = grid[len(grid) // 2][len(grid[0]) // 2]
    outward = Vector((0, 1, 0))
    lean_r = math.radians(lean)
    face_normal = Vector((0, math.cos(lean_r), math.sin(lean_r)))
    ellipsoid(m, tuple(middle + face_normal * 0.5), (2.2, 2.2, 1.3),
              rotation=(-math.degrees(math.atan2(face_normal.y, face_normal.z)), 0, 0))
    # A short blade over the shield's right edge.
    tube(m, [(6.0, body_y + 2.0, 8.6), (7.2, body_y + 9.0, 10.4)], [0.55, 0.3])
    tube(m, [(5.0, body_y + 3.1, 8.7), (7.0, body_y + 2.8, 8.9)], 0.4)


BUILDERS = {"mizrakci": spearman, "okcu": archer, "suvari": cavalry, "kalkan": shield_bearer}


def emblem(material, unit_type, shape):
    """The type cut into the back of the base — the small-size fallback the art direction asks for. Cut
    in, dark, rather than raised and lit: raised arcs beside the quiver read as a face."""
    z = 1.5
    y = -6.7 if shape == "round" else -7.0
    if unit_type == "mizrakci":
        tube(material, [(0, y - 1.3, z), (0, y + 1.3, z)], 0.24, segments=6)
    elif unit_type == "okcu":
        tube(material, [(-1.2, y - 0.8, z), (0, y + 0.8, z), (1.2, y - 0.8, z)], 0.24, segments=6)
    elif unit_type == "suvari":
        tube(material, arc_points((0, y - 0.3), 1.1, -20, 200, z, 10), 0.24, segments=6)
    else:
        tube(material, arc_points((0, y), 1.1, 0, 360, z, 16), 0.24, segments=6, caps=False)


def build_figure(stage, unit_type, material_name, shape, pose):
    material = getattr(stage.materials, material_name)
    plinth(material, getattr(stage.materials, material_name + "_ground"), shape)
    emblem(stage.materials.groove, unit_type, shape)
    BUILDERS[unit_type](Figure(material), "base" if pose == "fallen" else pose)
    if pose == "fallen":
        topple(stage)


def topple(stage):
    """Knocks the whole cast piece onto its side, rested on the table and centred on the cell."""
    pivot = bpy.data.objects.new("pivot", None)
    stage.scene.collection.objects.link(pivot)
    meshes = [obj for obj in stage.models() if obj.type == "MESH"]
    for obj in meshes:
        obj.parent = pivot
    pivot.rotation_euler = (math.radians(6), math.radians(-88), math.radians(-16))
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    corners = []
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        corners.extend(obj.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    low = min(corner.z for corner in corners)
    mid_x = (min(c.x for c in corners) + max(c.x for c in corners)) / 2
    mid_y = (min(c.y for c in corners) + max(c.y for c in corners)) / 2
    pivot.location = (-mid_x, -mid_y, -low)
    bpy.context.view_layer.update()


def selection_ring(stage):
    builder = bmesh.new()
    bmesh.ops.create_circle(builder, cap_ends=False, segments=96, radius=13)
    points = [tuple(vertex.co) for vertex in builder.verts]
    builder.free()
    points.append(points[0])
    tube(stage.materials.polished, [(x, y, 0.8) for x, y, _ in points], 0.75, segments=10, caps=False)


# MARK: - Effects and terrain

def arrow(stage):
    tube(stage.materials.wood, [(0, -7.2, 1.0), (0, 5.4, 1.0)], 0.32, segments=8)
    cone(stage.materials.iron, (0, 5.2, 1.0), (0, 8.2, 1.0), 0.85)
    for angle in (0, 120, 240):
        offset = Vector((math.cos(math.radians(angle)), 0, math.sin(math.radians(angle)))) * 0.55
        ellipsoid(stage.materials.feather, tuple(Vector((0, -6.0, 1.0)) + offset), (0.75, 1.6, 0.12),
                  rotation=(0, angle, 0))


def tree(stage, variant):
    """A model-railway tree seen from above: a dome of small foam clumps round a hidden trunk, the way
    a modeller builds one from lichen — lumpy enough to catch the lamp in dozens of small highlights."""
    material = stage.materials.foliage
    rng = np.random.default_rng(100 + variant)
    tube(stage.materials.wood, [(0, 0, 0), (0, 0, 6)], 0.8)
    crown = 5.6 + 0.5 * variant
    clumps = 34 + 6 * variant
    for index in range(clumps):
        # Spread over a squashed dome: denser and higher in the middle.
        angle = index * 2.39996 + rng.uniform(-0.2, 0.2)
        spread = math.sqrt((index + 0.5) / clumps) * crown
        height = 5.0 + 4.2 * math.sqrt(max(0.0, 1 - (spread / (crown + 0.6)) ** 2)) + rng.uniform(-0.5, 0.5)
        size = rng.uniform(1.1, 1.9)
        builder = bmesh.new()
        bmesh.ops.create_icosphere(
            builder, subdivisions=2, radius=1,
            matrix=Matrix.Translation((math.cos(angle) * spread, math.sin(angle) * spread, height))
            @ Matrix.Diagonal((size, size * rng.uniform(0.8, 1.0), size * 0.85, 1)))
        _link("clump", builder, material)


def stones(stage, variant):
    material = stage.materials.stone
    rng = np.random.default_rng(300 + variant)
    for _ in range(4 + variant):
        center = (rng.uniform(-4, 4), rng.uniform(-4, 4), 0.6)
        size = rng.uniform(0.9, 2.0)
        ellipsoid(material, center, (size, size * rng.uniform(0.6, 1.0), size * 0.55),
                  rotation=(0, 0, rng.uniform(0, 180)), segments=8)
    for obj in stage.models():
        if obj.type == "MESH":
            displace = obj.modifiers.new("chips", "DISPLACE")
            texture = bpy.data.textures.new(f"chips-{variant}", type="VORONOI")
            texture.noise_scale = 1.2
            displace.texture = texture
            displace.strength = 0.35


# MARK: - Contact sheet (the grey-scale legibility check, ART-DIRECTION §3)

def contact_sheet(figures, path, grey):
    sands = [linear(0x5E6A63), linear(0x7A8780), linear(0x2A302E)]
    names = [f"{unit_type}-{team}-{pose}" for unit_type in UNIT_TYPES for team in TEAMS for pose in POSES]
    cell = int(CANVAS * 3)
    rows = [names[index : index + len(POSES)] for index in range(0, len(names), len(POSES))]
    sheet = np.zeros((cell * len(rows), cell * len(POSES) * len(sands), 3))
    for band, sand in enumerate(sands):
        for row, row_names in enumerate(rows):
            for column, name in enumerate(row_names):
                image = downsample(figures[name], SCALES[3])
                x = (band * len(POSES) + column) * cell
                y = row * cell
                tile = np.flipud(image)
                sheet[y : y + cell, x : x + cell] = tile[..., :3] + np.array(sand) * (1 - tile[..., 3:4])
    if grey:
        luminance = sheet[..., 0] * 0.2126 + sheet[..., 1] * 0.7152 + sheet[..., 2] * 0.0722
        sheet = np.repeat(luminance[..., None], 3, axis=-1)
    alpha = np.ones(sheet.shape[:2] + (1,))
    write_png(path, np.round(np.concatenate([encode_srgb(sheet), alpha], axis=-1) * 255).astype(np.uint8))


# MARK: - Main

def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="figures.py")
    parser.add_argument("--atlas", required=True)
    parser.add_argument("--terrain")
    parser.add_argument("--contact-sheet")
    parser.add_argument("--only", help="render just this unit type (for iterating on one figure)")
    args = parser.parse_args(argv)

    os.makedirs(args.atlas, exist_ok=True)
    with open(os.path.join(args.atlas, "Contents.json"), "w") as handle:
        handle.write('{ "info" : { "author" : "xcode", "version" : 1 } }\n')
    workdir = tempfile.mkdtemp(prefix="ferman-figures-")
    stage = Stage(workdir)
    outline = 0.5 * PIXELS_PER_POINT
    figures = {}

    stage.frame(CANVAS, CANVAS)
    for unit_type in UNIT_TYPES:
        if args.only and unit_type != args.only:
            continue
        for material_name, shape in TEAMS.items():
            for pose in POSES:
                stage.clear_models()
                build_figure(stage, unit_type, material_name, shape, pose)
                image = stage.render()
                if pose == "fallen":
                    image = dulled(image)
                image = outlined(image, outline)
                name = f"{unit_type}-{material_name}-{pose}"
                figures[name] = image
                write_imageset(args.atlas, name, image)
                print(f"figure {name}", flush=True)
        for fallen in (False, True):
            stage.clear_models()
            build_figure(stage, unit_type, "brass", "round", "fallen" if fallen else "base")
            name = f"shadow-{unit_type}" + ("-fallen" if fallen else "")
            write_imageset(args.atlas, name, shadow_from(stage.render(shadow=True), opacity=0.62))
            print(f"shadow {name}", flush=True)

    if not args.only:
        stage.clear_models()
        selection_ring(stage)
        write_imageset(args.atlas, "ring-selection", outlined(stage.render(), outline))

        stage.frame(6, 18)
        stage.clear_models()
        arrow(stage)
        write_imageset(args.atlas, "arrow", outlined(stage.render(), 0.3 * PIXELS_PER_POINT, strength=0.6))
        write_imageset(args.atlas, "shadow-arrow", shadow_from(stage.render(shadow=True), opacity=0.4))
        print("arrow", flush=True)

    if args.terrain:
        os.makedirs(args.terrain, exist_ok=True)
        folder_contents = os.path.join(args.terrain, "Contents.json")
        with open(folder_contents, "w") as handle:
            handle.write('{\n  "info" : { "author" : "xcode", "version" : 1 },\n  "properties" : { "provides-namespace" : false }\n}\n')
        stage.frame(24, 24)
        for variant in range(4):
            stage.clear_models()
            tree(stage, variant)
            image = stage.render()
            shade = stage.render(shadow=True)
            write_imageset(args.terrain, f"terrain-tree-{variant}", outlined(image, 0.35 * PIXELS_PER_POINT, 0.5))
            write_imageset(args.terrain, f"terrain-tree-{variant}-shadow", shadow_from(shade, opacity=0.55))
            print(f"tree {variant}", flush=True)
        stage.frame(12, 12)
        for variant in range(3):
            stage.clear_models()
            stones(stage, variant)
            image = outlined(stage.render(), 0.3 * PIXELS_PER_POINT, 0.5)
            shade = shadow_from(stage.render(shadow=True), opacity=0.5)
            write_imageset(args.terrain, f"terrain-stones-{variant}", image + shade * (1 - image[..., 3:4]))
            print(f"stones {variant}", flush=True)

    if args.contact_sheet and not args.only:
        contact_sheet(figures, args.contact_sheet, grey=False)
        root, extension = os.path.splitext(args.contact_sheet)
        contact_sheet(figures, root + "-grey" + extension, grey=True)
        print(f"contact sheets {args.contact_sheet}", flush=True)
    os.rmdir(workdir)


main()
