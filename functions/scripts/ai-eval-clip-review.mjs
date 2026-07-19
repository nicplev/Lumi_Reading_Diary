#!/usr/bin/env node
// Local clip-review harness for the AI comprehension evaluator.
//
// Runs a directory of AUTHORISED/SYNTHETIC .m4a clips through the real
// production pipeline shape — Speech-to-Text V2 recognize (inline base64,
// `long`/`en-AU`, the exact transcription.ts request shape) then the real
// evaluation prompt (buildEvaluationRequestBody, `general` rubric) — and
// writes ONE self-contained review-sheet.html so a teacher can listen to
// each clip beside its transcript and evaluation and record an accuracy
// verdict.
//
// This script NEVER writes to Firestore or Storage: local file reads and
// direct provider API calls only. It refuses to run without --authorised.
//
// Usage (from functions/ after `npm run build`):
//   TOKEN="$(gcloud auth print-access-token)" PROJECT=lumi-ninc-au \
//     node scripts/ai-eval-clip-review.mjs --authorised \
//     --dir /path/to/clips --question "What happened in the story?"
//
// Options:
//   --dir <path>       directory of .m4a clips (required)
//   --question <text>  the teacher-set question evaluated for every clip
//                      (required)
//   --out <path>       output HTML path (default: <dir>/review-sheet.html —
//                      keep it next to the clips so the audio links work)
//   --authorised       confirm every clip is authorised/synthetic (required)
//
// Cost: one billable STT recognize + up to one Gemini call per clip.

import {createRequire} from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const {
  buildRecognizeBody,
  joinTranscript,
  minConfidence,
  billedSeconds,
  LOW_STT_CONFIDENCE_THRESHOLD,
} = require(path.join(here, '../lib/ai_evaluation/transcription.js'));
const {buildEvaluationRequestBody} =
  require(path.join(here, '../lib/ai_evaluation/evaluation.js'));
const {validateEvalResponse} =
  require(path.join(here, '../lib/ai_evaluation/schemas.js'));
const {rubricForKey, RUBRIC_VERSION} =
  require(path.join(here, '../lib/ai_evaluation/rubrics.js'));
const {
  AI_EVAL_REGION,
  AI_EVAL_SPEECH_ENDPOINT,
  AI_EVAL_VERTEX_BASE_URL,
  AI_EVAL_DEFAULT_MODEL,
} = require(path.join(here, '../lib/ai_evaluation/config.js'));

export const AUTHORISATION_WARNING = [
  'REFUSED: this harness processes audio through live provider APIs.',
  '',
  'Run it ONLY on clips you are authorised to process: synthetic audio or',
  'recordings with documented authority (see docs/AI_EVALUATION_PLAN.md).',
  'Never feed it historical or production child recordings. Each clip makes',
  'billable STT + Gemini calls. Nothing is written to Firestore or Storage,',
  'and the generated review sheet must be handled as sensitive content and',
  'deleted after review.',
  '',
  'Re-run with --authorised to confirm the clips meet these conditions.',
].join('\n');

// Pure: parses CLI args into {values, errors}. Exported for unit tests.
export function parseArgs(argv) {
  const values = {authorised: false, dir: '', question: '', out: ''};
  const errors = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--authorised') {
      values.authorised = true;
    } else if (arg === '--dir' || arg === '--question' || arg === '--out') {
      const value = argv[i + 1];
      if (value === undefined || value.startsWith('--')) {
        errors.push(`${arg} requires a value`);
      } else {
        values[arg.slice(2)] = value;
        i++;
      }
    } else {
      errors.push(`unknown argument: ${arg}`);
    }
  }
  if (!values.dir) errors.push('--dir is required');
  if (!values.question) errors.push('--question is required');
  return {values, errors};
}

// Pure: minimal HTML escaping for every model/file-derived string.
export function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

