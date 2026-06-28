import type { Metadata } from 'next';
import { LegalDocument } from '@/components/legal/legal-document';

export const metadata: Metadata = {
  title: 'Privacy Policy — Lumi',
  description: 'How Lumi collects, uses, and protects personal information.',
};

const SUPPORT_EMAIL = 'support@lumi-reading.com';

export default function PrivacyPolicyPage() {
  return (
    <LegalDocument title="Privacy Policy" lastUpdated="28 June 2026">
      <section>
        <p>
          This Privacy Policy explains how <strong>Lumi</strong> (&ldquo;Lumi&rdquo;, &ldquo;we&rdquo;,
          &ldquo;us&rdquo; or &ldquo;our&rdquo;) collects, uses, discloses and protects personal
          information when you use the Lumi Reading Diary mobile app and related services
          (together, the &ldquo;Service&rdquo;).
        </p>
        <p>
          Lumi is a children&rsquo;s reading-tracking tool provided to schools. We handle most
          information about students on behalf of, and at the direction of, the school that
          enrols them. We are committed to handling personal information in accordance with the{' '}
          <strong>Privacy Act 1988 (Cth)</strong> and the{' '}
          <strong>Australian Privacy Principles (APPs)</strong>.
        </p>
        <p className="text-muted">
          This document is provided in good faith and reflects the Service&rsquo;s actual data
          practices. It is not legal advice; we recommend it be reviewed by the operator and, if a
          registered entity operates Lumi, that the entity&rsquo;s legal name and ABN be inserted here.
        </p>
      </section>

      <section>
        <h2>1. Information we collect</h2>

        <h3>Account information</h3>
        <p>When a teacher, school administrator or parent/carer creates an account, we collect:</p>
        <ul>
          <li>name and the role you hold (parent/carer, teacher or school administrator);</li>
          <li>a mobile phone number (required for parent/carer accounts, and used for sign-in and reminders) and, optionally, an email address;</li>
          <li>for parents/carers, the relationship to the child (e.g. Mum, Dad, Guardian);</li>
          <li>the school and class you are associated with, and the link or school code used to join;</li>
          <li>an optional profile photo and chosen in-app character.</li>
        </ul>
        <p>
          Account passwords are managed by our authentication provider (Google Firebase
          Authentication). We do not see or store your raw password.
        </p>

        <h3>Student information</h3>
        <p>
          Schools and the parents/carers and teachers they authorise enter information about
          students so reading can be tracked. This may include:
        </p>
        <ul>
          <li>the student&rsquo;s name, class and year level, and (optionally) a date of birth and profile photo;</li>
          <li>reading level and the history of reading-level changes;</li>
          <li>reading activity — dates, minutes read, books read, how the child felt about the session, and any notes;</li>
          <li>optional short voice recordings of the child recapping what they read (the &ldquo;comprehension recording&rdquo; feature), where a school has turned this feature on;</li>
          <li>optional photos attached to a reading log;</li>
          <li>messages exchanged between a teacher and a parent/carer about a reading log.</li>
        </ul>

        <h3>Device and technical information</h3>
        <ul>
          <li>a push-notification token, so we can deliver reminders and updates to your device;</li>
          <li>app version, device type and basic diagnostics;</li>
          <li>crash reports and limited product-usage analytics (collected only in production builds) to keep the app reliable and to understand which features are used;</li>
          <li>information you provide when you contact support or send feedback.</li>
        </ul>
      </section>

      <section>
        <h2>2. How we use information</h2>
        <p>We use personal information to:</p>
        <ul>
          <li>provide the Service — record and display reading activity, progress and achievements;</li>
          <li>enable communication between teachers and parents/carers about a child&rsquo;s reading;</li>
          <li>send reading reminders, achievement and comment notifications, and school announcements;</li>
          <li>operate, secure, troubleshoot and improve the app (including crash reporting and aggregate usage analytics);</li>
          <li>verify school enrolment and manage access entitlements; and</li>
          <li>respond to support requests and meet legal obligations.</li>
        </ul>
        <p>
          We do <strong>not</strong> sell personal information, we do <strong>not</strong> use it for
          third-party advertising, and we do <strong>not</strong> track you across other companies&rsquo;
          apps or websites.
        </p>
      </section>

      <section>
        <h2>3. Children&rsquo;s information</h2>
        <p>
          Lumi is designed to be used <em>about</em> children by the adults responsible for them —
          schools, teachers and parents/carers — rather than by young children independently. The
          school is responsible for ensuring it has the appropriate authority and parental consent to
          enter student information into the Service and to enable optional features such as voice
          recordings. Parents/carers can see the reading information for the child or children linked
          to their account. If you believe a child&rsquo;s information has been provided to us without
          proper authority, contact us and we will work with the school to address it.
        </p>
      </section>

      <section>
        <h2>4. When we disclose information</h2>
        <p>We disclose personal information only as needed to run the Service:</p>
        <ul>
          <li>
            <strong>Within the school community:</strong> a child&rsquo;s reading information is visible
            to that child&rsquo;s teachers and school administrators, and to the parents/carers linked to
            the child.
          </li>
          <li>
            <strong>Service providers:</strong> we use Google Firebase (authentication, database,
            file storage, messaging, crash reporting and analytics) to host and operate the Service.
            These providers process data on our behalf under their own security and privacy commitments.
          </li>
          <li>
            <strong>Book look-ups:</strong> to fetch book titles and cover images we may send a book&rsquo;s
            ISBN or title to public book databases (such as Google Books and the Open Library). No
            student information is sent in these look-ups.
          </li>
          <li>
            <strong>Legal reasons:</strong> where required by law, or to protect the rights, safety
            and security of users, the public or Lumi.
          </li>
        </ul>
      </section>

      <section>
        <h2>5. Storage, security and location</h2>
        <p>
          Information is stored using Google Cloud / Firebase infrastructure, with our primary
          database and file storage hosted in <strong>Australia</strong> (the Sydney
          <code> australia-southeast1 </code> region). Information is encrypted in transit and at
          rest, and access is restricted by authentication and security rules so that users can only
          reach the data they are entitled to. Some of our providers&rsquo; supporting systems (for
          example, crash-reporting and analytics processing) may operate outside Australia; where that
          occurs we take reasonable steps to ensure your information is handled consistently with the
          APPs.
        </p>
      </section>

      <section>
        <h2>6. How long we keep information</h2>
        <p>
          We keep personal information for as long as the related account or school relationship is
          active, and as needed to provide the Service. Access to a student&rsquo;s data is tied to the
          school&rsquo;s enrolment and annual renewal. When information is no longer required, or on a
          valid deletion request, we delete it or de-identify it, unless we are required to retain it
          by law.
        </p>
      </section>

      <section>
        <h2>7. Accessing, correcting or deleting your information</h2>
        <p>
          You may request access to, or correction of, the personal information we hold about you.
          Parents/carers can view and update much of their own and their child&rsquo;s information in the
          app, and schools can manage student records directly. To request access, correction, or
          deletion of an account and its associated data, contact us at{' '}
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>. Because data is held on behalf of
          schools, we may need to coordinate a student-data request with the relevant school.
        </p>
      </section>

      <section>
        <h2>8. Push notifications and analytics</h2>
        <p>
          You can turn off push notifications at any time in your device settings. Product-usage
          analytics and crash reporting are collected only in production builds and are used in
          aggregate to improve reliability and usability; they are not used for advertising.
        </p>
      </section>

      <section>
        <h2>9. Changes to this policy</h2>
        <p>
          We may update this Privacy Policy from time to time. When we do, we will revise the
          &ldquo;Last updated&rdquo; date above and, where appropriate, notify you in the app.
        </p>
      </section>

      <section>
        <h2>10. Contact us and complaints</h2>
        <p>
          If you have a question about this policy, or wish to make a privacy complaint, contact us
          at <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>. We will acknowledge your
          complaint and respond within a reasonable period. If you are not satisfied with our
          response, you may contact the Office of the Australian Information Commissioner (OAIC) at{' '}
          <a href="https://www.oaic.gov.au" target="_blank" rel="noopener noreferrer">oaic.gov.au</a>.
        </p>
      </section>
    </LegalDocument>
  );
}
