#!/usr/bin/env bash
# One-shot health audit for the Gen2 Cloud Functions estate.
#
# Exists because a missing per-service `roles/run.invoker` binding is
# INVISIBLE: Eventarc retries, gives up, and the only trace is a 403 in that
# one service's logs. maintainClassDailyReading was broken this way for three
# days (982 dropped invocations) before an unrelated canary exposed it.
#
# Checks:
#   1. invoker-403s across every service (the exact bug class)
#   2. every eventarc/scheduler-backed service has the runtime-SA invoker
#   3. dropped events ("no available instance" = maxInstances saturation)
#   4. scheduler jobs whose last attempt actually failed
#   5. cron heartbeats: missing, errored, or stale beyond their cadence
#
# Usage: ./scripts/audit-function-health.sh [project] [region]
# Read-only: issues no writes and changes no configuration.

set -uo pipefail
PROJECT="${1:-lumi-ninc-au}"
REGION="${2:-australia-southeast1}"
RUNTIME_SA="lumi-functions-runtime@${PROJECT}.iam.gserviceaccount.com"
FAIL=0

echo "=== Gen2 function health audit — ${PROJECT}/${REGION} ==="

echo
echo "[1] invoker-403s in the last 30 days (count + most recent, to tell live from historical)"
INV403=$(gcloud logging read 'textPayload:"run.routes.invoke"' --project "$PROJECT" \
  --freshness=30d --limit=1000 \
  --format="value(resource.labels.service_name,timestamp)" 2>/dev/null \
  | awk -F'\t' '{c[$1]++; if($2>last[$1]) last[$1]=$2} END {for (s in c) printf "    %-38s %5d  last: %s\n", s, c[s], last[s]}' | sort -k2 -rn)
if [ -n "$INV403" ]; then
  echo "$INV403"
  echo "    ^ if 'last' predates your most recent fix, these are historical; re-run tomorrow to confirm clean"
  FAIL=1
else echo "    none"; fi

echo
echo "[2] invoker bindings on trigger/scheduler-backed services"
gcloud run services list --project "$PROJECT" --region "$REGION" \
  --format="value(metadata.name)" 2>/dev/null | sort > /tmp/_af_all.txt
gcloud eventarc triggers list --project "$PROJECT" --location "$REGION" \
  --format="value(name)" 2>/dev/null | sed 's|.*/||; s/-[0-9]*$//' | sort -u > /tmp/_af_trig.txt
gcloud scheduler jobs list --project "$PROJECT" --location "$REGION" \
  --format="value(name)" 2>/dev/null \
  | sed 's|.*/||; s|^firebase-schedule-||; s|-'"$REGION"'$||' | tr 'A-Z' 'a-z' | sort -u > /tmp/_af_sched.txt
GAPS=0
while read -r S; do
  [ -z "$S" ] && continue
  grep -qx "$S" /tmp/_af_trig.txt || grep -qx "$S" /tmp/_af_sched.txt || continue
  gcloud run services get-iam-policy "$S" --project "$PROJECT" --region "$REGION" \
    --format=json 2>/dev/null | grep -q "$RUNTIME_SA" || {
      echo "    MISSING run.invoker: $S"; GAPS=$((GAPS+1)); FAIL=1; }
done < /tmp/_af_all.txt
[ "$GAPS" -eq 0 ] && echo "    all trigger/scheduler services OK"

echo
echo "[3] dropped events (maxInstances saturation), last 7 days"
DROPS=$(gcloud logging read 'resource.type="cloud_run_revision" AND textPayload:"no available instance"' \
  --project "$PROJECT" --freshness=7d --limit=500 \
  --format="value(resource.labels.service_name)" 2>/dev/null | sort | uniq -c | sort -rn)
if [ -n "$DROPS" ]; then echo "$DROPS" | sed 's/^/    /'; echo "    NOTE: with retry:false these events are LOST; check the matching reconciler"; else echo "    none"; fi

echo
echo "[4] scheduler jobs whose last attempt failed"
BAD=$(gcloud scheduler jobs list --project "$PROJECT" --location "$REGION" \
  --format="value(name.basename(),status.code,lastAttemptTime)" 2>/dev/null \
  | awk -F'\t' '$2!="" && $2!=0 && $3!="" {print "    FAILED: "$1" (code "$2")"}')
if [ -n "$BAD" ]; then echo "$BAD"; FAIL=1; else echo "    none (jobs with code -1 and no lastAttemptTime have simply never run)"; fi

echo
echo "[5] cron heartbeats (opsMetrics/cronHeartbeats)"
TOKEN=$(gcloud auth print-access-token 2>/dev/null)
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/opsMetrics/cronHeartbeats" 2>/dev/null \
  | python3 -c "
import json,sys,datetime
try: d=json.load(sys.stdin).get('fields',{})
except Exception: print('    (unreadable)'); sys.exit()
now=datetime.datetime.now(datetime.timezone.utc); bad=0
for k,v in sorted(d.items()):
    f=v.get('mapValue',{}).get('fields',{})
    st=f.get('lastStatus',{}).get('stringValue','?')
    ts=f.get('lastRunAt',{}).get('timestampValue')
    age=(now-datetime.datetime.fromisoformat(ts.replace('Z','+00:00'))).total_seconds()/3600 if ts else None
    # 8 days covers the weekly crons (pruneStaleFcmTokens, reconcileClassDailyReading)
    if st!='ok' or (age is not None and age>192):
        print(f'    ATTENTION {k}: status={st} age={age:.1f}h'); bad+=1
print(f'    {len(d)} heartbeats, {bad} needing attention')"

echo
[ "$FAIL" -eq 0 ] && echo "=== RESULT: clean ===" || echo "=== RESULT: findings above need review ==="
exit 0