// Pure: one clip row -> the HTML card shown in the review sheet.
// row: {fileName, error?, inaudible?, transcript?, sttConfidence?,
//       billedSec?, lowConfidence?, evalProblem?, evaluation?}
export function renderClipCard(row, index) {
  const name = escapeHtml(row.fileName);
  const parts = [];
  parts.push(`<section class="clip" id="clip-${index}">`);
  parts.push(`<h2>${index + 1}. ${name}</h2>`);
  parts.push(
    `<audio controls preload="none" src="./${encodeURIComponent(row.fileName)}"></audio>`);
  if (row.error) {
    parts.push(`<p class="problem">Pipeline error: ${escapeHtml(row.error)}</p>`);
  } else {
    const confidence = Number(row.sttConfidence ?? 0).toFixed(3);
    const low = row.lowConfidence ?
      ' <span class="badge warn">low STT confidence</span>' : '';
    parts.push(
      `<p class="meta">STT confidence ${escapeHtml(confidence)}${low} · ` +
      `billed ${escapeHtml(String(row.billedSec ?? 0))}s</p>`);
    if (row.inaudible) {
      parts.push('<p class="problem">No transcript returned (inaudible) — ' +
        'no evaluation call was made.</p>');
    } else {
      parts.push('<h3>Transcript</h3>');
      parts.push(`<blockquote>${escapeHtml(row.transcript)}</blockquote>`);
      if (row.evalProblem) {
        parts.push(
          `<p class="problem">Evaluation problem: ${escapeHtml(row.evalProblem)}</p>`);
      } else if (row.evaluation) {
        const evaluation = row.evaluation;
        const flags = evaluation.flags.length ?
          evaluation.flags.map((f) => `<span class="badge">${escapeHtml(f)}</span>`).join(' ') :
          '<span class="meta">none</span>';
        parts.push('<h3>Evaluation</h3>');
        parts.push(
          `<p><strong>assessable:</strong> ${evaluation.assessable} · ` +
          `<strong>level:</strong> ${escapeHtml(evaluation.overallLevel)} · ` +
          `<strong>confidence:</strong> ${escapeHtml(evaluation.confidence)}</p>`);
        parts.push(`<p><strong>flags:</strong> ${flags}</p>`);
        parts.push(`<p>${escapeHtml(evaluation.summary)}</p>`);
        parts.push('<table><thead><tr><th>Criterion</th><th>Score</th>' +
          '<th>Evidence</th></tr></thead><tbody>');
        for (const score of evaluation.criterionScores) {
          parts.push(
            `<tr><td>${escapeHtml(score.criterionId)}</td>` +
            `<td>${score.score}</td>` +
            `<td>${escapeHtml(score.evidence)}</td></tr>`);
        }
        parts.push('</tbody></table>');
      }
    }
  }
  parts.push('<h3>Teacher notes</h3>');
  parts.push('<div class="notes" contenteditable="true"></div>');
  parts.push('<h3>Accuracy verdict</h3>');
  parts.push('<div class="verdict" contenteditable="true"></div>');
  parts.push('</section>');
  return parts.join('\n');
}

// Pure: assembles the complete self-contained review sheet.
// meta: {generatedAt, model, question, rubricKey, rubricVersion, clipCount}
export function buildReviewSheetHtml(meta, rows) {
  const cards = rows.map((row, index) => renderClipCard(row, index)).join('\n');
  return [
    '<!doctype html>',
    '<html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<title>AI eval clip review</title>',
    '<style>',
    'body{font-family:system-ui,sans-serif;max-width:60rem;margin:2rem auto;',
    'padding:0 1rem;line-height:1.5;color:#1c1c1c}',
    '.clip{border:1px solid #ccc;border-radius:8px;padding:1rem;margin:1.5rem 0}',
    'blockquote{background:#f6f6f6;padding:.75rem;border-radius:6px}',
    'table{border-collapse:collapse;width:100%}',
    'td,th{border:1px solid #ddd;padding:.4rem;text-align:left;vertical-align:top}',
    '.badge{background:#eee;border-radius:4px;padding:0 .4rem;font-size:.85em}',
    '.badge.warn{background:#ffe3b3}',
    '.problem{color:#a33;font-weight:600}',
    '.meta{color:#555}',
    '.notes,.verdict{border:1px dashed #999;border-radius:6px;',
    'min-height:3rem;padding:.5rem;background:#fffef5}',
    '.banner{background:#fff3f3;border:1px solid #d99;',
    'border-radius:8px;padding:.75rem}',
    'audio{width:100%;margin:.5rem 0}',
    '</style></head><body>',
    '<h1>AI comprehension eval — clip review sheet</h1>',
    '<p class="banner"><strong>Authorised review content.</strong> ',
    'Audio, transcripts and evaluations on this page may contain personal ',
    'information. Handle as sensitive, do not redistribute, delete after ',
    'review. Generated locally; nothing was written to Firestore.</p>',
    `<p class="meta">Generated ${escapeHtml(meta.generatedAt)} · ` +
      `model ${escapeHtml(meta.model)} · rubric ` +
      `${escapeHtml(meta.rubricKey)} v${escapeHtml(String(meta.rubricVersion))} · ` +
      `${meta.clipCount} clip(s)</p>`,
    `<p><strong>Question:</strong> ${escapeHtml(meta.question)}</p>`,
    cards,
    '</body></html>',
  ].join('\n');
}

