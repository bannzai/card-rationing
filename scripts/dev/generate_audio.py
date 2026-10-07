#!/usr/bin/env python3
"""BGM と効果音の素材 (assets/audio/) を合成して書き出す。

外部の素材・音源を使わず、波形 (正弦波の重ね合わせ・はじいた弦の模擬・ノイズ) を足し合わせて作る。乱数は固定の
seed で作るため、同じスクリプトからは同じ波形になる。効果音は WAV、BGM は Ogg Vorbis (ffmpeg の libvorbis で
エンコードする) で書き出す。書き出した素材は assets/CREDITS.md に記録する。

実行方法 (リポジトリのルートで): python3 scripts/dev/generate_audio.py
必要なもの: Python 3 (標準ライブラリだけ) と、libvorbis を有効にした ffmpeg。全素材の合成に 1〜2 分かかる
"""

import math
import random
import struct
import subprocess
import sys
import wave
from pathlib import Path

# 書き出し先
OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "audio"
# サンプリング周波数 (Hz)。音楽 CD と同じ値で、鐘の高い倍音 (基音の 9 倍弱。D6 で約 10 kHz) まで収まる
RATE = 44100
# 書き出す波形の最大振幅 (1.0 = 16 bit の最大値)。効果音は、ほかの音と重ねて鳴らしても割れにくいよう上限から
# 少し下げた 0.85。BGM はそれより約 5 dB 小さい 0.5 にして、回数の増減を知らせる効果音が BGM に埋もれないように
# する (設定の音量は BGM・効果音とも同じ既定値のため、釣り合いは素材の側で取る)
SE_PEAK = 0.85
BGM_PEAK = 0.5
# BGM の Ogg Vorbis の品質 (ffmpeg の -q:a。0〜10)。44100 Hz モノラルで 1 曲 300 KB 前後に収まる値
OGG_QUALITY = "4"
# 正弦波の 1 周期ぶんの位相 (ラジアン)
TWO_PI = 2.0 * math.pi
# 音名 → ハ (C) からの半音の数
PITCH_CLASSES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
# 鐘の倍音 (基音に対する周波数の比, 音量, 減衰の速さの比)。整数倍からずれた倍音が金属の響きになる
BELL_PARTIALS = [(1.0, 1.0, 1.0), (2.0, 0.6, 0.8), (2.76, 0.4, 0.55), (5.4, 0.25, 0.35), (8.93, 0.1, 0.2)]
# 残響 (Schroeder の方式) の、並列のくし形フィルタ (遅延の秒, 戻す量) と直列の全域通過フィルタ (遅延の秒, 係数)
REVERB_COMBS = [(0.0297, 0.80), (0.0371, 0.78), (0.0411, 0.76), (0.0437, 0.74)]
REVERB_ALLPASSES = [(0.005, 0.7), (0.0017, 0.7)]


def freq(name):
    """音名 (「D5」「F#4」「Bb3」。A4 = 440 Hz) の周波数 (Hz)"""
    octave = int(name[-1])
    semitone = PITCH_CLASSES[name[0]] + name[1:-1].count("#") - name[1:-1].count("b")
    return 440.0 * 2.0 ** ((12 * (octave + 1) + semitone - 69) / 12.0)


def mix(buf, start, samples, gain, wrap=False):
    """buf の start (秒) から samples を gain 倍して足す。wrap なら buf の末尾を越えた分を先頭に足す
    (繰り返しの継ぎ目で音が途切れないようにする)"""
    first = int(start * RATE)
    size = len(buf)
    for i, value in enumerate(samples):
        index = first + i
        if index >= size:
            if not wrap:
                break
            index %= size
        buf[index] += value * gain


