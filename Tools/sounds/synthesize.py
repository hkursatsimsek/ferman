# FERMAN's sound set (ART-DIRECTION §7): every sound synthesised from scratch — decaying resonances for
# metal and wood, a plucked string for the bow, shaped noise for sand and paper. No recordings, no samples,
# nothing to license.
#
#     python3 Tools/sounds/synthesize.py App/Ferman/Sounds
#
# Needs numpy and nothing else. Blender's bundled Python has it, so the pinned figure tool can run it too:
#
#     blender --background --factory-startup --python Tools/sounds/synthesize.py -- App/Ferman/Sounds
#
# Noise comes from a counter hashed with SplitMix64, not numpy's generators, and WAVs are written with the
# standard library, so a run writes the same bytes on any machine with the same numpy.
#
# The figures are miniatures on a table, so the sounds are too: small cast metal, a wooden table top,
# sand, paper and ink. "Close your eyes and still understand" — every order the player wrote has its own
# sound, and nothing sounds like a video game UI.
#
# A phone speaker gives almost nothing below ~250 Hz, so a thump is never just a low sine: it carries a
# body resonance in the few-hundred-hertz range, which is also what something small on a table sounds like.

import math
import os
import sys
import wave

import numpy as np

RATE = 44_100
AMBIENT_RATE = 22_050


# MARK: - Building blocks

def seconds(duration, rate=RATE):
    return np.arange(int(round(duration * rate))) / rate