async function postJson(url, token, body) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const json = await response.json().catch(() => ({}));
  return {ok: response.ok, status: response.status, json};
}

async function processClip({filePath, fileName, token, project, model,
  rubric, question}) {
  const row = {fileName};
  const bytes = fs.readFileSync(filePath);

  const sttUrl = `https://${AI_EVAL_SPEECH_ENDPOINT}/v2/projects/${project}` +
    `/locations/${AI_EVAL_REGION}/recognizers/_:recognize`;
  const stt = await postJson(sttUrl, token, buildRecognizeBody(bytes));
  if (!stt.ok) {
    row.error = `stt_http_${stt.status}`;
    return row;
  }
  row.transcript = joinTranscript(stt.json);
  row.sttConfidence = minConfidence(stt.json);
  row.billedSec = billedSeconds(stt.json);
  row.lowConfidence = row.sttConfidence < LOW_STT_CONFIDENCE_THRESHOLD;
  if (!row.transcript) {
    row.inaudible = true;
    return row;
  }

  const evalUrl = `${AI_EVAL_VERTEX_BASE_URL}/v1/projects/${project}` +
    `/locations/${AI_EVAL_REGION}/publishers/google/models/` +
    `${encodeURIComponent(model)}:generateContent`;
  const body = buildEvaluationRequestBody({
    model,
    rubric,
    promptVersion: 1,
    questionText: question,
    transcript: row.transcript,
    timeoutSec: 60,
  });
  const evalResponse = await postJson(evalUrl, token, body);
  if (!evalResponse.ok) {
    row.evalProblem = `eval_http_${evalResponse.status}`;
    return row;
  }
  const candidate = evalResponse.json.candidates?.[0];
  const finishReason = candidate?.finishReason ?? '';
  if (finishReason === 'SAFETY' || finishReason === 'PROHIBITED_CONTENT' ||
      evalResponse.json.promptFeedback?.blockReason) {
    row.evalProblem = `safety_block(${finishReason ||
      evalResponse.json.promptFeedback?.blockReason})`;
    return row;
  }
  const text = candidate?.content?.parts?.map((p) => p.text ?? '').join('') ?? '';
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    row.evalProblem = 'unparseable_json';
    return row;
  }
  const validation = validateEvalResponse(parsed, rubric);
  if (!validation.ok) {
    row.evalProblem = `schema:${validation.reason}`;
    return row;
  }
  row.evaluation = validation.value;
  return row;
}

async function main() {
  const {values, errors} = parseArgs(process.argv.slice(2));
  if (!values.authorised) {
    console.error(AUTHORISATION_WARNING);
    process.exit(2);
  }
  if (errors.length) {
    console.error(errors.join('\n'));
    process.exit(2);
  }
  const token = process.env.TOKEN;
  if (!token) {
    console.error('TOKEN env required (gcloud auth print-access-token)');
    process.exit(2);
  }
  const project = process.env.PROJECT ?? 'lumi-ninc-au';
  const model = process.env.MODEL ?? AI_EVAL_DEFAULT_MODEL;
  const rubric = rubricForKey('general');

  const dir = path.resolve(values.dir);
  const clips = fs.readdirSync(dir)
    .filter((name) => name.toLowerCase().endsWith('.m4a'))
    .sort();
  if (!clips.length) {
    console.error(`no .m4a clips found in ${dir}`);
    process.exit(2);
  }

  const rows = [];
  for (const fileName of clips) {
    process.stderr.write(`processing ${fileName} ...\n`);
    try {
      rows.push(await processClip({
        filePath: path.join(dir, fileName),
        fileName, token, project, model, rubric,
        question: values.question,
      }));
    } catch (err) {
      rows.push({fileName, error: String(err?.message ?? err)});
    }
  }

  const html = buildReviewSheetHtml({
    generatedAt: new Date().toISOString(),
    model,
    question: values.question,
    rubricKey: rubric.key,
    rubricVersion: RUBRIC_VERSION,
    clipCount: rows.length,
  }, rows);
  const outPath = values.out ?
    path.resolve(values.out) :
    path.join(dir, 'review-sheet.html');
  fs.writeFileSync(outPath, html);
  console.log(`review sheet written: ${outPath}`);
  console.log('open it in a browser from the clips directory so the audio ' +
    'links resolve.');
}

const isDirectRun = process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href;
if (isDirectRun) await main();