def sines(partials, length, attack=0.005, decay=0.0, release=0.05, glide=0.0, tremolo=0.0):
    """正弦波の重ね合わせ。partials は (周波数, 音量, 減衰の速さの比) の並びで、length (秒) の音を返す。
    attack (秒) で立ち上がり、decay (秒。0 なら減衰しない) × 比 で指数的に減衰し、最後の release (秒) で消える。
    glide は 1 秒あたりに周波数が下がる割合、tremolo は音量を揺らす周波数 (Hz。0 なら揺らさない)。
    attack と release の既定値は、音の頭と終わりで波形が跳んで雑音 (クリック) にならない程度の短さ。ほかの既定値は
    「かけない」(減衰しない・周波数を変えない・揺らさない)"""
    count = int(length * RATE)
    out = [0.0] * count
    for partial_freq, volume, decay_ratio in partials:
        phase = 0.0
        step = TWO_PI * partial_freq / RATE
        partial_decay = decay * decay_ratio
        for i in range(count):
            t = i / RATE
            env = volume
            if t < attack:
                env *= t / attack
            if partial_decay > 0.0:
                env *= math.exp(-t / partial_decay)
            if t > length - release:
                env *= max(0.0, (length - t) / release)
            if tremolo > 0.0:
                env *= 0.75 + 0.25 * math.sin(TWO_PI * tremolo * t)
            out[i] += math.sin(phase) * env
            phase += step * (1.0 - glide * t)
    return out


def bell(note_freq, length, decay, glide=0.0):
    """鐘 (契約の印の音)。decay (秒) で減衰する"""
    partials = [(note_freq * ratio, volume, speed) for ratio, volume, speed in BELL_PARTIALS]
    return sines(partials, length, attack=0.002, decay=decay, release=0.03, glide=glide)


def pad(note_freq, length, edge, tremolo=0.0):
    """わずかにずらした正弦波を重ねた、ゆっくり立ち上がる持続音。edge (秒) で立ち上がり、同じ長さで消える"""
    partials = [(note_freq * 0.997, 0.5, 1.0), (note_freq * 1.003, 0.5, 1.0), (note_freq * 2.0, 0.2, 1.0)]
    return sines(partials, length, attack=edge, release=edge, tremolo=tremolo)


def bass(note_freq, length):
    """低音。倍音を少し足した正弦波が、鳴らしてすぐ弱まる"""
    partials = [(note_freq, 1.0, 1.0), (note_freq * 2.0, 0.35, 0.6), (note_freq * 3.0, 0.12, 0.4)]
    return sines(partials, length, attack=0.008, decay=length * 0.9, release=0.03)


def pluck(note_freq, length, rng, brightness):
    """はじいた弦 (Karplus-Strong 法)。1 周期ぶんの雑音を、隣と平均しながら繰り返し読んで減衰させる。
    brightness (0〜1) が低いほど、はじいた瞬間の雑音をなまらせて柔らかい音にする"""
    period = max(2, int(round(RATE / note_freq)))
    ring = [rng.uniform(-1.0, 1.0) for _ in range(period)]
    low = 0.0
    for i in range(period):
        low += (ring[i] - low) * brightness
        ring[i] = low
    mean = sum(ring) / period
    top = max(abs(value - mean) for value in ring) or 1.0
    ring = [(value - mean) / top for value in ring]
    count = int(length * RATE)
    out = [0.0] * count
    position = 0
    for i in range(count):
        value = ring[position]
        out[i] = value
        following = position + 1
        if following == period:
            following = 0
        ring[position] = 0.498 * (value + ring[following])
        position = following
    fade = min(count, int(0.03 * RATE))
    for i in range(fade):
        out[count - 1 - i] *= i / fade
    return out


def drum(length, start_freq, end_freq, sweep, decay, noise, rng):
    """太鼓。start_freq から end_freq (Hz) へ sweep (秒) で下がる正弦波と、なまらせた雑音 (noise 倍) が
    decay (秒) で減衰する"""
    count = int(length * RATE)
    out = [0.0] * count
    phase = 0.0
    low = 0.0
    for i in range(count):
        t = i / RATE
        phase += TWO_PI * (end_freq + (start_freq - end_freq) * math.exp(-t / sweep)) / RATE
        low += (rng.uniform(-1.0, 1.0) - low) * 0.3
        out[i] = (math.sin(phase) + low * noise) * math.exp(-t / decay) * min(1.0, t / 0.002)
    return out


