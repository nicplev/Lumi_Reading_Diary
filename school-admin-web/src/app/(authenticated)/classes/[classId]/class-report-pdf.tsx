'use client';

// Loaded only via dynamic import (on the Download PDF click), so @react-pdf
// stays out of the main bundle and never runs during SSR/build.
import { Document, Page, Text, View, Image, StyleSheet, pdf } from '@react-pdf/renderer';
import type { ClassReport } from '@/lib/firestore/reports';

// Lumi palette — kept in sync with school-admin-web/src/app/globals.css.
// @react-pdf can't read CSS vars, so the brand colours live here as literals.
const C = {
  red: '#EC4544',
  redDark: '#D63A39',
  tintRed: '#F4B5B7',
  yellow: '#FFCB05',
  tintYellow: '#FBE89F',
  green: '#51BA65',
  tintGreen: '#B5DAB8',
  blue: '#56C8E6',
  tintBlue: '#C8E8F1',
  orange: '#FAA51A',
  tintOrange: '#FED8A8',
  cream: '#F7F5F0',
  paper: '#FFFFFF',
  ink: '#1A1A1A',
  muted: '#6B6B6B',
  rule: '#E5E2DC',
  white: '#FFFFFF',
};

const styles = StyleSheet.create({
  page: { padding: 28, paddingBottom: 44, fontSize: 10, color: C.ink, fontFamily: 'Helvetica' },

  // Branded header band + sub-strip
  header: {
    backgroundColor: C.red,
    borderRadius: 10,
    paddingVertical: 14,
    paddingHorizontal: 16,
    flexDirection: 'row',
    alignItems: 'center',
  },
  logo: {
    width: 42,
    height: 42,
    borderRadius: 8,
    backgroundColor: C.white,
    objectFit: 'contain',
    marginRight: 12,
  },
  headerSchool: { fontSize: 9, color: C.white, opacity: 0.9, marginBottom: 2 },
  headerTitle: { fontSize: 18, color: C.white, fontFamily: 'Helvetica-Bold' },
  headerBrandWrap: { flexDirection: 'row', alignItems: 'center' },
  headerChar: { width: 34, height: 34, objectFit: 'contain', marginRight: 5 },
  headerBrand: { fontSize: 19, color: C.white, fontFamily: 'Helvetica-Bold' },
  subBar: { marginTop: 8, marginBottom: 10 },
  subBarText: { fontSize: 9.5, color: C.muted },

  // Plain-language summary
  summaryBox: { backgroundColor: C.cream, borderRadius: 8, padding: 9, marginBottom: 12 },
  summaryText: { fontSize: 9.5, color: C.ink, lineHeight: 1.35 },

  // Bento metric tiles
  metricsRow: { flexDirection: 'row', flexWrap: 'wrap', marginBottom: 6 },
  metricOuter: { width: '25%', padding: 3 },
  metricBox: { borderRadius: 8, padding: 9, minHeight: 50 },
  metricValue: { fontSize: 15, fontFamily: 'Helvetica-Bold', color: C.ink },
  metricLabel: { fontSize: 7.5, color: C.ink, opacity: 0.75, textTransform: 'uppercase', marginTop: 3, fontFamily: 'Helvetica-Bold' },
  metricSub: { fontSize: 7.5, color: C.ink, opacity: 0.6, marginTop: 1, fontFamily: 'Helvetica-Bold' },

  // Legend under the metrics
  legend: { fontSize: 8, color: C.muted, marginBottom: 12 },

  // Sections
  section: { marginBottom: 14 },
  sectionHead: { flexDirection: 'row', alignItems: 'center', marginBottom: 6 },
  sectionDot: { width: 11, height: 11, borderRadius: 3, marginRight: 6 },
  sectionTitle: { fontSize: 12.5, fontFamily: 'Helvetica-Bold', color: C.ink },
  sectionNote: { fontSize: 8, color: C.muted, marginBottom: 6 },

  // Tables
  headRow: {
    flexDirection: 'row',
    backgroundColor: C.cream,
    borderRadius: 5,
    paddingVertical: 4,
    paddingHorizontal: 4,
  },
  row: { flexDirection: 'row', borderBottom: `1 solid ${C.rule}`, paddingVertical: 3, paddingHorizontal: 4 },
  th: { fontSize: 8.5, color: C.muted, fontFamily: 'Helvetica-Bold' },
  cell: { fontSize: 9.5 },
  cellBold: { fontSize: 9.5, fontFamily: 'Helvetica-Bold' },
  totalsRow: { flexDirection: 'row', borderTop: `1.5 solid ${C.rule}`, paddingVertical: 4, paddingHorizontal: 4 },
  totalsCell: { fontSize: 9.5, fontFamily: 'Helvetica-Bold' },

  // Rank badges (gold / silver / bronze)
  rankBadge: { width: 14, height: 14, borderRadius: 7, alignItems: 'center', justifyContent: 'center' },
  rankText: { fontSize: 8, fontFamily: 'Helvetica-Bold' },

  // Level distribution bars
  levelRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 5 },
  levelName: { fontSize: 9.5, width: 90 },
  levelTrack: { flex: 1, height: 7, borderRadius: 4, backgroundColor: C.cream, marginHorizontal: 6 },
  levelFill: { height: 7, borderRadius: 4, backgroundColor: C.green },
  levelCount: { fontSize: 8.5, color: C.muted, width: 24, textAlign: 'right' },

  footer: {
    position: 'absolute',
    bottom: 22,
    left: 28,
    right: 28,
    fontSize: 8,
    color: C.muted,
    textAlign: 'center',
    borderTop: `1 solid ${C.red}`,
    paddingTop: 6,
  },
});

