/**
 * Official government/public-school term dates per Australian state, used as
 * the fallback when a school hasn't entered (or only partially entered) its
 * own term dates — see term_dates_fallback.ts.
 *
 * Student attendance dates from each education department's published
 * calendar (staff-only development days excluded where the state
 * distinguishes them). NSW = Eastern division. Verified 2026-07-14 against:
 *   VIC vic.gov.au/school-term-dates-and-holidays-victoria
 *   NSW education.nsw.gov.au/schooling/calendars
 *   QLD education.qld.gov.au/about-us/calendar/term-dates
 *   SA  education.sa.gov.au/students/term-dates-south-australian-state-schools
 *   WA  education.wa.edu.au/future-term-dates
 *   TAS decyp.tas.gov.au/learning/term-dates
 *   NT  nt.gov.au/learning/primary-and-secondary-students/school-term-dates-in-nt
 *   ACT act.gov.au ACT school term dates 2026-30 PDF
 *
 * Yearly upkeep: add the next year here (redeploy), or hot-add it without a
 * deploy via the platformConfig/stateTermDates override doc — entries there
 * win over this bundled table year-by-year. The applyStateTermDates cron
 * warns from 1 October when the coming year is missing from both.
 */

export interface StateTermEntry {
  term: number;
  start: string; // inclusive "YYYY-MM-DD", first day students attend
  end: string; // inclusive "YYYY-MM-DD", last day of term
}

export type StateTermTable = {
  [year: string]: {[state: string]: StateTermEntry[]};
};

export const AU_STATE_TERM_DATES: StateTermTable = {
  "2026": {
    VIC: [
      {term: 1, start: "2026-01-28", end: "2026-04-02"},
      {term: 2, start: "2026-04-20", end: "2026-06-26"},
      {term: 3, start: "2026-07-13", end: "2026-09-18"},
      {term: 4, start: "2026-10-05", end: "2026-12-18"},
    ],
    NSW: [
      {term: 1, start: "2026-02-02", end: "2026-04-02"},
      {term: 2, start: "2026-04-22", end: "2026-07-03"},
      {term: 3, start: "2026-07-21", end: "2026-09-25"},
      {term: 4, start: "2026-10-13", end: "2026-12-17"},
    ],
    QLD: [
      {term: 1, start: "2026-01-27", end: "2026-04-02"},
      {term: 2, start: "2026-04-20", end: "2026-06-26"},
      {term: 3, start: "2026-07-13", end: "2026-09-18"},
      {term: 4, start: "2026-10-06", end: "2026-12-11"},
    ],
    SA: [
      {term: 1, start: "2026-01-27", end: "2026-04-10"},
      {term: 2, start: "2026-04-27", end: "2026-07-03"},
      {term: 3, start: "2026-07-20", end: "2026-09-25"},
      {term: 4, start: "2026-10-12", end: "2026-12-11"},
    ],
    WA: [
      {term: 1, start: "2026-02-02", end: "2026-04-02"},
      {term: 2, start: "2026-04-20", end: "2026-07-03"},
      {term: 3, start: "2026-07-20", end: "2026-09-25"},
      {term: 4, start: "2026-10-12", end: "2026-12-17"},
    ],
    TAS: [
      {term: 1, start: "2026-02-05", end: "2026-04-17"},
      {term: 2, start: "2026-05-04", end: "2026-07-10"},
      {term: 3, start: "2026-07-27", end: "2026-10-02"},
      {term: 4, start: "2026-10-19", end: "2026-12-18"},
    ],
    NT: [
      {term: 1, start: "2026-01-29", end: "2026-04-02"},
      {term: 2, start: "2026-04-14", end: "2026-06-19"},
      {term: 3, start: "2026-07-14", end: "2026-09-18"},
      {term: 4, start: "2026-10-06", end: "2026-12-10"},
    ],
    ACT: [
      {term: 1, start: "2026-01-30", end: "2026-04-02"},
      {term: 2, start: "2026-04-21", end: "2026-07-03"},
      {term: 3, start: "2026-07-21", end: "2026-09-25"},
      {term: 4, start: "2026-10-13", end: "2026-12-18"},
    ],
  },
  "2027": {
    VIC: [
      {term: 1, start: "2027-01-28", end: "2027-03-25"},
      {term: 2, start: "2027-04-12", end: "2027-06-25"},
      {term: 3, start: "2027-07-12", end: "2027-09-17"},
      {term: 4, start: "2027-10-04", end: "2027-12-17"},
    ],
    NSW: [
      {term: 1, start: "2027-01-28", end: "2027-04-09"},
      {term: 2, start: "2027-04-27", end: "2027-07-02"},
      {term: 3, start: "2027-07-19", end: "2027-09-24"},
      {term: 4, start: "2027-10-11", end: "2027-12-20"},
    ],
    QLD: [
      {term: 1, start: "2027-01-27", end: "2027-03-25"},
      {term: 2, start: "2027-04-12", end: "2027-06-25"},
      {term: 3, start: "2027-07-12", end: "2027-09-17"},
      {term: 4, start: "2027-10-05", end: "2027-12-10"},
    ],
    SA: [
      {term: 1, start: "2027-01-27", end: "2027-04-09"},
      {term: 2, start: "2027-04-26", end: "2027-07-02"},
      {term: 3, start: "2027-07-19", end: "2027-09-24"},
      {term: 4, start: "2027-10-11", end: "2027-12-10"},
    ],
    WA: [
      {term: 1, start: "2027-02-01", end: "2027-04-09"},
      {term: 2, start: "2027-04-26", end: "2027-07-02"},
      {term: 3, start: "2027-07-19", end: "2027-09-24"},
      {term: 4, start: "2027-10-11", end: "2027-12-16"},
    ],
    TAS: [
      {term: 1, start: "2027-02-04", end: "2027-04-09"},
      {term: 2, start: "2027-04-26", end: "2027-07-02"},
      {term: 3, start: "2027-07-19", end: "2027-09-24"},
      {term: 4, start: "2027-10-11", end: "2027-12-16"},
    ],
    NT: [
      {term: 1, start: "2027-01-27", end: "2027-04-02"},
      {term: 2, start: "2027-04-13", end: "2027-06-18"},
      {term: 3, start: "2027-07-13", end: "2027-09-17"},
      {term: 4, start: "2027-10-05", end: "2027-12-09"},
    ],
    ACT: [
      {term: 1, start: "2027-02-01", end: "2027-04-09"},
      {term: 2, start: "2027-04-28", end: "2027-07-02"},
      {term: 3, start: "2027-07-20", end: "2027-09-24"},
      {term: 4, start: "2027-10-12", end: "2027-12-17"},
    ],
  },
};