def hiss(length, decay, rng, tone, attack=0.002):
    """雑音。tone (0〜1) が低いほど高い音を削る。attack (秒) で立ち上がり、decay (秒) で減衰して、最後の 0.01 秒で消える。
    attack の既定値は、音の頭で波形が跳んで雑音 (クリック) にならない程度の短さ"""
    count = int(length * RATE)
    out = [0.0] * count
    low = 0.0
    for i in range(count):
        t = i / RATE
        low += (rng.uniform(-1.0, 1.0) - low) * tone
        out[i] = low * math.exp(-t / decay) * min(1.0, t / attack, (length - t) / 0.01)
    return out


def reverb(buf, wet):
    """buf に残響を足した波形。buf を繰り返す音 (BGM) として扱い、末尾の残響が先頭へ回り込むようにする
    (フィルタに 1 周ぶんを先に流してから、2 周目の出力を使う)"""
    size = len(buf)
    combed = [0.0] * size
    for delay, feedback in REVERB_COMBS:
        line = [0.0] * int(delay * RATE)
        position = 0
        for lap in range(2):
            for i in range(size):
                echoed = line[position]
                line[position] = buf[i] + echoed * feedback
                position += 1
                if position == len(line):
                    position = 0
                if lap == 1:
                    combed[i] += echoed
    for delay, gain in REVERB_ALLPASSES:
        line = [0.0] * int(delay * RATE)
        position = 0
        passed = [0.0] * size
        for lap in range(2):
            for i in range(size):
                value = combed[i]
                echoed = line[position] - gain * value
                line[position] = value + gain * echoed
                position += 1
                if position == len(line):
                    position = 0
                if lap == 1:
                    passed[i] = echoed
        combed = passed
    scale = wet / len(REVERB_COMBS)
    return [dry + echoed * scale for dry, echoed in zip(buf, combed)]


def normalized(buf, peak):
    """最大振幅が peak になるよう揃えた buf (無音の buf はそのまま返す)"""
    # 無音の時に 0 で割らないよう、最大振幅が 0 なら 1.0 として扱う
    top = max(abs(value) for value in buf) or 1.0
    return [value * peak / top for value in buf]


def pcm16(buf):
    """-1〜1 の値の並びを 16 bit のリトルエンディアンの PCM にする"""
    return struct.pack("<%dh" % len(buf), *(int(max(-1.0, min(1.0, value)) * 32767) for value in buf))


def write_wav(path, buf):
    """buf を 16 bit モノラルの WAV にして path に書き出す"""
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm16(normalized(buf, SE_PEAK)))


def write_ogg(path, buf):
    """ffmpeg で Ogg Vorbis にエンコードする。エンコーダの版などのメタデータは書かない"""
    subprocess.run(
        [
            "ffmpeg", "-loglevel", "error", "-y",
            "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "pipe:0",
            "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
            "-c:a", "libvorbis", "-q:a", OGG_QUALITY, str(path),
        ],
        input=pcm16(normalized(buf, BGM_PEAK)),
        check=True,
    )


# 効果音。回数の増減を知らせる 4 つ (使う・最後の 1 回・契約切れ・回復) は同じ鐘の音色で作り、回数が減る音は
# 下がる音型、戻る音は上がる音型にして、聞き分けられるようにする


def se_card_use():
    """カードを使う (残りが 2 回以上ある): 紙をめくるような短い雑音と、鐘を 1 つ"""
    rng = random.Random(1)
    buf = [0.0] * int(0.4 * RATE)
    mix(buf, 0.0, hiss(0.12, 0.03, rng, 0.35), 0.5)
    mix(buf, 0.01, bell(freq("D5"), 0.38, 0.12), 0.5)
    return buf