// Metric tiles: soft brand tint per metric so the PDF reads like the on-screen
// bento grid rather than a monochrome sheet.
type Tile = { label: string; value: string | number; bg: string; sub?: string };

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}

function rankColors(i: number): { bg: string; fg: string } {
  if (i === 0) return { bg: C.yellow, fg: C.ink };
  if (i === 1) return { bg: C.rule, fg: C.ink };
  if (i === 2) return { bg: C.orange, fg: C.white };
  return { bg: 'transparent', fg: C.muted };
}

// One plain-language sentence — mirrors buildSummary() in class-report-tab.tsx.
function summarySentence(report: ClassReport): string {
  const parts: string[] = [
    `${report.activeReaders} of ${report.totalStudents} student${report.totalStudents === 1 ? '' : 's'} read this period`,
    report.needsSupport.length > 0
      ? `${report.needsSupport.length} need${report.needsSupport.length === 1 ? 's' : ''} support`
      : 'everyone is engaged',
    `averaging ${report.avgMinutesPerStudent} min and ${report.avgReadingDaysPerStudent} days each`,
  ];
  if (report.topReaders.length > 0) parts.push(`top reader: ${report.topReaders[0].name}`);
  return `${parts.join(' · ')}.`;
}

function SectionHead({ color, title }: { color: string; title: string }) {
  return (
    <View style={styles.sectionHead}>
      <View style={[styles.sectionDot, { backgroundColor: color }]} />
      <Text style={styles.sectionTitle}>{title}</Text>
    </View>
  );
}

