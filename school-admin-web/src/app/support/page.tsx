import type { Metadata } from 'next';
import { LegalDocument } from '@/components/legal/legal-document';

export const metadata: Metadata = {
  title: 'Support — Lumi',
  description: 'Get help with the Lumi Reading Diary app, and how to manage or delete your account.',
};

const SUPPORT_EMAIL = 'support@lumi-reading.com';

export default function SupportPage() {
  return (
    <LegalDocument title="Support" lastUpdated="28 June 2026">
      <section>
        <p>
          <strong>Lumi Reading Diary</strong> helps schools and families track and celebrate
          children&rsquo;s reading. If you need help, we&rsquo;re here.
        </p>
        <p>
          Email us at <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a> and we&rsquo;ll get back to
          you as soon as we can. Please include your name, your school, and a short description of the
          issue (and screenshots if you have them).
        </p>
      </section>

      <section>
        <h2>Who to contact</h2>
        <ul>
          <li>
            <strong>Parents and carers:</strong> for help joining your child, logging reading, or a
            question about your child&rsquo;s reading record, contact your child&rsquo;s school first — they
            manage classes, students and access. For app problems, email{' '}
            <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
          </li>
          <li>
            <strong>Teachers and schools:</strong> email{' '}
            <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a> for help with classes, students,
            book allocations, or access and renewals.
          </li>
        </ul>
      </section>

      <section>
        <h2>Getting started</h2>
        <ul>
          <li>
            <strong>Schools and teachers</strong> are set up with a school code and can manage classes
            and students from the app or the school portal.
          </li>
          <li>
            <strong>Parents and carers</strong> join using a link code provided by the school, then log
            reading sessions for their child — choosing the book(s), minutes read, and how the session
            went.
          </li>
          <li>
            The optional <strong>comprehension recording</strong> (a short voice recap by the child) is
            only available when a school turns it on.
          </li>
        </ul>
      </section>

      <section>
        <h2>Delete your account or data</h2>
        <p>
          You can ask us to delete your account and its associated personal information at any time.
          Email <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a> from the email address or with
          the phone number on your account, with the subject &ldquo;Delete my account&rdquo;, and tell us:
        </p>
        <ul>
          <li>your name and role (parent/carer, teacher or school administrator);</li>
          <li>your school; and</li>
          <li>whether you want only your account removed, or also a child&rsquo;s records you are responsible for.</li>
        </ul>
        <p>
          We will verify your request and delete the relevant account and personal information,
          except anything we are required to keep by law. Because student records are held on behalf
          of schools, a request to delete a student&rsquo;s records may be coordinated with the relevant
          school. We aim to action deletion requests within 30 days.
        </p>
      </section>

      <section>
        <h2>More information</h2>
        <p>
          See our <a href="/legal/privacy">Privacy Policy</a> and{' '}
          <a href="/legal/terms">Terms of Use</a>.
        </p>
      </section>
    </LegalDocument>
  );
}