def se_last_one():
    """最後の 1 回 (使った後の残りが 1 回): 鐘が 2 つ、5 度下がる"""
    buf = [0.0] * int(0.8 * RATE)
    mix(buf, 0.0, bell(freq("A5"), 0.5, 0.2), 0.5)
    mix(buf, 0.14, bell(freq("D5"), 0.66, 0.28), 0.6)
    mix(buf, 0.14, sines([(freq("D3"), 1.0, 1.0)], 0.6, attack=0.02, decay=0.25), 0.25)
    return buf


def se_expired():
    """契約切れ (使った後の残りが 0 回): 低い太鼓と、印が焼け落ちる雑音、音程が下がっていく鐘"""
    rng = random.Random(3)
    buf = [0.0] * int(1.1 * RATE)
    mix(buf, 0.0, drum(0.4, 150.0, 50.0, 0.04, 0.14, 0.3, rng), 0.7)
    mix(buf, 0.02, hiss(0.7, 0.2, rng, 0.12, attack=0.03), 0.5)
    mix(buf, 0.0, bell(freq("D5"), 0.5, 0.16), 0.4)
    mix(buf, 0.16, bell(freq("G#4"), 0.9, 0.3, glide=0.22), 0.55)
    return buf


def se_restore():
    """回数の回復: 鐘が 4 つ、明るい和音を駆け上がる (印がもう一度灯る)"""
    buf = [0.0] * int(1.2 * RATE)
    for index, name in enumerate(["D5", "F#5", "A5", "D6"]):
        start = index * 0.09
        mix(buf, start, bell(freq(name), 1.2 - start, 0.4), 0.4)
    mix(buf, 0.27, sines([(freq("D7"), 1.0, 1.0)], 0.8, attack=0.05, decay=0.3), 0.06)
    return buf


def se_hit():
    """被弾: 短い雑音と、低く下がる打撃音"""
    rng = random.Random(5)
    buf = [0.0] * int(0.4 * RATE)
    mix(buf, 0.0, hiss(0.2, 0.04, rng, 0.25), 0.7)
    mix(buf, 0.0, drum(0.38, 200.0, 60.0, 0.05, 0.1, 0.0, rng), 0.9)
    return buf


def se_win():
    """勝利: はじいた弦が明るい和音を駆け上がり、鐘の和音が残る"""
    rng = random.Random(6)
    buf = [0.0] * int(1.6 * RATE)
    for index, name in enumerate(["D4", "A4", "D5", "F#5", "A5"]):
        mix(buf, index * 0.07, pluck(freq(name), 1.0, rng, 0.6), 0.4)
    for name in ["D5", "F#5", "A5"]:
        mix(buf, 0.36, bell(freq(name), 1.2, 0.5), 0.3)
    return buf


def se_lose():
    """敗北: 鐘がゆっくり下がり、低い持続音が消えていく"""
    buf = [0.0] * int(2.0 * RATE)
    for index, name in enumerate(["D5", "C5", "A4", "F4"]):
        start = index * 0.3
        mix(buf, start, bell(freq(name), 2.0 - start, 0.5), 0.4)
    for name in ["D2", "A2"]:
        mix(buf, 0.0, sines([(freq(name), 1.0, 1.0)], 2.0, attack=0.3, decay=0.9, release=0.4), 0.35)
    return buf