function ClassReportDocument({
  report,
  schoolName,
  levelsEnabled,
  logo,
  character,
  goal,
}: {
  report: ClassReport;
  schoolName?: string;
  levelsEnabled?: boolean;
  logo?: string | null;
  /** Data-URL of the Lumi brand character shown in the header. */
  character?: string | null;
  /** The class's daily reading goal (minutes) — clarifies "Met daily goal". */
  goal: number;
}) {
  const generatedOn = new Date().toLocaleDateString();

  const tiles: Tile[] = [
    { label: 'Students', value: report.totalStudents, bg: C.tintBlue },
    { label: 'Active readers', value: `${report.activeReaders}/${report.totalStudents}`, sub: `${report.engagementRate}% engaged`, bg: C.tintGreen },
    { label: 'Met daily goal', value: `${report.targetMetRate}%`, sub: `of the ${goal} min/day goal`, bg: C.tintYellow },
    { label: 'Total minutes', value: report.totalMinutes, bg: C.tintBlue },
    { label: 'Avg min/student', value: report.avgMinutesPerStudent, bg: C.tintGreen },
    { label: 'Avg days/student', value: report.avgReadingDaysPerStudent, bg: C.tintOrange },
    { label: 'Sessions', value: report.totalSessions, bg: C.tintRed },
    { label: 'Books read', value: report.totalBooks, bg: C.tintRed },
  ];

  // Roster column widths — with an extra Level column when levels are enabled.
  const col = levelsEnabled
    ? { name: '30%', min: '12%', sess: '12%', days: '9%', met: '13%', last: '14%', level: '10%' }
    : { name: '34%', min: '13%', sess: '13%', days: '10%', met: '14%', last: '16%', level: '0%' };

  return (
    <Document title={`Class Reading Report — ${report.className}`}>
      <Page size="A4" style={styles.page}>
        {/* Branded header band */}
        <View style={styles.header}>
          {logo ? <Image src={logo} style={styles.logo} /> : null}
          <View style={{ flex: 1 }}>
            {schoolName ? <Text style={styles.headerSchool}>{schoolName}</Text> : null}
            <Text style={styles.headerTitle}>Class Reading Report</Text>
          </View>
          <View style={styles.headerBrandWrap}>
            {character ? <Image src={character} style={styles.headerChar} /> : null}
            <Text style={styles.headerBrand}>LUMI</Text>
          </View>
        </View>
        <View style={styles.subBar}>
          <Text style={styles.subBarText}>
            {[report.className, report.yearLevel].filter(Boolean).join(' · ')} · {fmtDate(report.from)} – {fmtDate(report.to)} · Daily goal: {goal} min
          </Text>
        </View>

        {/* Plain-language summary */}
        <View style={styles.summaryBox}>
          <Text style={styles.summaryText}>
            <Text style={{ fontFamily: 'Helvetica-Bold' }}>Summary. </Text>
            {summarySentence(report)}
          </Text>
        </View>

        {/* Bento metrics */}
        <View style={styles.metricsRow}>
          {tiles.map((t) => (
            <View style={styles.metricOuter} key={t.label}>
              <View style={[styles.metricBox, { backgroundColor: t.bg }]}>
                <Text style={styles.metricValue}>{String(t.value)}</Text>
                <Text style={styles.metricLabel}>{t.label}</Text>
                {t.sub ? <Text style={styles.metricSub}>{t.sub}</Text> : null}
              </View>
            </View>
          ))}
        </View>
        <Text style={styles.legend}>
          Met daily goal = students who read at least the {goal}-minute daily goal on 70%+ of the days they logged. Reading levels are current (as of today).
        </Text>

        {/* Top readers */}
        <View style={styles.section}>
          <SectionHead color={C.yellow} title="Top readers" />
          {report.topReaders.length === 0 ? (
            <Text style={styles.cell}>No reading recorded in this period.</Text>
          ) : (
            <View>
              <View style={styles.headRow}>
                <Text style={[styles.th, { width: '10%' }]}>#</Text>
                <Text style={[styles.th, { width: '50%' }]}>Student</Text>
                <Text style={[styles.th, { width: '15%', textAlign: 'right' }]}>Minutes</Text>
                <Text style={[styles.th, { width: '12%', textAlign: 'right' }]}>Days</Text>
                <Text style={[styles.th, { width: '13%', textAlign: 'right' }]}>Books</Text>
              </View>
              {report.topReaders.map((r, i) => {
                const rc = rankColors(i);
                return (
                  <View style={styles.row} key={r.id}>
                    <View style={{ width: '10%' }}>
                      <View style={[styles.rankBadge, { backgroundColor: rc.bg }]}>
                        <Text style={[styles.rankText, { color: rc.fg }]}>{i + 1}</Text>
                      </View>
                    </View>
                    <Text style={[styles.cellBold, { width: '50%' }]}>{r.name}</Text>
                    <Text style={[styles.cell, { width: '15%', textAlign: 'right' }]}>{r.minutes}</Text>
                    <Text style={[styles.cell, { width: '12%', textAlign: 'right' }]}>{r.readingDays}</Text>
                    <Text style={[styles.cell, { width: '13%', textAlign: 'right' }]}>{r.books}</Text>
                  </View>
                );
              })}
            </View>
          )}
        </View>

        {/* Keep an eye on — the "silent middle" (50–69% met target). */}
        {report.watchList.length > 0 && (
          <View style={styles.section}>
            <SectionHead color={C.orange} title="Keep an eye on" />
            <Text style={styles.sectionNote}>Reading regularly, but meeting their goal on only 50–69% of sessions.</Text>
            <View>
              <View style={styles.headRow}>
                <Text style={[styles.th, { width: '52%' }]}>Student</Text>
                <Text style={[styles.th, { width: '16%', textAlign: 'right' }]}>Minutes</Text>
                <Text style={[styles.th, { width: '14%', textAlign: 'right' }]}>Days</Text>
                <Text style={[styles.th, { width: '18%', textAlign: 'right' }]}>Met target</Text>
              </View>
              {report.watchList.map((r) => (
                <View style={styles.row} key={r.id}>
                  <Text style={[styles.cellBold, { width: '52%' }]}>{r.name}</Text>
                  <Text style={[styles.cell, { width: '16%', textAlign: 'right' }]}>{r.minutes}</Text>
                  <Text style={[styles.cell, { width: '14%', textAlign: 'right' }]}>{r.readingDays}</Text>
                  <Text style={[styles.cell, { width: '18%', textAlign: 'right' }]}>{r.metPct}%</Text>
                </View>
              ))}
            </View>
          </View>
        )}

        {/* Needs support */}
        <View style={styles.section}>
          <SectionHead color={C.red} title="Students needing support" />
          {report.needsSupport.length === 0 ? (
            <Text style={styles.cell}>All students are actively engaged in reading.</Text>
          ) : (
            <View>
              <View style={styles.headRow}>
                <Text style={[styles.th, { width: '50%' }]}>Student</Text>
                <Text style={[styles.th, { width: '17%', textAlign: 'right' }]}>Minutes</Text>
                <Text style={[styles.th, { width: '13%', textAlign: 'right' }]}>Days</Text>
                <Text style={[styles.th, { width: '20%' }]}>Issue</Text>
              </View>
              {report.needsSupport.map((r) => (
                <View style={styles.row} key={r.id}>
                  <Text style={[styles.cellBold, { width: '50%' }]}>{r.name}</Text>
                  <Text style={[styles.cell, { width: '17%', textAlign: 'right' }]}>{r.minutes}</Text>
                  <Text style={[styles.cell, { width: '13%', textAlign: 'right' }]}>{r.readingDays}</Text>
                  <Text style={[styles.cell, { width: '20%', color: C.redDark }]}>{r.issue}</Text>
                </View>
              ))}
            </View>
          )}
        </View>

        {/* All students — header repeats across page breaks; totals row at the end. */}
        <View style={styles.section}>
          <SectionHead color={C.blue} title="All students" />
          {report.students.length === 0 ? (
            <Text style={styles.cell}>No students in this class.</Text>
          ) : (
            <View>
              <View style={styles.headRow} fixed>
                <Text style={[styles.th, { width: col.name }]}>Student</Text>
                <Text style={[styles.th, { width: col.min, textAlign: 'right' }]}>Minutes</Text>
                <Text style={[styles.th, { width: col.sess, textAlign: 'right' }]}>Sessions</Text>
                <Text style={[styles.th, { width: col.days, textAlign: 'right' }]}>Days</Text>
                <Text style={[styles.th, { width: col.met, textAlign: 'right' }]}>Met target</Text>
                <Text style={[styles.th, { width: col.last, textAlign: 'right' }]}>Last read</Text>
                {levelsEnabled && <Text style={[styles.th, { width: col.level, textAlign: 'right' }]}>Level</Text>}
              </View>
              {report.students.map((r, i) => (
                <View style={[styles.row, i % 2 === 1 ? { backgroundColor: C.cream } : {}]} key={r.id} wrap={false}>
                  <Text style={[styles.cellBold, { width: col.name }]}>{r.name}</Text>
                  <Text style={[styles.cell, { width: col.min, textAlign: 'right' }]}>{r.minutes}</Text>
                  <Text style={[styles.cell, { width: col.sess, textAlign: 'right' }]}>{r.sessions}</Text>
                  <Text style={[styles.cell, { width: col.days, textAlign: 'right' }]}>{r.readingDays}</Text>
                  <Text style={[styles.cell, { width: col.met, textAlign: 'right' }]}>{r.sessions > 0 ? `${r.metPct}%` : '—'}</Text>
                  <Text style={[styles.cell, { width: col.last, textAlign: 'right' }]}>{r.lastRead ? fmtDate(r.lastRead) : '—'}</Text>
                  {levelsEnabled && (
                    <Text style={[styles.cell, { width: col.level, textAlign: 'right' }]}>{r.currentReadingLevel ?? '—'}</Text>
                  )}
                </View>
              ))}
              <View style={styles.totalsRow}>
                <Text style={[styles.totalsCell, { width: col.name }]}>Class total</Text>
                <Text style={[styles.totalsCell, { width: col.min, textAlign: 'right' }]}>{report.totalMinutes}</Text>
                <Text style={[styles.totalsCell, { width: col.sess, textAlign: 'right' }]}>{report.totalSessions}</Text>
                <Text style={[styles.totalsCell, { width: col.days, textAlign: 'right' }]}>{report.totalReadingDays}</Text>
                <Text style={[styles.totalsCell, { width: col.met, textAlign: 'right' }]}>{report.targetMetRate}%</Text>
                <Text style={[styles.totalsCell, { width: col.last, textAlign: 'right' }]}>—</Text>
                {levelsEnabled && <Text style={[styles.totalsCell, { width: col.level, textAlign: 'right' }]}>—</Text>}
              </View>
            </View>
          )}
        </View>

        {/* Current reading levels (snapshot as of today) */}
        {levelsEnabled && (
          <View style={styles.section}>
            <SectionHead color={C.green} title="Current reading levels" />
            <Text style={styles.sectionNote}>A snapshot as of today — not limited to the selected period.</Text>
            {report.levelDistribution.length === 0 ? (
              <Text style={styles.cell}>No students in this class.</Text>
            ) : (
              report.levelDistribution.map((l) => {
                const pct = report.totalStudents > 0 ? Math.round((l.count / report.totalStudents) * 100) : 0;
                return (
                  <View style={styles.levelRow} key={l.level}>
                    <Text style={styles.levelName}>{l.level}</Text>
                    <View style={styles.levelTrack}>
                      <View style={[styles.levelFill, { width: `${pct}%` }]} />
                    </View>
                    <Text style={styles.levelCount}>{l.count}</Text>
                  </View>
                );
              })
            )}
            {report.popularLevel && (
              <Text style={[styles.sectionNote, { marginTop: 4, marginBottom: 0 }]}>
                Most common level: {report.popularLevel}
                {report.longestStreak > 0 ? ` · Longest streak (all-time): ${report.longestStreak} days` : ''}
              </Text>
            )}
          </View>
        )}

        <Text
          style={styles.footer}
          fixed
          render={({ pageNumber, totalPages }) => `Generated by Lumi · ${generatedOn} · Page ${pageNumber} of ${totalPages}`}
        />
      </Page>
    </Document>
  );
}

