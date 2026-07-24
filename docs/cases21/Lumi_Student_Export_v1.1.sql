/******************************************************************************
    Lumi Student Export
    CASES21 SQL Worksheet Query
    Version: 1.1

    WHAT THIS DOES
    Returns one row per actively-enrolled student, with the six columns the
    Lumi import expects:

        Student ID | First Name | Last Name | Class Name | Year Level | Parent Email

    HOW TO RUN IT
    CASES21 → Utilities → MAZE → View and Report Data → Worksheet → SQL editor.
    Paste this whole file, run it, then export the results to Excel.
    Upload the .xlsx straight to Lumi, or save as CSV first — either works.

    WHAT CHANGED SINCE v1.0
    - Year Level is now a clean whole number, and Foundation exports as "Prep"
      rather than 0. (v1.0's ROUND() rendered every year as "0.0", "4.0" …)
    - Enrolment status match is case-insensitive.
    - Blank student-key rows are excluded (v1.0 returned one empty row).
    - Names and home groups are trimmed.

    IF THIS QUERY ERRORS ON YOUR CASES21 VERSION
    The Year Level CASE block is the only part using CAST. Replace lines marked
    [YEAR LEVEL] with the v1.0 form:

        ROUND(ST.SCHOOL_YEAR,0)           AS [Year Level],

    Lumi reads that form too — it understands "0.0" as Prep and "4.0" as Year 4.
    Everything else in this query is plain CASES21 SQL.
******************************************************************************/

SELECT
    TRIM(ST.STKEY)                    AS [Student ID],
    TRIM(ST.FIRST_NAME)               AS [First Name],
    TRIM(ST.SURNAME)                  AS [Last Name],
    TRIM(ST.HOME_GROUP)               AS [Class Name],

    /* [YEAR LEVEL] CASES21 stores Foundation as year 0. ------------------- */
    CASE
        WHEN CAST(ST.SCHOOL_YEAR AS INTEGER) = 0 THEN 'Prep'
        ELSE CAST(CAST(ST.SCHOOL_YEAR AS INTEGER) AS VARCHAR(10))
    END                               AS [Year Level],
    /* -------------------------------------------------------------------- */

    /* Family email: primary, falling back to the secondary address.
       Siblings share a family record, so the same address repeats — that is
       expected and Lumi handles it. */
    CASE
        WHEN ISNULL(DF.E_MAIL_A,'') <> '' THEN DF.E_MAIL_A
        WHEN ISNULL(DF.E_MAIL_B,'') <> '' THEN DF.E_MAIL_B
        ELSE ''
    END                               AS [Parent Email]

FROM ST
LEFT JOIN DF
    ON ST.FAMILY = DF.DFKEY

WHERE UPPER(TRIM(ST.STATUS)) = 'ACTV'
  AND TRIM(ISNULL(ST.STKEY,'')) <> ''

/*  OPTIONAL — uncomment ONE of the following by replacing the WHERE line above.

    Include next year's enrolments as well as current students. Use this when
    you are rolling over in December/January and next year's Preps are already
    loaded into CASES21 with a "future" status:

        WHERE UPPER(TRIM(ST.STATUS)) IN ('ACTV','FUT')
          AND TRIM(ISNULL(ST.STKEY,'')) <> ''

    Single campus only (replace 01 with your campus number):

        WHERE UPPER(TRIM(ST.STATUS)) = 'ACTV'
          AND TRIM(ISNULL(ST.STKEY,'')) <> ''
          AND ST.CAMPUS = 01
*/

ORDER BY
    CAST(ST.SCHOOL_YEAR AS INTEGER),
    ST.HOME_GROUP,
    ST.SURNAME,
    ST.FIRST_NAME;


/******************************************************************************
    ANNUAL ROLLOVER VARIANT — no parent contact details

    Lumi only needs parent emails the first time a school is set up. For the
    yearly class rollover, the five columns below are enough, and the export
    then contains no contact information at all.

    Replace the SELECT list above with:

        TRIM(ST.STKEY)          AS [Student ID],
        TRIM(ST.FIRST_NAME)     AS [First Name],
        TRIM(ST.SURNAME)        AS [Last Name],
        TRIM(ST.HOME_GROUP)     AS [Class Name],
        CASE
            WHEN CAST(ST.SCHOOL_YEAR AS INTEGER) = 0 THEN 'Prep'
            ELSE CAST(CAST(ST.SCHOOL_YEAR AS INTEGER) AS VARCHAR(10))
        END                     AS [Year Level]

    ...and delete the LEFT JOIN DF line.
******************************************************************************/
