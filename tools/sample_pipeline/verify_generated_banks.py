from __future__ import annotations

import json
import math
import struct
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parent
GENERATED = ROOT / "generated"
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


def read_nibbles(path: Path) -> list[int]:
    nibbles = []
    for line in path.read_text(encoding="ascii").splitlines():
        word = int(line, 16)
        nibbles.extend((word >> shift) & 0xF for shift in (0, 4, 8, 12))
    return nibbles


def decode(nibbles: list[int], prediction: int, index: int) -> list[int]:
    result = [prediction]
    for code in nibbles:
        step = STEP_TABLE[index]
        difference = step >> 3
        if code & 4:
            difference += step
        if code & 2:
            difference += step >> 1
        if code & 1:
            difference += step >> 2
        prediction += -difference if code & 8 else difference
        prediction = max(-32768, min(32767, prediction))
        index = max(0, min(88, index + INDEX_DELTA[code & 7]))
        result.append(prediction)
    return result


def write_wave(path: Path, samples: list[int], sample_rate: int) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(struct.pack("<{}h".format(len(samples)), *samples))


def main() -> None:
    manifest = json.loads((GENERATED / "manifest.json").read_text(encoding="utf-8"))
    rate = manifest["sample_rate"]
    report = []
    for bank in manifest["banks"]:
        nibbles = read_nibbles(GENERATED / "sample_adpcm_{}.mem".format(bank["index"]))
        decoded = decode(
            nibbles[:bank["nibble_count"]],
            bank["initial_prediction"],
            bank["initial_index"],
        )
        seam_report = None
        if bank["loop_enabled"]:
            loop_position = bank["loop_start"]
            loop_sample = decode(
                [nibbles[loop_position]],
                bank["loop_prediction"],
                bank["loop_index"],
            )[-1]
            seam_before = decoded[bank["end_position"] + 1]
            seam_after = loop_sample
            adjacent = [
                abs(decoded[index + 1] - decoded[index])
                for index in range(max(0, bank["end_position"] - 2000), bank["end_position"])
            ]
            adjacent.sort()
            seam_report = {
                "before": seam_before,
                "after": seam_after,
                "jump": abs(seam_after - seam_before),
                "typical_p99_jump": adjacent[int(len(adjacent) * 0.99)],
            }

        preview = decoded[:bank["end_position"] + 1]
        if bank["loop_enabled"]:
            preview = preview + decoded[bank["loop_start"]:bank["end_position"] + 1]
        write_wave(
            GENERATED / "preview_bank_{}_{}_{}.wav".format(
                bank["index"], bank["instrument"], bank["root_note"]
            ),
            preview,
            rate,
        )
        report.append(
            {
                "bank": bank["index"],
                "instrument": bank["instrument"],
                "root_note": bank["root_note"],
                "decoded_samples": len(decoded),
                "peak": max(abs(value) for value in decoded),
                "rms": round(math.sqrt(sum(value * value for value in decoded) / len(decoded))),
                "seam": seam_report,
            }
        )

    (GENERATED / "verification.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
