# App Store screenshots

Store-ready framed panels live in `framed/` — upload those to App Store
Connect. Raw simulator captures live in `raw/`. The compositor is `frame/`
(`panel.html` + `build.sh`; edit a caption or tint in `build.sh` and re-run).

## Sizes
- iPhone 6.9″: `framed/iphone69/*.png` — 1320×2868 portrait (7 panels)
- iPad 13″: `framed/ipad13/*.png` — 2752×2064 landscape (6 panels)

## iPhone panels (parent story, upload in this order)

| # | Caption | Screen |
|---|---------|--------|
| 01 | Tonight's reading, ready to go | Zoe's Tonight card: 3 assigned books with covers, Log reading + Quick log |
| 02 | Every child, one place | Sarah's home: Ava ✓ logged / Leo pending, child switcher, 55-night streak momentum card |
| 03 | Every night is a win | "Night 50 complete" celebration: confetti, streak pill, badge-earned pill |
| 04 | Badges worth earning | Achievements: 10/14 unlocked, "Almost there" progress |
| 05 | Every book, remembered | Bookshelf: 9 covers with authors + session counts |
| 06 | Your teacher, in the loop | Activity timeline: feeling blobs, teacher comment card, week summary |
| 07 | Meet Lumi | Welcome screen with the mascot |

## iPad panels (teacher story)

| # | Caption | Screen |
|---|---------|--------|
| 01 | Your class at a glance | Dashboard: engagement ring, needs-attention, recent reading |
| 02 | Momentum you can see | Weekly chart, 12-week heatmap, Top Readers leaderboard |
| 03 | Made for the classroom iPad | Kiosk "Find your name" avatar wall, 5/10 scanned |
| 04 | Reading groups, organised | 4 colored groups, level pills, avatar strips |
| 05 | Your class library | Cover wall with assigned-count badges |
| 06 | Celebrate your top readers | Awards: gold Top Reader + Special award holders |

## Demo data

Tenant: `lumi_demo_primary_school` (prod `lumi-ninc-au`, `isDemo: true`).
Rebuild with:

```
node scripts/seed_demo_school.js --reset --yes       # base tenant
node scripts/seed_demo_screenshots.js                # screenshot overlay
```

(Auth-user creation needs `FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH` — plain
gcloud ADC can't call the Auth Admin API.)

Logins (password `LumiDemo!2026`): `demo.parent@lumidemo.school` (Sarah:
Ava + Leo), `demo.parent2@lumidemo.school` (Marcus: Zoe),
`demo.teacher@lumidemo.school` (Priya, 3G Goannas).

Staging notes baked into the overlay: Leo sits one night short of the
50-night badge so one quick-log reproduces the celebration shot; Zoe has no
log "today" (red pre-log Tonight card); 5 of 10 students are kiosk-scanned;
Oliver holds gold Top Reader; Isla holds the Special award.

## Recapture

Simulators: iPhone 17 Pro Max (1320×2868) + iPad Pro 13-inch (2752×2064).
Clean status bar first:

```
xcrun simctl status_bar <udid> override --time "9:41" --batteryLevel 100 \
  --batteryState charged --wifiBars 3 --cellularBars 4
```

Capture with ⌘S in Simulator, drop into `raw/`, then `frame/build.sh`.
