from __future__ import annotations

"""High-level asynchronous service for transcribing audio files with OpenAI Whisper.

This service wraps the helper logic currently used in the standalone
`transcribe_audio.py` CLI utility and makes it available as a reusable class
inside the backend codebase.

Key features
------------
1. 25 MB limit handling – automatic compression to 16 kHz mono MP3 @ 64 kbps
2. Automatic chunking into ≤10 minute segments if the compressed file is still
   too large for Whisper
3. Convenience coroutine ``transcribe_audio_file`` that returns the final text
   transcription

Typical usage
-------------
>>> svc = TranscriptionService()
>>> text = await svc.transcribe_audio_file(Path("/tmp/audio.m4a"))
"""

from pathlib import Path
from typing import List
import asyncio
import shutil
import subprocess
import tempfile
import uuid

from openai import OpenAI
from pydub import AudioSegment

__all__ = ["TranscriptionService"]

DEFAULT_MODEL = "whisper-1"
OPENAI_AUDIO_MAX_BYTES = 25 * 1024 * 1024  # 25 MB per OpenAI API docs


class TranscriptionService:
    """Service class encapsulating audio transcription logic."""

    def __init__(self, *, model: str = DEFAULT_MODEL):
        self._client = OpenAI()  # API key picked up from env var
        self._model = model

    # ---------------------------------------------------------------------
    # Public coroutine -----------------------------------------------------
    # ---------------------------------------------------------------------
    async def transcribe_audio_file(self, audio_file_path: Path) -> str:
        """Return transcription text for *audio_file_path*.

        This method is designed for use inside async contexts (e.g. Cloud
        Functions). All blocking operations (ffmpeg, OpenAI SDK calls) are
        executed in a thread pool via ``asyncio.to_thread``.
        """

        if not audio_file_path.exists():
            raise FileNotFoundError(f"Audio file not found: {audio_file_path}")

        temp_files: List[Path] = []
        try:
            # 1️⃣ Ensure the file is under the 25 MB limit – compress if needed
            if self._file_under_limit(audio_file_path):
                target_path = audio_file_path
            else:
                target_path = await asyncio.to_thread(self._compress_to_mp3, audio_file_path)
                temp_files.append(target_path)

            # 2️⃣ If still over limit, split into chunks
            if self._file_under_limit(target_path):
                return await self._upload_for_transcription(target_path)

            chunks = await asyncio.to_thread(self._split_audio_to_mp3_chunks, target_path)
            temp_files.extend(chunks)

            # 3️⃣ Transcribe each chunk sequentially (Whisper quality benefits
            #     from full context per chunk; parallelism would risk rate-limits)
            transcripts: List[str] = []
            for chunk_path in chunks:
                transcripts.append(await self._upload_for_transcription(chunk_path))

            return "\n\n".join(transcripts)
        finally:
            # Clean up any temp artefacts
            for p in temp_files:
                try:
                    p.unlink(missing_ok=True)
                except Exception:
                    pass

    # ------------------------------------------------------------------
    # Internal helpers --------------------------------------------------
    # ------------------------------------------------------------------
    @staticmethod
    def _file_under_limit(path: Path) -> bool:
        return path.stat().st_size <= OPENAI_AUDIO_MAX_BYTES

    @staticmethod
    def _compress_to_mp3(src: Path, *, bitrate_kbps: int = 64) -> Path:
        """Re-encode *src* to a temporary MP3 to reduce size.

        Requires *ffmpeg* to be installed in the runtime environment.
        """
        if shutil.which("ffmpeg") is None:
            raise RuntimeError("ffmpeg not found — required for audio compression.")

        tmp_fd, tmp_path_str = tempfile.mkstemp(suffix=".mp3")
        tmp_path = Path(tmp_path_str)

        # Close the descriptor – ffmpeg will write to the path
        try:
            from os import close as _close

            _close(tmp_fd)
        except Exception:
            pass

        cmd = [
            "ffmpeg",
            "-i",
            str(src),
            "-vn",  # no video
            "-acodec",
            "libmp3lame",
            "-ar",
            "16000",  # 16 kHz sample rate keeps quality for speech
            "-ac",
            "1",  # mono
            "-b:a",
            f"{bitrate_kbps}k",
            "-y",
            str(tmp_path),
        ]

        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return tmp_path

    @staticmethod
    def _split_audio_to_mp3_chunks(src: Path, *, chunk_duration_ms: int = 10 * 60 * 1000) -> List[Path]:
        """Split *src* into ≤10-minute MP3 chunks within size limit."""
        if shutil.which("ffmpeg") is None:
            raise RuntimeError("ffmpeg not found — required for audio splitting.")

        audio = AudioSegment.from_file(src)
        chunks: List[Path] = []
        for start in range(0, len(audio), chunk_duration_ms):
            segment = audio[start : start + chunk_duration_ms]
            tmp_path = Path(tempfile.gettempdir()) / f"transcript_chunk_{uuid.uuid4().hex}.mp3"
            segment.export(
                tmp_path,
                format="mp3",
                bitrate="64k",
                parameters=["-ar", "16000", "-ac", "1"],
            )

            if tmp_path.stat().st_size > OPENAI_AUDIO_MAX_BYTES:
                tmp_path.unlink(missing_ok=True)
                raise RuntimeError(
                    "Chunk after export exceeds 25 MB; consider using shorter chunk duration."
                )

            chunks.append(tmp_path)

        if not chunks:
            raise RuntimeError("Audio splitting produced no chunks.")

        return chunks

    async def _upload_for_transcription(self, path: Path) -> str:
        """Upload *path* to Whisper and return the transcription text."""

        # The OpenAI Python SDK call is synchronous – run in default executor
        def _do_request() -> str:
            with path.open("rb") as f:
                response = self._client.audio.transcriptions.create(model=self._model, file=f)
            return response.text  # type: ignore[attr-defined]

        return await asyncio.to_thread(_do_request) 