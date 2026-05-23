#!/usr/bin/env python3
"""
Generate bundled letter audio assets expected by Pismenka.

Default provider is macOS `say`, which works offline and can generate the full
asset set immediately. `say` must be allowed to use the macOS speech service;
if generated files are tiny/empty, rerun outside restrictive sandboxes. For the
current shipped letter voices, pass `--provider google`; Czech defaults to
Google Cloud TTS `cs-CZ-Chirp3-HD-Achernar`, and American English defaults to
`en-US-Chirp3-HD-Aoede`.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUTPUT_DIR = ROOT / "Pismenka" / "Sounds"
LETTERS_DIR = OUTPUT_DIR / "Letters"

ENGLISH_LETTERS = [chr(code) for code in range(ord("A"), ord("Z") + 1)]
CZECH_LETTERS = [
    "A", "Á", "B", "C", "Č", "D", "Ď", "E", "É", "Ě",
    "F", "G", "H", "I", "Í", "J", "K", "L", "M", "N",
    "Ň", "O", "Ó", "P", "Q", "R", "Ř", "S", "Š", "T",
    "Ť", "U", "Ú", "Ů", "V", "W", "X", "Y", "Ý", "Z", "Ž",
]

ENGLISH_LETTER_PROMPTS = {
    "A": "A as in apple",
    "B": "B as in banana",
    "C": "C as in cat",
    "D": "D as in daddy",
    "E": "E as in elephant",
    "F": "F as in fish",
    "G": "G as in guitar",
    "H": "H as in house",
    "I": "I as in igloo",
    "J": "J as in jacket",
    "K": "K as in kite",
    "L": "L as in lemon",
    "M": "M as in mommy",
    "N": "N as in nose",
    "O": "O as in orange",
    "P": "P as in pencil",
    "Q": "Q as in queen",
    "R": "R as in robot",
    "S": "S as in sun",
    "T": "T as in tiger",
    "U": "U as in umbrella",
    "V": "V as in violin",
    "W": "W as in watch",
    "X": "X as in xylophone",
    "Y": "Y as in yogurt",
    "Z": "Z as in zebra",
}

CZECH_LETTER_PROMPTS = {
    "A": "Á jako auto",
    "Á": "Dlouhé á",
    "B": "Bé jako banán",
    "C": "Cé jako citrón",
    "Č": "Čé jako čáp",
    "D": "Dé jako dům",
    "Ď": "Ďé jako ďábel",
    "E": "É jako euro",
    "É": "Dlouhé é",
    "Ě": "É s háčkem",
    "F": "Ef jako fialka",
    "G": "Gé jako guma",
    "H": "Há jako hora",
    "I": "Í jako iglú",
    "Í": "Dlouhé í",
    "J": "Jé jako jablko",
    "K": "Ká jako kočka",
    "L": "El jako lev",
    "M": "Em jako máma",
    "N": "En jako nos",
    "Ň": "En s háčkem",
    "O": "Ó jako oko",
    "Ó": "Dlouhé ó",
    "P": "Pé jako pes",
    "Q": "Kvé",
    "R": "Er jako ryba",
    "Ř": "Eř jako řeka",
    "S": "Es jako slunce",
    "Š": "Eš jako šála",
    "T": "Té jako táta",
    "Ť": "Ťé jako ťuká",
    "U": "Ú jako ucho",
    "Ú": "Dlouhé ú",
    "Ů": "Ů s kroužkem",
    "V": "Vé jako voda",
    "W": "Dvojité vé",
    "X": "Iks",
    "Y": "Ipsilón",
    "Ý": "Dlouhý Ipsilón",
    "Z": "Zet jako zub",
    "Ž": "Žet jako žába",
}

SFX_SPECS = {
    "sfx_correct.mp3": "sine=frequency=880:duration=0.12,sine=frequency=1320:duration=0.14",
    "sfx_wrong.mp3": "sine=frequency=220:duration=0.18",
    "sfx_streak_5.mp3": "sine=frequency=660:duration=0.10,sine=frequency=880:duration=0.10,sine=frequency=1175:duration=0.18",
    "sfx_streak_10.mp3": "sine=frequency=660:duration=0.10,sine=frequency=880:duration=0.10,sine=frequency=1175:duration=0.10,sine=frequency=1568:duration=0.22",
    "sfx_click.mp3": "sine=frequency=1000:duration=0.04",
    # Note: sfx_applause.mp3 is intentionally NOT generated here. It is a real
    # CC0 crowd-applause clip fetched by `scripts/fetch_celebration_applause.py`
    # and committed to Pismenka/Sounds/. The synthesized noise version that
    # used to live here sounded like static, not clapping.
}

# Recorded "Wow!" exclamation played at the start of every daily-Winner
# celebration regardless of profile language. Tuned with higher `style` and
# lower `stability` than letter clips so the voice has real energy. Falls
# back to macOS `say` if ElevenLabs isn't configured, but the result there is
# noticeably less expressive.
CELEBRATION_VOICE_LINES = {
    "sfx_wow_en.m4a": {
        "text": "Wow!",
        "language": "en",
        "voice": "Samantha",
    },
}

# Per-file ElevenLabs voice_settings overrides. Anything not listed here uses
# the default settings in `generate_with_elevenlabs`.
ELEVENLABS_VOICE_SETTINGS_OVERRIDES = {
    "sfx_wow_en.m4a": {
        "stability": 0.22,
        "similarity_boost": 0.75,
        "style": 0.55,
        "use_speaker_boost": True,
        "speed": 1.0,
    },
}

# Google Cloud Text-to-Speech expands some Czech standalone letter names in a
# way that duplicates the prompt text. These overrides reproduce the reviewed
# shipped letter set from the Google Chirp3-HD regeneration pass.
GOOGLE_TEXT_OVERRIDES = {
    "cz_á.m4a": "á.",
    "cz_é.m4a": "é.",
    "cz_ě.m4a": "e s háčkem.",
    "cz_í.m4a": "í.",
    "cz_ó.m4a": "ó.",
    "cz_ú.m4a": "ú.",
    "cz_ů.m4a": "ů.",
    "cz_x.m4a": "x jako ksilofon.",
    "cz_ý.m4a": "dlouhý ipsilon.",
    "cz_z.m4a": "zet jako zebra.",
}


@dataclass(frozen=True)
class Asset:
    filename: str
    text: str
    language: str
    voice: str


def audio_key(value: str) -> str:
    return value.lower()


def is_czech_letter_filename(filename: str) -> bool:
    return filename.startswith("cz_")


def output_path_for(filename: str) -> Path:
    if filename.startswith("en_") or is_czech_letter_filename(filename):
        return LETTERS_DIR / filename
    return OUTPUT_DIR / filename


def english_letter_prompt(letter: str) -> str:
    prompt = ENGLISH_LETTER_PROMPTS[letter]
    letter_name, example = prompt.split(" as in ", 1)
    return f"{letter_name}, as in {example}."


def czech_letter_prompt(letter: str) -> str:
    prompt = CZECH_LETTER_PROMPTS[letter]
    if " jako " in prompt:
        letter_name, example = prompt.split(" jako ", 1)
        return f"{letter_name}, jako {example}."
    return prompt.rstrip(".") + "."


def expected_voice_assets() -> list[Asset]:
    assets: list[Asset] = []

    for letter in ENGLISH_LETTERS:
        assets.append(Asset(
            filename=f"en_{audio_key(letter)}.m4a",
            text=english_letter_prompt(letter),
            language="en",
            voice="Samantha",
        ))

    for letter in CZECH_LETTERS:
        assets.append(Asset(
            filename=f"cz_{audio_key(letter)}.m4a",
            text=czech_letter_prompt(letter),
            language="cs",
            voice="Zuzana",
        ))

    for filename, spec in CELEBRATION_VOICE_LINES.items():
        assets.append(Asset(
            filename=filename,
            text=spec["text"],
            language=spec["language"],
            voice=spec["voice"],
        ))

    return assets


def missing_assets(include_sfx: bool = True) -> list[str]:
    expected = [asset.filename for asset in expected_voice_assets()]
    if include_sfx:
        expected += list(SFX_SPECS.keys())
    return sorted(name for name in expected if not output_path_for(name).exists())


def run(cmd: list[str], quiet: bool = True) -> None:
    subprocess.run(
        cmd,
        check=True,
        stdout=subprocess.DEVNULL if quiet else None,
        stderr=subprocess.DEVNULL if quiet else None,
    )


def generate_with_say(asset: Asset, out_path: Path) -> None:
    if not shutil.which("say"):
        raise SystemExit("macOS `say` was not found.")
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg was not found.")

    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "voice.wav"
        run([
            "say",
            "-v", asset.voice,
            "--file-format=WAVE",
            "--data-format=LEI16@22050",
            "-o", str(wav_path),
            asset.text,
        ])
        run([
            "ffmpeg", "-y",
            "-i", str(wav_path),
            "-c:a", "aac",
            "-b:a", "128k",
            "-movflags", "+faststart",
            str(out_path),
        ])


def elevenlabs_voice_id(asset: Asset) -> str:
    if asset.language == "cs":
        return os.environ.get("ELEVENLABS_CZ_VOICE_ID", "MpbYQvoTmXjHkaxtLiSh")
    return os.environ.get("ELEVENLABS_EN_VOICE_ID", "bF7C2fCv7Zf30iT84wZ1")


def generate_with_elevenlabs(asset: Asset, out_path: Path) -> None:
    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        raise SystemExit("Set ELEVENLABS_API_KEY or use --provider say.")
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg was not found.")

    url = (
        "https://api.elevenlabs.io/v1/text-to-speech/"
        f"{elevenlabs_voice_id(asset)}?output_format=mp3_44100_128"
    )
    voice_settings = ELEVENLABS_VOICE_SETTINGS_OVERRIDES.get(asset.filename, {
        "stability": 0.35,
        "similarity_boost": 0.8,
        "style": 0.25,
        "use_speaker_boost": True,
        "speed": 0.85,
    })
    payload = {
        "text": asset.text,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": voice_settings,
    }
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
        },
        method="POST",
    )

    with tempfile.TemporaryDirectory() as tmp:
        mp3_path = Path(tmp) / "voice.mp3"
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                mp3_path.write_bytes(response.read())
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"ElevenLabs failed for {asset.filename}: {detail}") from error

        run([
            "ffmpeg", "-y",
            "-i", str(mp3_path),
            "-c:a", "aac",
            "-b:a", "128k",
            "-movflags", "+faststart",
            str(out_path),
        ])


def edge_voice(asset: Asset) -> str:
    if asset.language == "cs":
        return os.environ.get("EDGE_CZ_VOICE", "cs-CZ-AntoninNeural")
    return os.environ.get("EDGE_EN_VOICE", "en-US-JennyNeural")


async def save_with_edge_tts(asset: Asset, mp3_path: Path) -> None:
    try:
        import edge_tts  # type: ignore[import-not-found]
    except ImportError as error:
        raise SystemExit(
            "Python package `edge-tts` is required for --provider edge. "
            "Install it with: python3 -m pip install edge-tts"
        ) from error

    communicate = edge_tts.Communicate(
        asset.text,
        voice=edge_voice(asset),
        rate=os.environ.get("EDGE_TTS_RATE", "+0%"),
        volume=os.environ.get("EDGE_TTS_VOLUME", "+0%"),
        pitch=os.environ.get("EDGE_TTS_PITCH", "+0Hz"),
    )
    await communicate.save(str(mp3_path))


def generate_with_edge(asset: Asset, out_path: Path) -> None:
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg was not found.")

    with tempfile.TemporaryDirectory() as tmp:
        mp3_path = Path(tmp) / "voice.mp3"
        asyncio.run(save_with_edge_tts(asset, mp3_path))
        run([
            "ffmpeg", "-y",
            "-i", str(mp3_path),
            "-c:a", "aac",
            "-b:a", "128k",
            "-movflags", "+faststart",
            str(out_path),
        ])


def google_voice(asset: Asset) -> str:
    if asset.language == "cs":
        return os.environ.get("GOOGLE_CZ_VOICE", "cs-CZ-Chirp3-HD-Achernar")
    return os.environ.get("GOOGLE_EN_VOICE", "en-US-Chirp3-HD-Aoede")


def google_language_code(voice: str) -> str:
    parts = voice.split("-")
    if len(parts) < 2:
        raise ValueError(f"Google voice name does not include a language code: {voice}")
    return "-".join(parts[:2])


def google_access_token() -> str:
    token = os.environ.get("GOOGLE_OAUTH_ACCESS_TOKEN")
    if token:
        return token
    if not shutil.which("gcloud"):
        raise SystemExit(
            "gcloud was not found. Install Google Cloud CLI, run "
            "`gcloud auth login`, or set GOOGLE_OAUTH_ACCESS_TOKEN."
        )
    return subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()


def google_quota_project() -> str | None:
    project = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCLOUD_PROJECT")
    if project:
        return project
    if not shutil.which("gcloud"):
        return None
    result = subprocess.run(
        ["gcloud", "config", "get-value", "project"],
        check=False,
        capture_output=True,
        text=True,
    )
    project = result.stdout.strip()
    if result.returncode == 0 and project and project != "(unset)":
        return project
    return None


def google_text(asset: Asset) -> str:
    return GOOGLE_TEXT_OVERRIDES.get(asset.filename, asset.text)


def generate_with_google(asset: Asset, out_path: Path) -> None:
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg was not found.")

    voice = google_voice(asset)
    headers = {
        "Authorization": f"Bearer {google_access_token()}",
        "Content-Type": "application/json; charset=utf-8",
    }
    quota_project = google_quota_project()
    if quota_project:
        headers["x-goog-user-project"] = quota_project

    payload = {
        "input": {"text": google_text(asset)},
        "voice": {
            "languageCode": google_language_code(voice),
            "name": voice,
        },
        "audioConfig": {
            "audioEncoding": "MP3",
            "speakingRate": 1.0,
            "pitch": 0.0,
        },
    }
    request = urllib.request.Request(
        "https://texttospeech.googleapis.com/v1/text:synthesize",
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )

    with tempfile.TemporaryDirectory() as tmp:
        mp3_path = Path(tmp) / "voice.mp3"
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                response_payload = json.loads(response.read().decode("utf-8"))
                audio_content = response_payload["audioContent"]
                mp3_path.write_bytes(base64.b64decode(audio_content))
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"Google Cloud TTS failed for {asset.filename}: {detail}") from error

        run([
            "ffmpeg", "-y",
            "-i", str(mp3_path),
            "-c:a", "aac",
            "-b:a", "128k",
            "-movflags", "+faststart",
            str(out_path),
        ])


def generate_sfx(filename: str, out_path: Path) -> None:
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg was not found.")
    # Simple, generated placeholder SFX. Replace with designed sounds later if desired.
    spec = SFX_SPECS[filename]
    if "," in spec:
        parts = spec.split(",")
        inputs: list[str] = []
        filter_parts: list[str] = []
        for idx, part in enumerate(parts):
            inputs.extend(["-f", "lavfi", "-i", part])
            filter_parts.append(f"[{idx}:a]")
        filter_complex = "".join(filter_parts) + f"concat=n={len(parts)}:v=0:a=1[out]"
        run([
            "ffmpeg", "-y",
            *inputs,
            "-filter_complex", filter_complex,
            "-map", "[out]",
            "-codec:a", "libmp3lame",
            "-q:a", "4",
            str(out_path),
        ])
    else:
        run([
            "ffmpeg", "-y",
            "-f", "lavfi",
            "-i", spec,
            "-codec:a", "libmp3lame",
            "-q:a", "4",
            str(out_path),
        ])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["say", "elevenlabs", "edge", "google"], default="say")
    parser.add_argument("--dry-run", action="store_true", help="Only print missing assets.")
    parser.add_argument("--force", action="store_true", help="Regenerate existing files too.")
    parser.add_argument("--repair-small", action="store_true", default=True, help="Regenerate existing voice files smaller than --min-bytes.")
    parser.add_argument("--min-bytes", type=int, default=1000, help="Minimum plausible voice asset size for --repair-small.")
    parser.add_argument("--only-files", help="Path to a newline-separated list of filenames to generate.")
    parser.add_argument("--only-english-letters", action="store_true", help="Only generate English alphabet letter files.")
    parser.add_argument("--only-czech-letters", action="store_true", help="Only generate Czech alphabet letter files.")
    parser.add_argument("--skip-sfx", action="store_true", help="Only generate voice .m4a files.")
    args = parser.parse_args()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    LETTERS_DIR.mkdir(parents=True, exist_ok=True)

    voice_assets = expected_voice_assets()
    if args.only_english_letters or args.only_czech_letters:
        letter_filenames: set[str] = set()
        if args.only_english_letters:
            letter_filenames.update(f"en_{audio_key(letter)}.m4a" for letter in ENGLISH_LETTERS)
        if args.only_czech_letters:
            letter_filenames.update(f"cz_{audio_key(letter)}.m4a" for letter in CZECH_LETTERS)
        voice_assets = [asset for asset in voice_assets if asset.filename in letter_filenames]

    only_files: set[str] | None = None
    if args.only_files:
        only_files = {
            line.strip()
            for line in Path(args.only_files).read_text(encoding="utf-8").splitlines()
            if line.strip()
        }
        voice_assets = [asset for asset in voice_assets if asset.filename in only_files]

    targets = [
        asset for asset in voice_assets
        if args.force
        or not output_path_for(asset.filename).exists()
        or (
            args.repair_small
            and output_path_for(asset.filename).exists()
            and output_path_for(asset.filename).stat().st_size < args.min_bytes
        )
    ]
    sfx_targets = [
        filename for filename in SFX_SPECS
        if not args.skip_sfx
        and (only_files is None or filename in only_files)
        and (args.force or not output_path_for(filename).exists())
    ]

    if args.dry_run:
        expected = [asset.filename for asset in voice_assets]
        if not args.skip_sfx:
            expected += [
                filename for filename in SFX_SPECS
                if only_files is None or filename in only_files
            ]
        for name in sorted(name for name in expected if not output_path_for(name).exists()):
            print(name)
        print(f"\nMissing voice m4a: {sum(1 for asset in voice_assets if not output_path_for(asset.filename).exists())}")
        print(f"Missing sfx mp3: {sum(1 for filename in expected if filename.endswith('.mp3') and not output_path_for(filename).exists())}")
        return 0

    generators = {
        "say": generate_with_say,
        "elevenlabs": generate_with_elevenlabs,
        "edge": generate_with_edge,
        "google": generate_with_google,
    }
    generator = generators[args.provider]

    total = len(targets) + len(sfx_targets)
    if total == 0:
        print("All audio assets already exist.")
        return 0

    print(f"Generating {len(targets)} voice files and {len(sfx_targets)} SFX files into {OUTPUT_DIR}")
    for idx, asset in enumerate(targets, start=1):
        out_path = output_path_for(asset.filename)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        print(f"[{idx}/{total}] {asset.filename} <- {asset.text}")
        generator(asset, out_path)

    offset = len(targets)
    for idx, filename in enumerate(sfx_targets, start=1):
        print(f"[{offset + idx}/{total}] {filename}")
        out_path = output_path_for(filename)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        generate_sfx(filename, out_path)

    remaining = missing_assets(include_sfx=not args.skip_sfx)
    if remaining:
        print("\nStill missing:")
        for name in remaining:
            print(name)
        return 1

    print("\nDone. All expected audio assets are present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
