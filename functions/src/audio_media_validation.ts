import {spawn} from "node:child_process";
import {createHash} from "node:crypto";
import {mkdtemp, readFile, rm, stat, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import ffmpegPath from "ffmpeg-static";

export const AUDIO_VALIDATION_VERSION = "ffmpeg-aac-mono-v1";
export const MIN_VALIDATED_AUDIO_SECONDS = 0.5;
export const MAX_VALIDATED_AUDIO_SECONDS = 60.75;
export const MAX_TRANSCODED_AUDIO_BYTES = 2 * 1024 * 1024;
export const MAX_UNTRUSTED_AUDIO_BYTES = 2 * 1024 * 1024;

const FFMPEG_TIMEOUT_MS = 15_000;
const MAX_PROCESS_OUTPUT_BYTES = 16 * 1024;

export interface ValidatedAudioMedia {
  durationMs: number;
  sizeBytes: number;
}

export interface ValidatedAudioBuffer extends ValidatedAudioMedia {
  bytes: Buffer;
  sha256: string;
}

export class AudioMediaValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AudioMediaValidationError";
  }
}

/**
 * Decode the complete untrusted upload and emit Lumi's canonical playback
 * representation. The input demuxer and protocols are fixed deliberately:
 * uploaded bytes cannot make ffmpeg fetch a URL or select a playlist/device.
 * Output is capped just beyond 60 seconds so a dishonest container duration
 * cannot turn a tiny compressed upload into an unbounded CPU job.
 *
 * @param {string} inputPath Random server-owned temporary input filename.
 * @param {string} outputPath Random server-owned temporary output filename.
 * @return {Promise<ValidatedAudioMedia>} Validated canonical media details.
 */
export async function validateAndTranscodeComprehensionAudio(
  inputPath: string,
  outputPath: string
): Promise<ValidatedAudioMedia> {
  const executable = ffmpegPath;
  if (!executable) {
    throw new Error("Bundled ffmpeg executable is unavailable");
  }

  const args = [
    "-hide_banner",
    "-loglevel", "error",
    "-nostdin",
    "-threads", "1",
    "-protocol_whitelist", "file,pipe",
    "-f", "mov",
    "-i", inputPath,
    "-map", "0:a:0",
    "-vn",
    "-sn",
    "-dn",
    "-map_metadata", "-1",
    "-map_chapters", "-1",
    "-ac", "1",
    "-ar", "16000",
    "-c:a", "aac",
    "-b:a", "48k",
    "-t", "61",
    "-movflags", "+faststart",
    "-f", "mp4",
    "-progress", "pipe:1",
    "-nostats",
    "-y",
    outputPath,
  ];

  let progressOutput = "";
  let errorOutput = "";
  let timedOut = false;

  await new Promise<void>((resolve, reject) => {
    const child = spawn(executable, args, {
      shell: false,
      stdio: ["pipe", "pipe", "pipe"],
      env: {PATH: process.env.PATH ?? ""},
    });
    child.stdin.end();

    const appendBounded = (current: string, chunk: Buffer): string => {
      if (current.length >= MAX_PROCESS_OUTPUT_BYTES) return current;
      return (current + chunk.toString("utf8")).slice(
        0,
        MAX_PROCESS_OUTPUT_BYTES
      );
    };
    child.stdout.on("data", (chunk: Buffer) => {
      progressOutput = appendBounded(progressOutput, chunk);
    });
    child.stderr.on("data", (chunk: Buffer) => {
      errorOutput = appendBounded(errorOutput, chunk);
    });

    const timeout = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, FFMPEG_TIMEOUT_MS);

    child.once("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.once("close", (code) => {
      clearTimeout(timeout);
      if (timedOut) {
        reject(new AudioMediaValidationError("Media decode timed out"));
      } else if (code !== 0) {
        reject(new AudioMediaValidationError(
          `Media decode failed: ${errorOutput.trim().slice(0, 500)}`
        ));
      } else {
        resolve();
      }
    });
  });

  const durationMatches = [...progressOutput.matchAll(
    /^out_time_(?:us|ms)=(\d+)$/gm
  )];
  const durationMicros = Number(
    durationMatches.length > 0 ? durationMatches[durationMatches.length - 1][1] : 0
  );
  const durationMs = Math.round(durationMicros / 1000);
  if (
    !Number.isFinite(durationMs) ||
    durationMs < MIN_VALIDATED_AUDIO_SECONDS * 1000 ||
    durationMs > MAX_VALIDATED_AUDIO_SECONDS * 1000
  ) {
    throw new AudioMediaValidationError("Media duration is outside limits");
  }

  const outputStat = await stat(outputPath);
  if (
    !outputStat.isFile() ||
    outputStat.size <= 0 ||
    outputStat.size >= MAX_TRANSCODED_AUDIO_BYTES
  ) {
    throw new AudioMediaValidationError("Canonical media size is outside limits");
  }

  return {durationMs, sizeBytes: outputStat.size};
}

/**
 * Buffer boundary used between the privileged receipt callable and the
 * no-permissions decoder worker. Temporary names are server-generated and the
 * directory is removed on every success/failure path.
 *
 * @param {Buffer} inputBytes Untrusted uploaded media bytes.
 * @return {Promise<ValidatedAudioBuffer>} Canonical AAC/M4A bytes and facts.
 */
export async function validateAndTranscodeAudioBuffer(
  inputBytes: Buffer
): Promise<ValidatedAudioBuffer> {
  if (inputBytes.length <= 0 || inputBytes.length >= MAX_UNTRUSTED_AUDIO_BYTES) {
    throw new AudioMediaValidationError("Uploaded media size is outside limits");
  }
  const workDir = await mkdtemp(join(tmpdir(), "lumi-audio-"));
  const inputPath = join(workDir, "untrusted-upload.m4a");
  const outputPath = join(workDir, "validated-output.m4a");
  try {
    await writeFile(inputPath, inputBytes, {flag: "wx"});
    const media = await validateAndTranscodeComprehensionAudio(
      inputPath,
      outputPath
    );
    const bytes = await readFile(outputPath);
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    return {...media, bytes, sha256};
  } finally {
    await rm(workDir, {recursive: true, force: true});
  }
}
