from __future__ import annotations

import json
import math
import struct
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "generated"
FFMPEG = Path(r"C:\Users\fsyyy\AppData\Roaming\bilibili\ffmpeg\ffmpeg.exe")

SAMPLE_RATE = 13000
OUTPUT_RATE = 48828.125
BANK_WORDS = 8192
BANK_NIBBLES = BANK_WORDS * 4

ERHU_DIR = ROOT / "erhu" / "aliexpress-erhu-main" / "Samples" / "sus"
GUZHENG_DIR = ROOT / "guzheng" / "XSXB-Band-Samples-main" / "samples" / "guzheng"

ERHU = [
    (60, ERHU_DIR / "erhu_c6_sus_rr1.wav"),
    (64, ERHU_DIR / "erhu_e6_sus_rr1.wav"),
    (67, ERHU_DIR / "erhu_g6_sus_rr1.wav"),
    (69, ERHU_DIR / "erhu_a6_sus_rr1.wav"),
]

GUZHENG = [
    (60, GUZHENG_DIR / "guzheng-60-v1-rr1.flac"),
    (67, GUZHENG_DIR / "guzheng-67-v1-rr1.flac"),
    (74, GUZHENG_DIR / "guzheng-74-v1-rr1.flac"),
    (79, GUZHENG_DIR / "guzheng-79-v1-rr1.flac"),
]

STEP_TABLE = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
    143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
    494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411,
    1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026,
    4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
    11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623,
    27086, 29794, 32767,
]
INDEX_DELTA = (-1, -1, -1, -1, 2, 4, 6, 8)