def noise(count, seed):
    """Uniform noise in [-1, 1): SplitMix64 over a counter — the same on every run and platform."""
    value = np.arange(count, dtype=np.uint64) + np.uint64((seed * 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF)
    value = (value ^ (value >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
    value = (value ^ (value >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
    value = value ^ (value >> np.uint64(31))
    return (value >> np.uint64(11)).astype(np.float64) / float(1 << 53) * 2 - 1


def unit_random(seed, index):
    return (noise(index + 1, seed)[index] + 1) / 2


def shaped(signal, gain, rate=RATE):
    """Filters by multiplying the spectrum with `gain(frequencies)`; zero-padded so a one-shot's tail
    doesn't wrap round onto its start."""
    count = len(signal)
    padded = np.concatenate([signal, np.zeros(count)])
    spectrum = np.fft.rfft(padded)
    frequencies = np.fft.rfftfreq(len(padded), 1 / rate)
    return np.fft.irfft(spectrum * gain(frequencies), len(padded))[:count]


def band(low, high, slope=2.0):
    """A soft band-pass response: flat between `low` and `high`, rolling off at `slope` octaves per decade-ish."""
    def gain(frequencies):
        f = np.maximum(frequencies, 1.0)
        below = 1 / (1 + (low / f) ** (2 * slope)) if low > 0 else 1
        above = 1 / (1 + (f / high) ** (2 * slope)) if high else 1
        return np.sqrt(below * above)
    return gain


def decay(t, tau, attack=0.0015):
    """Linear attack, exponential decay — the envelope of anything struck."""
    rise = np.clip(t / attack, 0, 1) if attack > 0 else 1
    return rise * np.exp(-t / tau)


def modes(t, frequencies, taus, amplitudes, seed=0):
    """A struck resonant body: a sum of decaying sine modes. Metal has inharmonic, long-ringing modes;
    wood has few, low and damped ones."""
    out = np.zeros_like(t)
    for index, (frequency, tau, amplitude) in enumerate(zip(frequencies, taus, amplitudes)):
        phase = unit_random(seed, index) * 2 * math.pi
        out += amplitude * np.sin(2 * math.pi * frequency * t + phase) * decay(t, tau, attack=0.0008)
    return out


def glide_sine(t, start, end, glide, tau):
    """A sine whose pitch falls from `start` to `end` over `glide` seconds — a drum skin or a thump."""
    frequency = end + (start - end) * np.exp(-t / glide)
    phase = 2 * math.pi * np.cumsum(frequency) / RATE
    return np.sin(phase) * decay(t, tau)


def click(t, seed, low, high, tau):
    return shaped(noise(len(t), seed), band(low, high)) * decay(t, tau, attack=0.0002)


def place(target, sound, at, gain=1.0, rate=RATE):
    start = int(round(at * rate))
    end = min(len(target), start + len(sound))
    target[start:end] += sound[: end - start] * gain
    return target


def pluck(frequency, duration, seed, damping=0.996):
    """Karplus–Strong: a noise burst circulating in a delay line, averaged on each pass — a string."""
    period = max(2, int(round(RATE / frequency)))
    line = noise(period, seed)
    out = np.zeros(int(duration * RATE))
    for index in range(len(out)):
        position = index % period
        following = (index + 1) % period
        out[index] = line[position]
        line[position] = damping * 0.5 * (line[position] + line[following])
    return out


def grains(duration, density, seed, tau=0.0025, rate=RATE):
    """Sand: a scatter of tiny impulses, each ringing out for a couple of milliseconds."""
    count = int(duration * rate)
    chance = (noise(count, seed) + 1) / 2
    amplitude = (noise(count, seed + 1) + 1) / 2
    impulses = np.where(chance < density / rate, amplitude, 0.0)
    kernel = np.exp(-np.arange(int(tau * 6 * rate)) / (tau * rate))
    return np.convolve(impulses, kernel)[:count]


def finish(sound, peak_db, fade=0.01, rate=RATE):
    """Removes DC, eases in over a millisecond and fades the tail to silence (no clicks at either end),
    and normalises the peak."""
    sound = sound - np.mean(sound)
    head = min(len(sound), int(0.001 * rate))
    sound[:head] *= np.linspace(0, 1, head)
    tail = min(len(sound), int(fade * rate))
    if tail > 0:
        sound[-tail:] *= np.linspace(1, 0, tail) ** 2
    peak = np.max(np.abs(sound))
    if peak > 0:
        sound = sound / peak * 10 ** (peak_db / 20)
    return sound


def write(folder, name, sound, rate=RATE):
    samples = np.clip(np.round(sound * 32767), -32768, 32767).astype("<i2")
    with wave.open(os.path.join(folder, name + ".wav"), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(samples.tobytes())


# MARK: - Paper and ink (the interface)

def order_tick(variant):
    """Kâğıt tık — the player's order taking effect: a crisp paper flick with a second, softer flex."""
    t = seconds(0.07)
    seed = 100 + variant
    body = click(t, seed, 2400, 9000, 0.0016) + 0.35 * modes(t, [3150 + 120 * variant], [0.009], [1.0], seed)
    flex = click(t, seed + 7, 3000, 10000, 0.0012)
    return finish(place(body, flex, 0.011 + 0.002 * variant, 0.4), -10)


def paper_settle():
    """A card settling after a reorder: a short rustle over a soft slide."""
    t = seconds(0.2)
    rustle = shaped(noise(len(t), 11), band(1500, 7000)) * shaped(grains(0.2, 260, 12, 0.004), band(0, 60))
    slide = shaped(noise(len(t), 13), band(300, 900))
    envelope = np.clip(t / 0.012, 0, 1) * np.exp(-t / 0.07)
    return finish((rustle * 2.2 + 0.25 * slide) * envelope, -12)


def slip():
    """A paper slip slapped onto the table: the result card, a new order."""
    t = seconds(0.26)
    slap = shaped(noise(len(t), 21), band(250, 6000)) * decay(t, 0.02, 0.001)
    thump = glide_sine(t, 260, 170, 0.02, 0.035)
    rustle = shaped(noise(len(t), 22), band(2000, 7000)) * np.exp(-((t - 0.05) / 0.04) ** 2) * 0.25
    return finish(slap + 0.6 * thump + rustle, -8)


def stamp():
    """Mühür vuruşu: a seal pressed down on a slip — a thump into the table, the paper crushing, and the
    tacky lift of inked stone."""
    t = seconds(0.42)
    thump = glide_sine(t, 125, 60, 0.035, 0.06)
    table = modes(t, [230, 470, 760, 1240], [0.045, 0.03, 0.018, 0.01], [1.0, 0.55, 0.3, 0.15], 31)
    crush = shaped(noise(len(t), 32), band(700, 4200)) * decay(t, 0.02)
    lift = np.zeros_like(t)
    place(lift, click(seconds(0.05), 33, 3000, 8000, 0.008), 0.15)
    return finish(0.5 * thump + table + 0.7 * crush + 0.22 * lift, -5)


def dial():
    """A notch of the parameter dial: a tiny ratchet click, wood on brass."""
    t = seconds(0.04)
    return finish(click(t, 61, 2500, 9000, 0.0009) + 0.5 * modes(t, [4200], [0.004], [1.0], 62), -14)


def victory():
    """Hat tutuldu — one strike on a small brass bowl: calm, not a fanfare (brief §7's officer's tone)."""
    t = seconds(1.4)
    base = 660
    ring = modes(t, [base, base * 2.71, base * 5.04], [0.8, 0.4, 0.2], [1.0, 0.35, 0.12], 71)
    ring += 0.4 * modes(t, [base + 1.1, base * 2.71 + 1.7], [0.75, 0.35], [1.0, 0.35], 72)
    mallet = click(t, 73, 400, 3000, 0.004)
    return finish(ring * np.clip(t / 0.003, 0, 1) + 0.3 * mallet, -9, fade=0.3)


def defeat():
    """Cephe yarıldı — one dull knock on the table, a cast figure's base laid down on its side."""
    t = seconds(0.7)
    knock = modes(t, [196, 412, 690], [0.16, 0.07, 0.03], [1.0, 0.45, 0.2], 81)
    thud = 0.6 * glide_sine(t, 140, 98, 0.03, 0.12)
    felt = shaped(noise(len(t), 82), band(150, 1200)) * decay(t, 0.02)
    return finish(knock + thud + 0.4 * felt, -8, fade=0.2)


def place_figure(variant):
    """A cast figure set down on the table: a metal clink, a small thunk, one tiny bounce."""
    t = seconds(0.32)
    base = 2350 + 180 * variant
    clink = modes(t, [base, base * 1.58, base * 2.37, base * 3.21], [0.12, 0.08, 0.05, 0.03], [1, 0.6, 0.35, 0.2], 40 + variant)
    thunk = glide_sine(t, 320, 260, 0.01, 0.025) + 0.5 * click(t, 41 + variant, 200, 2000, 0.008)
    one = 0.5 * clink + thunk
    return finish(place(one.copy(), one * 0.3, 0.034 + 0.004 * variant), -7)


# MARK: - Orders (the player's program at work)

def drum():
    """İlerle — a drum with a sheet of paper on its skin: "dum-dum", muffled, marching."""
    t = seconds(0.32)
    # A small drum: the skin's fundamental and its first membrane modes (1.59, 2.14, 2.30 x), gliding
    # down as the struck skin relaxes, the paper damping everything above.
    skin = (
        0.5 * glide_sine(t, 150, 105, 0.05, 0.1)
        + glide_sine(t, 330, 238, 0.05, 0.085)
        + 0.55 * glide_sine(t, 520, 378, 0.04, 0.05)
        + 0.3 * glide_sine(t, 705, 510, 0.04, 0.035)
    )
    slap = shaped(noise(len(t), 51), band(200, 2000)) * decay(t, 0.012)
    paper = shaped(noise(len(t), 52), band(2000, 5500)) * decay(t, 0.03) * 0.2
    beat = shaped(skin + 0.5 * slap, band(0, 1500)) + paper
    total = np.zeros(int(0.58 * RATE))
    place(total, beat, 0.0, 0.72)
    place(total, beat, 0.2, 1.0)
    return finish(total, -6)


def sand(duration, seed, bright_from, bright_to, dark_from, dark_to, density=900):
    t = seconds(duration)
    texture = grains(duration, density, seed, 0.002)
    bright = shaped(noise(len(t), seed + 1), band(1400, 3200)) * texture
    dark = shaped(noise(len(t), seed + 2), band(350, 1300)) * texture
    progress = t / duration
    return bright * (bright_from + (bright_to - bright_from) * progress) + dark * (dark_from + (dark_to - dark_from) * progress)


def scrape():
    """Geri çekil — a base dragged back through the sand, receding as it goes."""
    t = seconds(0.44)
    body = sand(0.44, 61, 1.0, 0.15, 0.6, 0.9)
    envelope = np.clip(t / 0.06, 0, 1) * np.clip((0.44 - t) / 0.18, 0, 1)
    return finish(body * envelope, -8)


def swish():
    """Kanat — a quick sweep of sand to one side (the runtime pans it left or right)."""
    t = seconds(0.26)
    body = sand(0.26, 71, 0.5, 1.2, 0.8, 0.2, density=1400)
    envelope = np.sin(np.pi * np.clip(t / 0.26, 0, 1)) ** 1.5
    return finish(body * envelope, -9)


def wood(t, frequency, seed, tau=0.06):
    return modes(t, [frequency, frequency * 2.1, frequency * 3.7], [tau, tau / 2, tau / 4], [1, 0.45, 0.2], seed) + 0.3 * click(
        t, seed + 1, 800, 5000, 0.003)


def knock():
    """Mevzini koru — one low wooden knock on the table: "tok"."""
    t = seconds(0.25)
    return finish(wood(t, 410, 81) + 0.5 * glide_sine(t, 150, 120, 0.01, 0.03), -8)


def point():
    """Hedefe odaklan — a pointer tapping the table twice, the second firmer: "tak-TAK"."""
    t = seconds(0.2)
    tap = wood(t, 760, 91, tau=0.035)
    total = np.zeros(int(0.3 * RATE))
    place(total, tap, 0.0, 0.6)
    place(total, tap, 0.085, 1.0)
    return finish(total, -9)


def pebble(seed, tau=0.006):
    t = seconds(0.05)
    frequency = 2900 + 1400 * unit_random(seed, 0)
    return modes(t, [frequency, frequency * 1.7], [tau, tau * 0.6], [1, 0.5], seed) + 0.4 * click(t, seed + 3, 1500, 8000, 0.002)


def gather():
    """Toplan — pebbles drawn together, faster and faster, then set down."""
    total = np.zeros(int(0.36 * RATE))
    for index, at in enumerate([0.0, 0.07, 0.125, 0.165, 0.195, 0.215, 0.23]):
        place(total, pebble(110 + index), at, 0.45 + 0.08 * index)
    place(total, wood(seconds(0.12), 520, 118, tau=0.04), 0.25, 0.7)
    return finish(total, -10)


def scatter():
    """Dağıl — pebbles flung apart: a spray of sand, then clicks spreading and thinning out."""
    total = np.zeros(int(0.5 * RATE))
    place(total, sand(0.08, 121, 1.0, 0.3, 0.4, 0.2, density=2500) * np.linspace(1, 0, int(0.08 * RATE)), 0.0, 0.8)
    at = 0.02
    for index in range(9):
        place(total, pebble(130 + index), at, 0.9 - 0.08 * index)
        at += 0.018 + 0.012 * index
    return finish(total, -9)


def shield(t, base, seed, length=1.0):
    ratios = [1.0, 1.47, 2.09, 2.56, 3.39, 4.23]
    taus = [0.9 * length, 0.7 * length, 0.5 * length, 0.4 * length, 0.3 * length, 0.2 * length]
    amplitudes = [1.0, 0.7, 0.55, 0.4, 0.3, 0.2]
    ring = modes(t, [base * r for r in ratios], taus, amplitudes, seed)
    # A slightly detuned twin of each mode beats against it: the shimmer of a thin plate.
    ring += 0.35 * modes(t, [base * r + 0.7 for r in ratios], taus, amplitudes, seed + 1)
    strike = click(t, seed + 2, 2000, 9000, 0.004)
    return ring + 0.6 * strike


def take_cover():
    """Siper al — a shield brought up and struck: a bright ring over a short plate shimmer."""
    t = seconds(1.1)
    return finish(shield(t, 520, 141, 0.8), -9, fade=0.2)


def bell():
    """Komutanı koru — a small brass hand bell: the commander's."""
    t = seconds(1.3)
    base = 1480
    ratios = [0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 2.662]
    taus = [1.1, 0.8, 0.6, 0.5, 0.35, 0.25, 0.2]
    amplitudes = [0.25, 1.0, 0.5, 0.35, 0.4, 0.2, 0.15]
    ring = modes(t, [base * r for r in ratios], taus, amplitudes, 151)
    mallet = np.clip(t / 0.004, 0, 1)
    return finish(ring * mallet, -12, fade=0.25)


# MARK: - Combat

def release(variant):
    """Yay bırakma — the string's twang, the thwack against the bracer, the arrow leaving."""
    duration = 0.34
    t = seconds(duration)
    seed = 160 + variant
    string = pluck(172 + 14 * variant, duration, seed, damping=0.993)
    string = shaped(string, band(90, 2500)) * decay(t, 0.09, 0.001)
    thwack = click(t, seed + 5, 900, 4000, 0.005)
    whoosh = shaped(noise(len(t), seed + 6), band(1500, 4200)) * np.exp(-((t - 0.1) / 0.06) ** 2) * 0.35
    return finish(string + 0.5 * thwack + whoosh, -8)


def land(variant):
    """Ok iniyor — a dull thunk into sand or wood, the shaft quivering after it."""
    t = seconds(0.22)
    seed = 170 + variant
    thud = shaped(noise(len(t), seed), band(150, 2400)) * decay(t, 0.01) + 0.4 * glide_sine(t, 170, 130, 0.01, 0.03)
    shaft = modes(t, [560 + 40 * variant, 1180 + 70 * variant], [0.03, 0.018], [0.6, 0.3], seed + 2)
    quiver_frequency = 880 + 60 * variant + 25 * np.sin(2 * math.pi * 38 * t)
    quiver = np.sin(2 * math.pi * np.cumsum(quiver_frequency) / RATE) * decay(t, 0.045) * 0.3
    return finish(thud + shaft + quiver, -10)


def hit(variant):
    """Vuruş — cast metal against cast metal, over the wood of the table."""
    t = seconds(0.26)
    seed = 180 + variant
    base = 1700 + 210 * variant
    metal = modes(t, [base, base * 1.62, base * 2.41, base * 3.3], [0.15, 0.1, 0.07, 0.04], [1, 0.6, 0.4, 0.25], seed)
    wood_body = wood(t, 280 + 30 * variant, seed + 4, tau=0.03)
    transient = click(t, seed + 8, 1000, 9000, 0.003)
    mix = [0.55, 0.4, 0.65, 0.5][variant % 4]
    return finish(mix * metal + (1 - mix) * wood_body + 0.5 * transient, -5)


def fall(variant):
    """Figür devrildi — a miniature tipping over: a rock on its base, the clink of it landing, two small
    bounces and a roll."""
    seed = 190 + variant
    total = np.zeros(int(0.36 * RATE))
    rock = shaped(noise(int(0.03 * RATE), seed), band(150, 900)) * np.linspace(0.2, 1, int(0.03 * RATE))
    place(total, rock, 0.0, 0.3)
    t = seconds(0.2)
    base = 2600 + 150 * variant
    impact = modes(t, [base, base * 1.53, base * 2.2], [0.06, 0.04, 0.025], [1, 0.5, 0.3], seed + 1) + glide_sine(
        t, 240, 190, 0.01, 0.02)
    place(total, impact, 0.03, 1.0)
    place(total, impact, 0.1 + 0.005 * variant, 0.55)
    place(total, impact, 0.145 + 0.006 * variant, 0.28)
    for index, at in enumerate([0.17, 0.195, 0.215]):
        place(total, pebble(seed + 10 + index, 0.004), at, 0.18)
    return finish(total, -7)


def rout():
    """Moral çöktü — a figure trembling on the table, rattling against it."""
    total = np.zeros(int(0.4 * RATE))
    at = 0.0
    index = 0
    while at < 0.33:
        rattle = pebble(200 + index, 0.004) * 0.6 + 0.4 * glide_sine(seconds(0.05), 210, 180, 0.005, 0.01)
        place(total, rattle, at, math.sin(math.pi * at / 0.33) ** 0.7 + 0.1)
        at += 0.024 + 0.006 * unit_random(201, index)
        index += 1
    return finish(total, -11)


def spear_wall():
    """Kirpi duvarı — spears lowered as one: wooden shafts clacking, their tips ticking."""
    total = np.zeros(int(0.42 * RATE))
    for index, at in enumerate([0.0, 0.045, 0.085, 0.14]):
        t = seconds(0.2)
        shaft = wood(t, 330 + 25 * index, 210 + index, tau=0.05)
        tip = modes(t, [3800 + 200 * index], [0.02], [0.35], 220 + index)
        place(total, shaft + tip, at, 1.0 - 0.12 * index)
    return finish(total, -7)


def shield_wall():
    """Kalkan duvarı — shields planted together: two rings and a thud into the ground."""
    t = seconds(1.3)
    total = shield(t, 440, 231, 0.9)
    place(total, shield(t, 468, 235, 0.8), 0.08, 0.8)
    total += 0.5 * glide_sine(t, 110, 80, 0.02, 0.05) + 0.6 * modes(t, [260, 540], [0.04, 0.02], [1, 0.4], 237)
    return finish(total, -8, fade=0.25)


def gallop():
    """Hücum — hooves on the table, getting closer."""
    total = np.zeros(int(0.72 * RATE))
    for index, at in enumerate([0.0, 0.09, 0.17, 0.33, 0.42, 0.5]):
        t = seconds(0.12)
        # A hoof is a clop — a hollow knock — more than a boom.
        clop = modes(t, [620 + 30 * (index % 3), 1310 + 50 * (index % 2)], [0.025, 0.012], [1.0, 0.4], 240 + index)
        hoof = clop + 0.5 * glide_sine(t, 160, 110, 0.015, 0.03) + 0.5 * shaped(
            noise(len(t), 250 + index), band(200, 1800)) * decay(t, 0.008)
        place(total, hoof, at, 0.5 + 0.1 * index)
    return finish(total, -6)


# MARK: - The room

def ambience():
    """The war room at night: a low room tone, a faint lamp hiss, a clock in another room, and wind
    outside rising and falling.
    Filtered in the frequency domain over the whole buffer and modulated only by periods that divide its
    length, so the loop has no seam."""
    duration = 16.0
    count = int(duration * AMBIENT_RATE)
    t = np.arange(count) / AMBIENT_RATE
    frequencies = np.fft.rfftfreq(count, 1 / AMBIENT_RATE)

    def circular(seed, gain):
        return np.fft.irfft(np.fft.rfft(noise(count, seed)) * gain(np.maximum(frequencies, 1.0)), count)

    room = circular(301, lambda f: (1 / f) * band(25, 380)(f))
    room /= np.max(np.abs(room))
    hiss = circular(302, band(3500, 9000))
    hiss /= np.max(np.abs(hiss))
    wind = circular(303, band(160, 620, slope=1.5))
    wind /= np.max(np.abs(wind))
    swell = 0.55 + 0.25 * np.sin(2 * math.pi * t / duration) + 0.2 * np.sin(2 * math.pi * 3 * t / duration + 1.3)
    swell = np.clip(swell, 0, None) ** 2
    # A clock somewhere in the house: tick and tock a second apart, heard through a wall.
    clock = np.zeros(count)
    for second in range(int(duration)):
        stroke_length = int(0.06 * AMBIENT_RATE)
        stroke_t = np.arange(stroke_length) / AMBIENT_RATE
        pitch = 1850 if second % 2 == 0 else 1580
        stroke = np.sin(2 * math.pi * pitch * stroke_t) * np.exp(-stroke_t / 0.008)
        stroke += 0.5 * np.sin(2 * math.pi * pitch * 2.3 * stroke_t) * np.exp(-stroke_t / 0.004)
        start = int(second * AMBIENT_RATE)
        clock[start : start + stroke_length] += stroke
    clock = np.fft.irfft(np.fft.rfft(clock) * band(600, 2600)(np.maximum(frequencies, 1.0)), count)
    clock /= np.max(np.abs(clock))
    mix = 0.55 * room + 0.035 * hiss + 0.4 * wind * swell + 0.1 * clock
    return mix / np.max(np.abs(mix)) * 10 ** (-14 / 20)


# MARK: - Main

def main():
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    if len(arguments) != 1:
        sys.stderr.write("usage: synthesize.py <App/Ferman/Sounds>\n")
        sys.exit(64)
    folder = arguments[0]
    os.makedirs(folder, exist_ok=True)

    sounds = {
        "stamp": stamp(),
        "paper": paper_settle(),
        "slip": slip(),
        "dial": dial(),
        "result-victory": victory(),
        "result-defeat": defeat(),
        "action-advance": drum(),
        "action-retreat": scrape(),
        "action-flank": swish(),
        "action-hold": knock(),
        "action-focus": point(),
        "action-regroup": gather(),
        "action-scatter": scatter(),
        "action-cover": take_cover(),
        "action-guard": bell(),
        "ability-spear-wall": spear_wall(),
        "ability-shield-wall": shield_wall(),
        "ability-charge": gallop(),
        "rout": rout(),
    }
    for variant in range(3):
        sounds[f"order-{variant + 1}"] = order_tick(variant)
        sounds[f"release-{variant + 1}"] = release(variant)
        sounds[f"land-{variant + 1}"] = land(variant)
        sounds[f"fall-{variant + 1}"] = fall(variant)
    for variant in range(2):
        sounds[f"place-{variant + 1}"] = place_figure(variant)
    for variant in range(4):
        sounds[f"hit-{variant + 1}"] = hit(variant)

    for stale in os.listdir(folder):
        if stale.endswith(".wav"):
            os.remove(os.path.join(folder, stale))
    for name in sorted(sounds):
        write(folder, name, sounds[name])
    write(folder, "ambience", ambience(), rate=AMBIENT_RATE)
    print(f"wrote {len(sounds) + 1} sounds to {folder}")


main()
