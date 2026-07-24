// DRAFT — pending counsel + Nic approval; not in force. DO NOT WIRE IN.
//
// Deploy-inert draft of the school-portal privacy-policy changes for the AI
// comprehension-evaluation feature. This module is intentionally NOT imported
// anywhere: it is not a route, it renders nothing in the built portal, and
// merging it changes no published page. It exists so the approved wording can
// be activated as a one-line import once the collection notice takes effect.
//
// Source of truth for the wording: docs/privacy/AI_EVAL_COLLECTION_NOTICE_DRAFT.md
// (and its approval record). Residency wording below is the tier-2 claim from
// docs/AI_EVALUATION_GEMINI_PLAN.md §6 — upgrade only if the during-ML-processing
// evidence is captured first. Never use the word "anonymised" here.
//
// Activation checklist (do not perform until approved + effective date set):
// 1. Replace EFFECTIVE_DATE_PLACEHOLDER below with the real effective date.
// 2. Resolve the opt-out paragraph against the decided opt-out model
//    (docs/privacy/AI_EVAL_OPT_OUT_DECISION_MEMO.md).
// 3. In src/app/legal/privacy/page.tsx:
//    a. import { AiEvaluationPrivacySectionDraft } from
//       '@/components/legal/ai-evaluation-privacy-section-draft';
//    b. render it between section 3 ("Children's information") and section 4
//       ("When we disclose information"), renumbering later headings;
//    c. update the "Last updated" date on the LegalDocument element;
//    d. in section 6 ("How long we keep information"), add the transcript
//       (90 days) and evaluation (730 days) retention lines mirrored below.
// 4. Rename this file to drop the -draft suffix and delete this checklist.

const SUPPORT_EMAIL = 'support@lumi-reading.com';

const EFFECTIVE_DATE_PLACEHOLDER = '[EFFECTIVE DATE — set on approval]';

export function AiEvaluationPrivacySectionDraft() {
  return (
    <section>
      <h2>AI comprehension evaluation (optional school feature)</h2>
      <p>
        From {EFFECTIVE_DATE_PLACEHOLDER}, where a school has asked us to enable it and has
        notified its families, new comprehension recordings may also be processed by an
        AI-assisted evaluation feature:
      </p>
      <ul>
        <li>
          the recording is converted to text by Google Cloud&rsquo;s speech-to-text service in
          Sydney, Australia;
        </li>
        <li>
          the text of the answer and the teacher&rsquo;s question are evaluated by an AI model
          (Google Gemini on Google Cloud&rsquo;s Vertex AI platform) against a simple
          comprehension rubric; and
        </li>
        <li>
          the result is a short, qualitative, <strong>teacher-only</strong> summary. There are no
          marks, scores or grades, results are never shown to students or parents/carers, and
          AI results are never used for formal assessment.
        </li>
      </ul>
      <p>
        The request sent to the AI service has <strong>no student identifiers attached; content
        may incidentally contain personal information</strong> (for example, a name a child says
        aloud in their answer). We additionally replace the student&rsquo;s registered name with
        &ldquo;[the student]&rdquo; in the text sent to the AI model.
      </p>
      <p>
        The AI summary is decision support for the teacher, who is directed to listen to the
        recording and use their professional judgement before acting on it. Recordings,
        transcripts and evaluations are stored in Google Cloud&rsquo;s Australian (Sydney) region
        and processed via Google Cloud&rsquo;s Sydney regional endpoint; Google&rsquo;s formal
        in-region processing commitment for generative AI in Australia is pending publication.
        No additional company receives student information for this feature, and Google does not
        use this content to train its AI models.
      </p>
      <p>
        Transcripts are removed after 90 days and evaluation summaries are deleted after 730
        days; the recording itself is kept only for the school&rsquo;s existing 30, 90 or 365-day
        deletion period. <strong>No recording made before this feature&rsquo;s effective date is
        ever processed by it.</strong>
      </p>
      <p>
        {/* Decided 20 July 2026: per-family opt-IN (Model C) via a first-use parent
            consent checkbox — wording pending counsel ratification. */}
        This feature is <strong>opt-in</strong>: a parent/carer is asked to agree the first time
        they use a comprehension recording, and without that agreement no AI transcription or
        evaluation ever occurs for that child — recordings simply work as before, with the
        teacher able to listen. A parent/carer can withdraw their agreement at any time via the
        school or <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>, with no effect on the
        rest of the Lumi service.
      </p>
    </section>
  );
}