// Fetch an image and inline it as a data URL. @react-pdf's <Image> can choke on
// a cross-origin URL (CORS) and cannot render SVG, so we fetch the bytes
// ourselves and skip anything that isn't a raster image. Any failure degrades
// gracefully (logo-less / character-less but still branded) header.
async function imageToDataUrl(url: string): Promise<string | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const blob = await res.blob();
    if (!blob.type.startsWith('image/') || blob.type.includes('svg')) return null;
    return await new Promise<string | null>((resolve) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(typeof reader.result === 'string' ? reader.result : null);
      reader.onerror = () => resolve(null);
      reader.readAsDataURL(blob);
    });
  } catch {
    return null;
  }
}

export async function downloadClassReportPdf(
  report: ClassReport,
  schoolName?: string,
  levelsEnabled = true,
  logoUrl?: string,
  goal = 20
): Promise<void> {
  // The Lumi brand character is a same-origin public asset — fetched to a data
  // URL so @react-pdf embeds it reliably.
  const [logo, character] = await Promise.all([
    logoUrl ? imageToDataUrl(logoUrl) : Promise.resolve(null),
    imageToDataUrl('/brand/blue-lumi-book.png'),
  ]);
  const blob = await pdf(
    <ClassReportDocument report={report} schoolName={schoolName} levelsEnabled={levelsEnabled} logo={logo} character={character} goal={goal} />
  ).toBlob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  const safeClass = (report.className || 'class').replace(/[^\w-]+/g, '-');
  a.href = url;
  a.download = `class-report-${safeClass}-${report.to.slice(0, 10)}.pdf`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