def decode_audio(path: Path) -> list[int]:
    command = [
        str(FFMPEG),
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(path),
        "-af",
        "highpass=f=45,lowpass=f=6200",
        "-ar",
        str(SAMPLE_RATE),
        "-ac",
        "1",
        "-f",
        "s16le",
        "-acodec",
        "pcm_s16le",
        "-",
    ]
    raw = subprocess.check_output(command)
    return list(struct.unpack("<{}h".format(len(raw) // 2), raw))


def prepare(samples: list[int]) -> tuple[list[int], dict]:
    peak = max((abs(value) for value in samples), default=1)
    threshold = max(24, int(peak * 0.006))
    first = next((i for i, value in enumerate(samples) if abs(value) >= threshold), 0)
    first = max(0, first - SAMPLE_RATE // 100)
    samples = samples[first:first + BANK_NIBBLES]

    peak = max((abs(value) for value in samples), default=1)
    scale = 30000.0 / peak if peak else 0.0
    samples = [max(-32768, min(32767, int(round(value * scale)))) for value in samples]
    return samples, {
        "leading_trim_samples": first,
        "source_peak_normalized": peak,
        "encoded_samples": len(samples),
    }


def window_stats(samples: list[int], start: int, length: int) -> tuple[float, float, list[int]]:
    window = samples[start:start + length]
    energy = float(sum(value * value for value in window))
    return energy, math.sqrt(energy / max(1, len(window))), window


def sparse_correlation(
    samples: list[int], first: int, second: int, width: int, stride: int
) -> tuple[float, float]:
    a = samples[first:first + width:stride]
    b = samples[second:second + width:stride]
    energy_a = float(sum(value * value for value in a))
    energy_b = float(sum(value * value for value in b))
    if not energy_a or not energy_b:
        return 0.0, 0.0
    dot = sum(x * y for x, y in zip(a, b))
    correlation = dot / math.sqrt(energy_a * energy_b)
    rms_a = math.sqrt(energy_a / len(a))
    rms_b = math.sqrt(energy_b / len(b))
    amplitude_match = min(rms_a, rms_b) / max(rms_a, rms_b, 1.0)
    return correlation, amplitude_match


def choose_loop(samples: list[int]) -> dict:
    width = 1600
    min_end = min(len(samples) - 1, int(0.80 * SAMPLE_RATE))
    max_end = min(len(samples) - 1, int(1.80 * SAMPLE_RATE))
    min_loop = min(6000, max(2500, len(samples) // 4))
    max_loop = min(11000, max_end - 2500)
    global_rms = math.sqrt(sum(value * value for value in samples) / max(1, len(samples)))

    candidates = []
    for loop_end in range(min_end, max_end + 1, 64):
        if loop_end - width < 0:
            continue
        _, end_rms, _ = window_stats(samples, loop_end - width, width)
        if end_rms < global_rms * 0.22:
            continue
        for loop_length in range(min_loop, max_loop + 1, 16):
            loop_start = loop_end - loop_length
            if loop_start - width < 0:
                continue
            correlation, amplitude_match = sparse_correlation(
                samples, loop_start - width, loop_end - width, width, 8
            )
            score = correlation * amplitude_match
            candidates.append((score, loop_end, loop_start, loop_length))

    candidates.sort(reverse=True)
    best = None
    for _, coarse_end, coarse_start, _ in candidates[:12]:
        coarse_length = coarse_end - coarse_start
        for loop_end in range(max(min_end, coarse_end - 64), min(max_end, coarse_end + 64) + 1):
            if loop_end - width < 0:
                continue
            for loop_length in range(
                max(min_loop, coarse_length - 64),
                min(max_loop, coarse_length + 64) + 1,
            ):
                loop_start = loop_end - loop_length
                if loop_start - width < 0:
                    continue
                correlation, amplitude_match = sparse_correlation(
                    samples, loop_start - width, loop_end - width, width, 2
                )
                length_penalty = min(1.0, loop_length / 8000.0)
                score = correlation * amplitude_match * length_penalty
                if best is None or score > best["score"]:
                    best = {
                        "score": score,
                        "correlation": correlation,
                        "amplitude_match": amplitude_match,
                        "loop_end": loop_end,
                        "loop_start": loop_start,
                        "loop_length": loop_length,
                    }

    if best is None:
        loop_start = min(len(samples) - 4000, int(0.55 * SAMPLE_RATE))
        loop_end = min(len(samples) - 1, loop_start + 8000)
        best = {
            "score": 0.0,
            "correlation": 0.0,
            "amplitude_match": 0.0,
            "loop_end": loop_end,
            "loop_start": loop_start,
            "loop_length": loop_end - loop_start,
        }
    return best


def encode_adpcm(samples: list[int], loop_start_sample: int | None = None) -> tuple[list[int], dict]:
    assert samples
    prediction = samples[0]
    index = 12
    initial_prediction = prediction
    initial_index = index
    nibbles = []
    loop_prediction = prediction
    loop_index = index

    desired_loop_position = None
    if loop_start_sample is not None:
        # Nibble j reconstructs source sample j+1.
        desired_loop_position = max(0, loop_start_sample - 1)

    for source_index, target in enumerate(samples[1:]):
        if source_index == desired_loop_position:
            loop_prediction = prediction
            loop_index = index

        step = STEP_TABLE[index]
        best_code = 0
        best_prediction = prediction
        best_error = None
        for candidate in range(16):
            delta = step >> 3
            if candidate & 4:
                delta += step
            if candidate & 2:
                delta += step >> 1
            if candidate & 1:
                delta += step >> 2
            candidate_prediction = prediction + (-delta if candidate & 8 else delta)
            candidate_prediction = max(-32768, min(32767, candidate_prediction))
            error = abs(int(target) - candidate_prediction)
            if best_error is None or error < best_error:
                best_code = candidate
                best_prediction = candidate_prediction
                best_error = error

        code = best_code
        prediction = best_prediction
        index = max(0, min(88, index + INDEX_DELTA[code & 7]))
        nibbles.append(code)

    return nibbles, {
        "initial_prediction": initial_prediction,
        "initial_index": initial_index,
        "loop_prediction": loop_prediction,
        "loop_index": loop_index,
    }


def write_bank(path: Path, nibbles: list[int]) -> None:
    padded = nibbles[:BANK_NIBBLES] + [0] * max(0, BANK_NIBBLES - len(nibbles))
    with path.open("w", encoding="ascii", newline="\n") as output:
        for word_index in range(BANK_WORDS):
            word = 0
            for nibble_index in range(4):
                word |= (padded[word_index * 4 + nibble_index] & 0xF) << (nibble_index * 4)
            output.write("{:04X}\n".format(word))


def pack_info(bank: dict) -> int:
    value = bank["initial_prediction"] & 0xFFFF
    value |= (bank["initial_index"] & 0x7F) << 16
    value |= (bank["end_position"] & 0x7FFF) << 23
    value |= (bank["loop_start"] & 0x7FFF) << 38
    value |= (bank["loop_prediction"] & 0xFFFF) << 53
    value |= (bank["loop_index"] & 0x7F) << 69
    value |= (1 if bank["loop_enabled"] else 0) << 76
    return value


def increment_value(semitones: int) -> int:
    return int(round(65536.0 * SAMPLE_RATE / OUTPUT_RATE * (2.0 ** (semitones / 12.0))))


def metadata_text(banks: list[dict]) -> str:
    lines = [
        "// Generated from CC0 multisamples. Banks 0-3: erhu; 4-7: guzheng.",
        "// Root groups follow the currently playable C4..D#6 range.",
        "function [1:0] sample_root;",
        "input [4:0] voice;",
        "input [1:0] instrument;",
        "begin",
        "if(instrument==0) sample_root=voice<=1 ? 2'd0 : voice<=5 ? 2'd1 : voice<=8 ? 2'd2 : 2'd3;",
        "else sample_root=voice<=6 ? 2'd0 : voice<=13 ? 2'd1 : voice<=15 ? 2'd2 : 2'd3;",
        "end endfunction",
        "function [3:0] sample_bank;",
        "input [4:0] voice;",
        "input [1:0] instrument;",
        "begin sample_bank={1'b0,instrument,2'b00}+{2'b0,sample_root(voice,instrument)}; end",
        "endfunction",
        "function [76:0] sample_info;",
        "input [3:0] bank;",
        "begin case(bank)",
    ]
    for bank_index, bank in enumerate(banks):
        lines.append("4'd{}: sample_info=77'h{:020X};".format(bank_index, pack_info(bank)))
    lines.extend(["default: sample_info=0; endcase end endfunction", ""])
    lines.extend([
        "// Q7 bank gain keeps the high guzheng register level with the other roots.",
        "function [7:0] sample_gain;",
        "input [3:0] bank;",
        "begin sample_gain=bank==4'd7 ? 8'd247 : 8'd128; end",
        "endfunction",
        "",
        "// Q16 source-step increments for a 13 kHz bank and 48.828125 kHz output.",
        "function [15:0] sample_increment;",
        "input [4:0] voice;",
        "input [5:0] note;",
        "input [1:0] instrument;",
        "integer root_offset;",
        "integer semitone;",
        "begin",
        "if(instrument==0) root_offset=voice<=1 ? 0 : voice<=5 ? 4 : voice<=8 ? 7 : 9;",
        "else root_offset=voice<=6 ? 0 : voice<=13 ? 7 : 14;",
        "semitone=note-root_offset;",
        "case(semitone+8)",
    ])
    for offset, semitone in enumerate(range(-8, 19)):
        lines.append("{}: sample_increment=16'd{}; // {} semitones".format(
            offset, increment_value(semitone), semitone
        ))
    lines.extend([
        "default: sample_increment=16'd0;",
        "endcase end endfunction",
        "",
        "function [14:0] sample_step;",
        "input [6:0] index;",
        "begin case(index)",
    ])
    for index, step in enumerate(STEP_TABLE):
        lines.append("7'd{}: sample_step=15'd{};".format(index, step))
    lines.extend(["default: sample_step=15'd32767;", "endcase end", "endfunction", ""])
    return "\n".join(lines)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "sample_rate": SAMPLE_RATE,
        "output_rate": OUTPUT_RATE,
        "bank_words": BANK_WORDS,
        "banks": [],
        "sources": [
            {
                "name": "sfzinstruments/aliexpress-erhu",
                "url": "https://github.com/sfzinstruments/aliexpress-erhu",
                "license": "CC0-1.0",
            },
            {
                "name": "sparklecatta-lang/XSXB-Band-Samples",
                "url": "https://github.com/sparklecatta-lang/XSXB-Band-Samples",
                "license": "CC0-1.0",
            },
        ],
    }

    for bank_index, (instrument, entries) in enumerate((("erhu", ERHU), ("guzheng", GUZHENG))):
        for root_index, (root_note, path) in enumerate(entries):
            decoded = decode_audio(path)
            samples, prep = prepare(decoded)
            loop = choose_loop(samples) if instrument == "erhu" else None
            if loop is not None:
                samples = samples[:loop["loop_end"]]

            if instrument == "guzheng":
                fade = min(256, len(samples))
                for index in range(fade):
                    gain = (fade - 1 - index) / max(1, fade - 1)
                    source_index = len(samples) - fade + index
                    samples[source_index] = int(round(samples[source_index] * gain))

            nibbles, encoder = encode_adpcm(
                samples, loop["loop_start"] if loop is not None else None
            )
            index = bank_index * 4 + root_index
            bank = {
                "index": index,
                "instrument": instrument,
                "root_note": root_note,
                "source": str(path),
                "sample_count": len(samples),
                "nibble_count": len(nibbles),
                "end_position": max(0, len(nibbles) - 1),
                "loop_enabled": loop is not None,
                "loop_start": max(0, loop["loop_start"] - 1) if loop is not None else 0,
                "loop_length_samples": loop["loop_length"] if loop is not None else 0,
                "loop_correlation": loop["correlation"] if loop is not None else 0.0,
                "loop_amplitude_match": loop["amplitude_match"] if loop is not None else 0.0,
                **prep,
                **encoder,
            }
            write_bank(OUTPUT / "sample_adpcm_{}.mem".format(index), nibbles)
            manifest["banks"].append(bank)
            print(json.dumps(bank, ensure_ascii=False))

    (OUTPUT / "sample_metadata.vh").write_text(metadata_text(manifest["banks"]), encoding="utf-8")
    (OUTPUT / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