# BGM の定義。tempo は 1 分の拍の数で、1 小節は 4 拍 (8 分音符 8 つ)。chords は 1 小節ごとの和音 (先頭が根音)、
# melody は小節ごとの旋律で (8 分音符の位置, 音名, 8 分音符いくつ分の長さ) の並び。arp は和音を 8 分音符で
# 分散して鳴らす弦で (和音の何番目の音か, 何オクターブ上か) の並び (None は休み)、bass は根音から何半音上を
# 鳴らすかの並び (None は休み)。drums は太鼓の種類ごとの 8 分音符の位置。pad_octave は持続音を和音の何オクターブ上で
# 鳴らすか。*_gain は各パートの音量 (低音と太鼓に旋律が埋もれないよう、帯域ごとの平均音量を ffmpeg で測って決めた)
BGMS = {
    # 地図: ニ調のドリア旋法のゆっくりした曲。持続音の上で弦が和音を分散し、鐘が旋律を鳴らす (夕暮れの祠の道)
    "bgm_map": {
        "tempo": 66,
        "seed": 10,
        "chords": [
            ["D3", "F3", "A3"], ["A2", "C3", "E3"], ["F2", "A2", "C3"], ["C3", "E3", "G3"],
            ["D3", "F3", "A3"], ["G2", "B2", "D3"], ["E3", "G3", "B3"], ["A2", "C3", "E3"],
        ],
        "melody": [
            [(0, "A4", 3), (4, "D5", 2), (6, "F5", 2)],
            [(0, "E5", 4), (4, "C5", 2), (6, "A4", 2)],
            [(0, "A4", 2), (2, "C5", 2), (4, "F5", 4)],
            [(0, "E5", 3), (3, "D5", 1), (4, "C5", 4)],
            [(0, "D5", 2), (2, "F5", 2), (4, "A5", 4)],
            [(0, "G5", 3), (3, "F5", 1), (4, "D5", 2), (6, "B4", 2)],
            [(0, "E5", 4), (4, "G5", 2), (6, "E5", 2)],
            [(0, "C5", 2), (2, "B4", 2), (4, "A4", 4)],
        ],
        "lead": "bell",
        "lead_gain": 0.26,
        "arp": [(0, 1), (2, 1), (0, 2), (1, 2), (2, 1), (1, 2), (0, 2), (2, 1)],
        "arp_gain": 0.16,
        "arp_brightness": 0.35,
        "bass": [0, None, None, None, None, None, 7, None],
        "bass_steps": 5,
        "bass_gain": 0.28,
        "pad_gain": 0.09,
        "pad_octave": 1,
        "tremolo": 0.0,
        "drums": {"low": [], "high": [], "tick": []},
        "drum_gain": 0.0,
        "reverb": 0.45,
    },
    # 戦闘: ホ短調の速い曲。3 + 3 + 2 の拍で打つ太鼓と、刻む低音の上で、はじいた弦が旋律を弾く
    "bgm_battle": {
        "tempo": 126,
        "seed": 20,
        "chords": [
            ["E3", "G3", "B3"], ["E3", "G3", "B3"], ["C3", "E3", "G3"], ["D3", "F#3", "A3"],
            ["E3", "G3", "B3"], ["E3", "G3", "B3"], ["C3", "E3", "G3"], ["B2", "D#3", "F#3"],
            ["A2", "C3", "E3"], ["E3", "G3", "B3"], ["C3", "E3", "G3"], ["D3", "F#3", "A3"],
            ["A2", "C3", "E3"], ["E3", "G3", "B3"], ["B2", "D#3", "F#3"], ["B2", "D#3", "F#3"],
        ],
        "melody": [
            [(0, "E5", 2), (2, "G5", 1), (3, "F#5", 1), (4, "E5", 2), (6, "B4", 2)],
            [(0, "E5", 1), (1, "F#5", 1), (2, "G5", 2), (4, "B5", 3), (7, "A5", 1)],
            [(0, "G5", 2), (2, "E5", 2), (4, "C5", 2), (6, "E5", 2)],
            [(0, "F#5", 2), (2, "D5", 2), (4, "A5", 4)],
            [(0, "B5", 2), (2, "A5", 1), (3, "G5", 1), (4, "F#5", 2), (6, "E5", 2)],
            [(0, "G5", 3), (3, "F#5", 1), (4, "E5", 4)],
            [(0, "E5", 2), (2, "G5", 2), (4, "C6", 2), (6, "B5", 2)],
            [(0, "B5", 2), (2, "A5", 2), (4, "F#5", 2), (6, "D#5", 2)],
            [(0, "A5", 3), (3, "C6", 1), (4, "B5", 2), (6, "A5", 2)],
            [(0, "G5", 2), (2, "B5", 2), (4, "E5", 4)],
            [(0, "C5", 2), (2, "E5", 2), (4, "G5", 2), (6, "E5", 2)],
            [(0, "D5", 2), (2, "F#5", 2), (4, "A5", 2), (6, "F#5", 2)],
            [(0, "E5", 2), (2, "A5", 2), (4, "C6", 3), (7, "B5", 1)],
            [(0, "B5", 4), (4, "G5", 2), (6, "E5", 2)],
            [(0, "F#5", 2), (2, "B5", 2), (4, "D#5", 2), (6, "F#5", 2)],
            [(0, "B4", 2), (2, "D#5", 2), (4, "F#5", 2), (6, "B5", 2)],
        ],
        "lead": "pluck",
        "lead_gain": 0.45,
        "arp": [(0, 1), None, (1, 1), (2, 1), None, (1, 1), (2, 1), None],
        "arp_gain": 0.18,
        "arp_brightness": 0.5,
        "bass": [0, 0, 12, 0, 0, 12, 0, 7],
        "bass_steps": 0.9,
        "bass_gain": 0.2,
        "pad_gain": 0.07,
        "pad_octave": 1,
        "tremolo": 0.0,
        "drums": {"low": [0, 3, 6], "high": [2, 5], "tick": [1, 4, 7]},
        "drum_gain": 0.65,
        "reverb": 0.25,
    },
    # ボス: ハ短調の重い曲。揺れる持続音と大きな太鼓の上で、鐘が旋律を鳴らす (2 度下げた和音で不穏にする)
    "bgm_boss": {
        "tempo": 96,
        "seed": 30,
        "chords": [
            ["C3", "Eb3", "G3"], ["C3", "Eb3", "G3"], ["Ab2", "C3", "Eb3"], ["G2", "B2", "D3"],
            ["C3", "Eb3", "G3"], ["C3", "Eb3", "G3"], ["Db3", "F3", "Ab3"], ["G2", "B2", "D3"],
            ["F2", "Ab2", "C3"], ["C3", "Eb3", "G3"], ["Ab2", "C3", "Eb3"], ["G2", "B2", "D3"],
            ["F2", "Ab2", "C3"], ["Db3", "F3", "Ab3"], ["G2", "B2", "D3"], ["G2", "B2", "D3"],
        ],
        "melody": [
            [(0, "C5", 4), (4, "Eb5", 2), (6, "D5", 2)],
            [(0, "C5", 2), (2, "G4", 2), (4, "C5", 4)],
            [(0, "Ab4", 2), (2, "C5", 2), (4, "Eb5", 4)],
            [(0, "D5", 3), (3, "B4", 1), (4, "G4", 4)],
            [(0, "G5", 4), (4, "F5", 2), (6, "Eb5", 2)],
            [(0, "D5", 2), (2, "Eb5", 2), (4, "C5", 4)],
            [(0, "Db5", 2), (2, "F5", 2), (4, "Ab5", 2), (6, "F5", 2)],
            [(0, "G5", 4), (4, "D5", 2), (6, "B4", 2)],
            [(0, "F5", 3), (3, "Ab5", 1), (4, "G5", 2), (6, "F5", 2)],
            [(0, "Eb5", 2), (2, "G5", 2), (4, "C5", 4)],
            [(0, "Ab5", 2), (2, "G5", 2), (4, "Eb5", 2), (6, "C5", 2)],
            [(0, "B4", 2), (2, "D5", 2), (4, "G5", 4)],
            [(0, "F5", 2), (2, "Ab5", 2), (4, "C6", 4)],
            [(0, "Db6", 3), (3, "Ab5", 1), (4, "F5", 4)],
            [(0, "G5", 2), (2, "B5", 2), (4, "D6", 4)],
            [(0, "D6", 2), (2, "B5", 2), (4, "G5", 2), (6, "D5", 2)],
        ],
        "lead": "bell",
        "lead_gain": 0.3,
        "arp": [(0, 1), (2, 1), None, (1, 1), (2, 1), None, (0, 2), (2, 1)],
        "arp_gain": 0.11,
        "arp_brightness": 0.3,
        "bass": [0, 0, 7, 0, 0, 7, 0, 12],
        "bass_steps": 0.9,
        "bass_gain": 0.3,
        "pad_gain": 0.1,
        "pad_octave": 0,
        "tremolo": 5.5,
        "drums": {"low": [0, 5], "high": [3, 6, 7], "tick": []},
        "drum_gain": 1.0,
        "reverb": 0.4,
    },
}


