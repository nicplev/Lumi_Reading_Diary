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
  page: { padding: 28, fontSize: 10, color: C.ink, fontFamily: 'Helvetica' },

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
  headerBrand: { fontSize: 12, color: C.white, fontFamily: 'Helvetica-Bold', opacity: 0.95 },
  subBar: { marginTop: 8, marginBottom: 16 },
  subBarText: { fontSize: 9, color: C.muted },

  // Bento metric tiles
  metricsRow: { flexDirection: 'row', flexWrap: 'wrap', marginBottom: 8 },
  metricOuter: { width: '25%', padding: 3 },
  metricBox: { borderRadius: 8, padding: 9, minHeight: 46 },
  metricValue: { fontSize: 15, fontFamily: 'Helvetica-Bold', color: C.ink },
  metricLabel: { fontSize: 6.5, color: C.ink, opacity: 0.7, textTransform: 'uppercase', marginTop: 3, fontFamily: 'Helvetica-Bold' },

  // Sections
  section: { marginBottom: 14 },
  sectionHead: { flexDirection: 'row', alignItems: 'center', marginBottom: 6 },
  sectionDot: { width: 11, height: 11, borderRadius: 3, marginRight: 6 },
  sectionTitle: { fontSize: 12, fontFamily: 'Helvetica-Bold', color: C.ink },

  // Tables
  headRow: {
    flexDirection: 'row',
    backgroundColor: C.cream,
    borderRadius: 5,
    paddingVertical: 4,
    paddingHorizontal: 4,
  },
  row: { flexDirection: 'row', borderBottom: `1 solid ${C.rule}`, paddingVertical: 3, paddingHorizontal: 4 },
  th: { fontSize: 8, color: C.muted, fontFamily: 'Helvetica-Bold' },
  cell: { fontSize: 9 },
  cellBold: { fontSize: 9, fontFamily: 'Helvetica-Bold' },

  // Rank badges (gold / silver / bronze)
  rankBadge: { width: 14, height: 14, borderRadius: 7, alignItems: 'center', justifyContent: 'center' },
  rankText: { fontSize: 8, fontFamily: 'Helvetica-Bold' },

  // Level distribution bars
  levelRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 5 },
  levelName: { fontSize: 9, width: 90 },
  levelTrack: { flex: 1, height: 7, borderRadius: 4, backgroundColor: C.cream, marginHorizontal: 6 },
  levelFill: { height: 7, borderRadius: 4, backgroundColor: C.green },
  levelCount: { fontSize: 8, color: C.muted, width: 24, textAlign: 'right' },

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
type Tile = { label: string; value: string | number; bg: string };

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}

function rankColors(i: number): { bg: string; fg: string } {
  if (i === 0) return { bg: C.yellow, fg: C.ink };
  if (i === 1) return { bg: C.rule, fg: C.ink };
  if (i === 2) return { bg: C.orange, fg: C.white };
  return { bg: 'transparent', fg: C.muted };
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
}: {
  report: ClassReport;
  schoolName?: string;
  levelsEnabled?: boolean;
  logo?: string | null;
}) {
  const tiles: Tile[] = [
    { label: 'Students', value: report.totalStudents, bg: C.tintBlue },
    { label: 'Active readers', value: report.activeReaders, bg: C.tintGreen },
    { label: 'Engagement', value: `${report.engagementRate}%`, bg: C.tintRed },
    { label: 'Met target', value: `${report.targetMetRate}%`, bg: C.tintYellow },
    { label: 'Total minutes', value: report.totalMinutes, bg: C.tintBlue },
    { label: 'Avg min/student', value: report.avgMinutesPerStudent, bg: C.tintGreen },
    { label: 'Reading days', value: report.totalReadingDays, bg: C.tintOrange },
    { label: 'Sessions', value: report.totalSessions, bg: C.tintRed },
  ];

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
          <Text style={styles.headerBrand}>Lumi</Text>
        </View>
        <View style={styles.subBar}>
          <Text style={styles.subBarText}>
            {[report.className, report.yearLevel].filter(Boolean).join(' · ')} · {fmtDate(report.from)} – {fmtDate(report.to)}
          </Text>
        </View>

        {/* Bento metrics */}
        <View style={styles.metricsRow}>
          {tiles.map((t) => (
            <View style={styles.metricOuter} key={t.label}>
              <View style={[styles.metricBox, { backgroundColor: t.bg }]}>
                <Text style={styles.metricValue}>{String(t.value)}</Text>
                <Text style={styles.metricLabel}>{t.label}</Text>
              </View>
            </View>
          ))}
        </View>

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

        {/* Needs support */}
        <View style={styles.section}>
          <SectionHead color={C.orange} title="Students needing support" />
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

        {/* All students */}
        <View style={styles.section}>
          <SectionHead color={C.blue} title="All students" />
          {report.students.length === 0 ? (
            <Text style={styles.cell}>No students in this class.</Text>
          ) : (
            <View>
              <View style={styles.headRow}>
                <Text style={[styles.th, { width: '34%' }]}>Student</Text>
                <Text style={[styles.th, { width: '13%', textAlign: 'right' }]}>Minutes</Text>
                <Text style={[styles.th, { width: '13%', textAlign: 'right' }]}>Sessions</Text>
                <Text style={[styles.th, { width: '10%', textAlign: 'right' }]}>Days</Text>
                <Text style={[styles.th, { width: '14%', textAlign: 'right' }]}>Met target</Text>
                <Text style={[styles.th, { width: '16%', textAlign: 'right' }]}>Last read</Text>
              </View>
              {report.students.map((r, i) => (
                <View style={[styles.row, i % 2 === 1 ? { backgroundColor: C.cream } : {}]} key={r.id} wrap={false}>
                  <Text style={[styles.cellBold, { width: '34%' }]}>{r.name}</Text>
                  <Text style={[styles.cell, { width: '13%', textAlign: 'right' }]}>{r.minutes}</Text>
                  <Text style={[styles.cell, { width: '13%', textAlign: 'right' }]}>{r.sessions}</Text>
                  <Text style={[styles.cell, { width: '10%', textAlign: 'right' }]}>{r.readingDays}</Text>
                  <Text style={[styles.cell, { width: '14%', textAlign: 'right' }]}>{r.sessions > 0 ? `${r.metPct}%` : '—'}</Text>
                  <Text style={[styles.cell, { width: '16%', textAlign: 'right' }]}>{r.lastRead ? fmtDate(r.lastRead) : '—'}</Text>
                </View>
              ))}
            </View>
          )}
        </View>

        {/* Reading levels */}
        {levelsEnabled && (
          <View style={styles.section}>
            <SectionHead color={C.green} title="Reading levels" />
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
          </View>
        )}

        <Text style={styles.footer} fixed>
          Generated by Lumi · {new Date().toLocaleDateString()}
        </Text>
      </Page>
    </Document>
  );
}

// Fetch the school logo and inline it as a data URL. @react-pdf's <Image> can
// choke on a cross-origin URL (CORS) and cannot render SVG, so we fetch the
// bytes ourselves and skip anything that isn't a raster image. Any failure
// degrades gracefully to a logo-less (but still branded) header.
async function logoToDataUrl(url: string): Promise<string | null> {
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
  logoUrl?: string
): Promise<void> {
  const logo = logoUrl ? await logoToDataUrl(logoUrl) : null;
  const blob = await pdf(
    <ClassReportDocument report={report} schoolName={schoolName} levelsEnabled={levelsEnabled} logo={logo} />
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
