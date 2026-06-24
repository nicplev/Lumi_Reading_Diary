'use client';

// Loaded only via dynamic import (on the Download PDF click), so @react-pdf
// stays out of the main bundle and never runs during SSR/build.
import { Document, Page, Text, View, StyleSheet, pdf } from '@react-pdf/renderer';
import type { ClassReport } from '@/lib/firestore/reports';

const styles = StyleSheet.create({
  page: { padding: 32, fontSize: 10, color: '#2B2B2B', fontFamily: 'Helvetica' },
  schoolName: { fontSize: 10, color: '#6B7280' },
  title: { fontSize: 20, fontWeight: 'bold', marginTop: 2 },
  subtitle: { fontSize: 10, color: '#6B7280', marginTop: 2, marginBottom: 16 },
  metricsRow: { flexDirection: 'row', flexWrap: 'wrap', marginBottom: 12 },
  metric: { width: '25%', padding: 4 },
  metricBox: { border: '1 solid #E5E7EB', borderRadius: 4, padding: 8 },
  metricLabel: { fontSize: 7, color: '#6B7280', textTransform: 'uppercase' },
  metricValue: { fontSize: 16, fontWeight: 'bold', marginTop: 3 },
  section: { marginBottom: 14 },
  sectionTitle: { fontSize: 13, fontWeight: 'bold', marginBottom: 6 },
  row: { flexDirection: 'row', borderBottom: '1 solid #F0F0F0', paddingVertical: 3 },
  th: { fontSize: 8, color: '#6B7280', fontWeight: 'bold' },
  cell: { fontSize: 9 },
  footer: {
    position: 'absolute',
    bottom: 24,
    left: 32,
    right: 32,
    fontSize: 8,
    color: '#9CA3AF',
    textAlign: 'center',
    borderTop: '1 solid #F0F0F0',
    paddingTop: 6,
  },
});

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}

function Metric({ label, value }: { label: string; value: string | number }) {
  return (
    <View style={styles.metric}>
      <View style={styles.metricBox}>
        <Text style={styles.metricLabel}>{label}</Text>
        <Text style={styles.metricValue}>{String(value)}</Text>
      </View>
    </View>
  );
}

function ClassReportDocument({ report, schoolName }: { report: ClassReport; schoolName?: string }) {
  return (
    <Document title={`Class Reading Report — ${report.className}`}>
      <Page size="A4" style={styles.page}>
        {schoolName ? <Text style={styles.schoolName}>{schoolName}</Text> : null}
        <Text style={styles.title}>Class Reading Report</Text>
        <Text style={styles.subtitle}>
          {[report.className, report.yearLevel].filter(Boolean).join(' · ')} · {fmtDate(report.from)} – {fmtDate(report.to)}
        </Text>

        <View style={styles.metricsRow}>
          <Metric label="Students" value={report.totalStudents} />
          <Metric label="Active readers" value={report.activeReaders} />
          <Metric label="Engagement" value={`${report.engagementRate}%`} />
          <Metric label="Met target" value={`${report.targetMetRate}%`} />
          <Metric label="Total minutes" value={report.totalMinutes} />
          <Metric label="Avg min/student" value={report.avgMinutesPerStudent} />
          <Metric label="Books read" value={report.totalBooks} />
          <Metric label="Sessions" value={report.totalSessions} />
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Top readers</Text>
          {report.topReaders.length === 0 ? (
            <Text style={styles.cell}>No reading recorded in this period.</Text>
          ) : (
            <View>
              <View style={styles.row}>
                <Text style={[styles.th, { width: '8%' }]}>#</Text>
                <Text style={[styles.th, { width: '52%' }]}>Student</Text>
                <Text style={[styles.th, { width: '15%' }]}>Minutes</Text>
                <Text style={[styles.th, { width: '12%' }]}>Days</Text>
                <Text style={[styles.th, { width: '13%' }]}>Books</Text>
              </View>
              {report.topReaders.map((r, i) => (
                <View style={styles.row} key={r.id}>
                  <Text style={[styles.cell, { width: '8%' }]}>{i + 1}</Text>
                  <Text style={[styles.cell, { width: '52%' }]}>{r.name}</Text>
                  <Text style={[styles.cell, { width: '15%' }]}>{r.minutes}</Text>
                  <Text style={[styles.cell, { width: '12%' }]}>{r.readingDays}</Text>
                  <Text style={[styles.cell, { width: '13%' }]}>{r.books}</Text>
                </View>
              ))}
            </View>
          )}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Students needing support</Text>
          {report.needsSupport.length === 0 ? (
            <Text style={styles.cell}>All students are actively engaged in reading.</Text>
          ) : (
            <View>
              <View style={styles.row}>
                <Text style={[styles.th, { width: '50%' }]}>Student</Text>
                <Text style={[styles.th, { width: '17%' }]}>Minutes</Text>
                <Text style={[styles.th, { width: '13%' }]}>Days</Text>
                <Text style={[styles.th, { width: '20%' }]}>Issue</Text>
              </View>
              {report.needsSupport.map((r) => (
                <View style={styles.row} key={r.id}>
                  <Text style={[styles.cell, { width: '50%' }]}>{r.name}</Text>
                  <Text style={[styles.cell, { width: '17%' }]}>{r.minutes}</Text>
                  <Text style={[styles.cell, { width: '13%' }]}>{r.readingDays}</Text>
                  <Text style={[styles.cell, { width: '20%' }]}>{r.issue}</Text>
                </View>
              ))}
            </View>
          )}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Reading levels</Text>
          {report.levelDistribution.length === 0 ? (
            <Text style={styles.cell}>No students in this class.</Text>
          ) : (
            report.levelDistribution.map((l) => (
              <View style={styles.row} key={l.level}>
                <Text style={[styles.cell, { width: '70%' }]}>{l.level}</Text>
                <Text style={[styles.cell, { width: '30%' }]}>{l.count}</Text>
              </View>
            ))
          )}
        </View>

        <Text style={styles.footer} fixed>
          Generated by Lumi · {new Date().toLocaleDateString()}
        </Text>
      </Page>
    </Document>
  );
}

export async function downloadClassReportPdf(report: ClassReport, schoolName?: string): Promise<void> {
  const blob = await pdf(<ClassReportDocument report={report} schoolName={schoolName} />).toBlob();
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