def bgm(spec):
    """spec (BGMS の値) の BGM を chords の小節の数だけ作る。末尾を越えた音は先頭に足し、残響も先頭へ回り込ませて、
    繰り返しの継ぎ目で途切れないようにする"""
    rng = random.Random(spec["seed"])
    step = 30.0 / spec["tempo"]
    bar = step * 8
    buf = [0.0] * int(round(bar * len(spec["chords"]) * RATE))
    edge = bar * 0.15
    for index, chord in enumerate(spec["chords"]):
        start = index * bar
        for name in chord:
            # 前後の小節と edge だけ重ね、和音が入れ替わる所で持続音を途切れさせない
            note = pad(freq(name) * 2.0 ** spec["pad_octave"], bar + edge, edge, spec["tremolo"])
            mix(buf, start, note, spec["pad_gain"], wrap=True)
        for position, offset in enumerate(spec["bass"]):
            if offset is None:
                continue
            note = bass(freq(chord[0]) * 2.0 ** (offset / 12.0 - 1.0), step * spec["bass_steps"])
            mix(buf, start + position * step, note, spec["bass_gain"], wrap=True)
        for position, tone in enumerate(spec["arp"]):
            if tone is None:
                continue
            note = pluck(freq(chord[tone[0]]) * 2.0 ** tone[1], step * 3, rng, spec["arp_brightness"])
            mix(buf, start + position * step, note, spec["arp_gain"], wrap=True)
        for position, name, steps in spec["melody"][index]:
            if spec["lead"] == "bell":
                note = bell(freq(name), step * steps + 0.6, 0.25 + step * steps * 0.5)
            else:
                note = pluck(freq(name), step * steps + 0.3, rng, 0.7)
            mix(buf, start + position * step, note, spec["lead_gain"], wrap=True)
        drums = spec["drums"]
        drum_gain = spec["drum_gain"]
        for position in drums["low"]:
            hit = drum(0.35, 110.0, 45.0, 0.03, 0.11, 0.25, rng)
            mix(buf, start + position * step, hit, 0.55 * drum_gain, wrap=True)
        for position in drums["high"]:
            hit = drum(0.2, 240.0, 130.0, 0.02, 0.06, 0.5, rng)
            mix(buf, start + position * step, hit, 0.22 * drum_gain, wrap=True)
        for position in drums["tick"]:
            mix(buf, start + position * step, hiss(0.05, 0.012, rng, 0.9), 0.05 * drum_gain, wrap=True)
    return reverb(buf, spec["reverb"])


def main():
    """全素材を OUT_DIR に書き出す。同じ名前の素材は上書きする"""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    effects = [
        ("se_card_use", se_card_use), ("se_last_one", se_last_one), ("se_expired", se_expired),
        ("se_restore", se_restore), ("se_hit", se_hit), ("se_win", se_win), ("se_lose", se_lose),
    ]
    for name, make in effects:
        write_wav(OUT_DIR / f"{name}.wav", make())
    for name, spec in BGMS.items():
        write_ogg(OUT_DIR / f"{name}.ogg", bgm(spec))
    return 0


if __name__ == "__main__":
    sys.exit(main())
