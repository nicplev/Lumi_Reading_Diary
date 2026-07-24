import type { Metadata } from 'next';
import { LegalDocument } from '@/components/legal/legal-document';

export const metadata: Metadata = {
  title: 'Terms of Use — Lumi',
  description: 'The terms governing your use of the Lumi Reading Diary app.',
};

const SUPPORT_EMAIL = 'support@lumi-reading.com';

export default function TermsOfUsePage() {
  return (
    <LegalDocument title="Terms of Use" lastUpdated="28 June 2026">
      <section>
        <p>
          These Terms of Use (&ldquo;Terms&rdquo;) are an agreement between you and{' '}
          <strong>Lumi</strong> (&ldquo;Lumi&rdquo;, &ldquo;we&rdquo;, &ldquo;us&rdquo;) and govern your
          use of the Lumi Reading Diary mobile app and related services (the &ldquo;Service&rdquo;). By
          downloading, accessing or using the Service, you agree to these Terms. If you do not agree,
          do not use the Service. These Terms also serve as the end-user licence agreement (EULA) for
          the app.
        </p>
        <p className="text-muted">
          This document reflects the Service&rsquo;s actual operation. It is not legal advice; we
          recommend review by the operator before publication and insertion of the operating
          entity&rsquo;s legal name where applicable.
        </p>
      </section>

      <section>
        <h2>1. Who may use the Service</h2>
        <p>
          The Service is provided to schools and to the teachers, school administrators and
          parents/carers they authorise. You must be at least 18 years old to create an account.
          Accounts are for adults; the Service is used <em>about</em> children by the responsible
          adults, and any use by a child must be supervised by a parent/carer or teacher. You are
          responsible for keeping your account credentials secure and for activity under your account.
        </p>
      </section>

      <section>
        <h2>2. Access through your school</h2>
        <p>
          Access to student information and reading features depends on a current school enrolment and
          entitlement. Entitlements are arranged between schools and Lumi (including through reading
          book packs and annual renewals). If a school&rsquo;s arrangement ends or a student&rsquo;s access
          lapses, access to the related features may be suspended or removed.
        </p>
      </section>

      <section>
        <h2>3. Licence</h2>
        <p>
          Subject to these Terms, Lumi grants you a limited, non-exclusive, non-transferable,
          revocable licence to install and use the app on a device you own or control, solely for the
          purpose of tracking and supporting children&rsquo;s reading. You must not copy, modify,
          distribute, sell, lease, reverse-engineer or attempt to extract the source code of the app,
          except to the extent this restriction is prohibited by law.
        </p>
      </section>

      <section>
        <h2>4. Acceptable use</h2>
        <p>You agree not to:</p>
        <ul>
          <li>use the Service for any unlawful purpose or in breach of any school policy;</li>
          <li>access or attempt to access data you are not authorised to view;</li>
          <li>upload content that is unlawful, harmful, or infringes another person&rsquo;s rights;</li>
          <li>interfere with, disrupt, or compromise the security or integrity of the Service; or</li>
          <li>misrepresent your identity or your authority to act for a child or school.</li>
        </ul>
      </section>

      <section>
        <h2>5. Your content</h2>
        <p>
          You and your school may add content such as reading logs, notes, photos and voice
          recordings (&ldquo;User Content&rdquo;). You retain your rights in User Content. You grant Lumi
          a licence to host, store, process and display User Content as necessary to operate the
          Service (for example, showing a reading log to the relevant teacher and linked
          parents/carers). You are responsible for ensuring you have the right and any necessary
          consent to provide User Content, including content about a child.
        </p>
      </section>

      <section>
        <h2>6. Privacy</h2>
        <p>
          Our handling of personal information is described in our{' '}
          <a href="/legal/privacy">Privacy Policy</a>, which forms part of these Terms.
        </p>
      </section>

      <section>
        <h2>7. Intellectual property</h2>
        <p>
          The Service, including its software, design, text, graphics and the Lumi name and logo, is
          owned by Lumi or its licensors and is protected by intellectual-property laws. Except for
          the licence granted above, no rights are transferred to you.
        </p>
      </section>

      <section>
        <h2>8. Third-party services</h2>
        <p>
          The Service relies on third-party services, including Google Firebase (hosting,
          authentication, storage, messaging, analytics and crash reporting) and public book
          databases such as Google Books and the Open Library. Your use of the Service may be subject
          to those providers&rsquo; terms. The app is distributed through the Apple App Store, and your
          use is also subject to the App Store Terms of Service.
        </p>
      </section>

      <section>
        <h2>9. Australian Consumer Law</h2>
        <p>
          Nothing in these Terms excludes, restricts or modifies any guarantee, right or remedy you
          may have under the <strong>Australian Consumer Law</strong> or other laws that cannot be
          lawfully excluded. To the extent permitted by law, our liability for failure to comply with
          a non-excludable guarantee is limited, at our option, to re-supplying the Service or paying
          the cost of having it re-supplied.
        </p>
      </section>

      <section>
        <h2>10. Disclaimers and limitation of liability</h2>
        <p>
          Except for rights and guarantees that cannot be excluded by law, the Service is provided on
          an &ldquo;as is&rdquo; and &ldquo;as available&rdquo; basis without warranties of any kind. To
          the maximum extent permitted by law, Lumi is not liable for any indirect, incidental or
          consequential loss arising out of your use of, or inability to use, the Service.
        </p>
      </section>

      <section>
        <h2>11. Suspension and termination</h2>
        <p>
          We may suspend or terminate access to the Service if you breach these Terms, if required for
          security or legal reasons, or if your school&rsquo;s arrangement ends. You may stop using the
          Service at any time and may request deletion of your account as described in our{' '}
          <a href="/support">Support</a> page.
        </p>
      </section>

      <section>
        <h2>12. Apple App Store terms</h2>
        <p>
          The following applies because the app is provided through the Apple App Store:
        </p>
        <ul>
          <li>These Terms are between you and Lumi only, not with Apple. Apple is not responsible for the app or its content.</li>
          <li>Apple has no obligation to provide any maintenance or support for the app.</li>
          <li>To the extent permitted by law, Apple has no warranty obligation with respect to the app; any claims arising from a failure to conform to a warranty are our responsibility, not Apple&rsquo;s.</li>
          <li>Apple is not responsible for addressing any claims by you or a third party relating to the app, including product-liability, regulatory, or intellectual-property claims.</li>
          <li>You represent that you are not located in a country subject to a U.S. Government embargo and are not on any U.S. Government list of prohibited or restricted parties.</li>
          <li>Apple and its subsidiaries are third-party beneficiaries of these Terms and may enforce them against you.</li>
        </ul>
      </section>

      <section>
        <h2>13. Changes to these Terms</h2>
        <p>
          We may update these Terms from time to time. When we do, we will revise the &ldquo;Last
          updated&rdquo; date above and, where appropriate, notify you in the app. Continued use of the
          Service after changes take effect means you accept the updated Terms.
        </p>
      </section>

      <section>
        <h2>14. Governing law</h2>
        <p>
          These Terms are governed by the laws of Australia and the State or Territory in which Lumi
          operates, and you submit to the non-exclusive jurisdiction of the courts of that place.
        </p>
      </section>

      <section>
        <h2>15. Contact</h2>
        <p>
          Questions about these Terms can be sent to{' '}
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
        </p>
      </section>
    </LegalDocument>
  );
}
