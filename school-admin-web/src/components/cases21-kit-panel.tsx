'use client';

import { Icon } from '@/components/lumi/icon';

/**
 * The CASES21 export kit, offered where admins actually need it — mid-import.
 *
 * Files are served from public/kit/ and mirror docs/cases21/ in the repo, so
 * the query an admin runs is the same one the importer's tests are written
 * against.
 */
export function CASES21KitPanel() {
  return (
    <div>
      <div className="flex items-start gap-2 mb-2">
        <span className="text-section shrink-0 mt-0.5"><Icon name="school" size={18} /></span>
        <div>
          <p className="text-sm font-bold text-ink">Using CASES21?</p>
          <p className="text-sm text-muted">
            Run our query in the CASES21 SQL worksheet and it produces exactly the columns Lumi
            needs — no reformatting. Upload the result here as Excel or CSV.
          </p>
        </div>
      </div>
      <div className="flex items-center gap-4 flex-wrap ml-7">
        <a
          href="/kit/lumi-cases21-export-kit.sql"
          download
          className="text-sm text-section hover:underline font-semibold"
        >
          Download the SQL query
        </a>
        <a
          href="/kit/lumi-cases21-export-guide.html"
          target="_blank"
          rel="noopener noreferrer"
          className="text-sm text-section hover:underline font-semibold"
        >
          Step-by-step guide
        </a>
      </div>
    </div>
  );
}
