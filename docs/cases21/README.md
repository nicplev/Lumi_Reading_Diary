# Lumi CASES21 Export Kit

Everything a Victorian government school needs to get its student roster out of
CASES21 and into Lumi — for first-time setup and for the annual class rollover.

**Kit contents**

| File | Purpose |
|---|---|
| `Lumi_Student_Export_v1.1.sql` | The query an admin runs in the CASES21 SQL worksheet |
| This guide | Step-by-step instructions + troubleshooting |

The same two files are served to admins inside the portal at
`school-admin-web/public/kit/` (`lumi-cases21-export-kit.sql` and
`lumi-cases21-export-guide.html`), linked from the Students → CSV import dialog
and from the School Year Transition wizard. **If you change the query here,
update the copy in `public/kit/` too** — the guide tells schools the two are the
same file.

---

## For the school admin

### Step 1 — Open the SQL worksheet

In CASES21: **Utilities → MAZE → View and Report Data → Worksheet**, then open
the SQL editor.

### Step 2 — Run the Lumi query

Paste the whole contents of `Lumi_Student_Export_v1.1.sql` and run it. You should
get one row per currently-enrolled student, sorted by year level then home group.

### Step 3 — Export to Excel

Use the worksheet's **export to Microsoft Excel** option.

### Step 4 — Give the file to Lumi

Open Lumi → **Students**, and either:

- **Setting the school up for the first time** — *Import CSV*
- **Rolling over to a new school year** — *School Year Transition*

Then upload the file. You can hand Lumi the `.xlsx` exactly as Excel saved it —
there is no need to convert it to CSV. If you prefer, *Save As → CSV (Comma
delimited)* works too, and so does selecting the rows in Excel and using Lumi's
**Paste from Excel** box.

Lumi shows you what it read before anything is saved, and the rollover import can
be undone afterwards.

---

## The columns Lumi reads

| Column | CASES21 source | Required | Notes |
|---|---|---|---|
| Student ID | `ST.STKEY` | Strongly recommended | How Lumi recognises a returning student year to year, so parent accounts and reading history stay attached. Without it, matching falls back to exact name. |
| First Name | `ST.FIRST_NAME` | **Yes** | |
| Last Name | `ST.SURNAME` | **Yes** | |
| Class Name | `ST.HOME_GROUP` | **Yes** | Imported exactly as written, so `00A` stays `00A`. Classes that don't exist yet are created. |
| Year Level | `ST.SCHOOL_YEAR` | Recommended | CASES21 stores Foundation as **0**; the query converts it to `Prep`. |
| Parent Email | `DF.E_MAIL_A`, else `DF.E_MAIL_B` | First-time setup only | Siblings share a family record, so the same address legitimately repeats. Not needed for the annual rollover — see the variant at the bottom of the SQL file. |

Column order doesn't matter, and extra columns are ignored. Lumi matches the
headings case-insensitively, so the uppercase headings the CASES21 worksheet
produces (`STUDENT ID`, `FIRST NAME`, …) are read correctly.

### If you export the ST table directly

Lumi also recognises CASES21's own column names — `STKEY`, `FIRST_NAME`,
`SURNAME`, `HOME_GROUP`, `SCHOOL_YEAR`, `E_MAIL_A`/`E_MAIL_B`, `STATUS` — so a
raw table dump imports too. In that case Lumi applies the filtering the query
would have done: students whose `STATUS` is `LEFT`/`INAC` are skipped, and it
tells you how many.

---

## Troubleshooting

**"No column found for First Name / Last Name / Class Name"**
The heading row is missing or was cut off. Re-export including the headings, or
paste the rows starting from the heading row.

**Year levels look wrong, or every student says "isn't a standard level"**
You're on query v1.0, which emitted `0.0`, `1.0`, … Lumi understands that form,
but v1.1 exports clean values. Either is fine — re-run with v1.1 if you'd prefer
the export to be readable.

**Some students show "Missing required fields"**
Those students have no home group in CASES21. Assign one there and re-export, or
exclude the rows in Lumi's review step.

**A student appears twice**
Two CASES21 records share one `STKEY`. Lumi refuses to guess between them — fix
the duplicate in CASES21, then re-export.

**Lots of students flagged as "left the school"**
The export is probably incomplete — for example, one campus or one year level
only. Check the row count against your enrolment before confirming; the rollover
wizard makes you tick an extra confirmation when the number is large.

**Next year's Preps are missing**
They're loaded in CASES21 with a *future* enrolment status. Use the
`IN ('ACTV','FUT')` variant noted in the SQL file.

**The query errors on `CAST`**
Replace the Year Level block with the v1.0 line shown in the SQL file's header
comment. Lumi reads that form too.

**`.xls` file won't upload**
Lumi reads `.xlsx`, not the older `.xls`. In Excel: *File → Save As → Excel
Workbook (.xlsx)*.

---

## For Lumi engineers

The parsing side lives in:

- `school-admin-web/src/lib/csv.ts` — tokenizer (`parseDelimited`), header aliases
- `school-admin-web/src/lib/sis/detect.ts` — format detection + row shaping
- `school-admin-web/src/lib/sis/read-input.ts` — file/paste/xlsx readers
- `school-admin-web/src/lib/year-ladder.ts` — numeric year-level decoding
  (mirrored in `functions/src/access.ts` — keep in sync)

Tests: `school-admin-web/scripts/sis-detect.test.ts` and
`scripts/year-ladder.test.ts` (`npx tsx <file>`). Their fixtures reproduce the
structure of a real CASES21 return — uppercase headings, CRLF, a blank record
between the header and the data, `N.0` year levels — with entirely synthetic
student rows. **Never commit real student data into fixtures.**

Adding another SIS (Compass, Sentral) is a new signature plus column map in
`detect.ts`; nothing downstream changes.
