// Browser-side readers that turn whatever an admin gives us — a file they
// picked, or text they pasted out of Excel — into tokenized records for
// ./detect.ts.
//
// Kept apart from detect.ts so the pure detection logic stays runnable outside
// a browser (scripts/sis-detect.test.ts) and so the spreadsheet parser can be
// code-split: `read-excel-file` is only fetched when someone actually picks an
// .xlsx, leaving the normal portal bundle unchanged.

import { parseDelimited } from '../csv';
import { adaptSisRecords, type SisNote, type SisParseResult } from './detect';

export const ACCEPTED_IMPORT_EXTENSIONS = '.csv,.tsv,.txt,.xlsx';

/** Spreadsheet formats we can't read — .xls/.xlsm need a different parser. */
const UNSUPPORTED_SPREADSHEETS = ['.xls', '.xlsm', '.xlsb', '.ods', '.numbers'];

export class ImportInputError extends Error {}

function extensionOf(name: string): string {
  const dot = name.lastIndexOf('.');
  return dot === -1 ? '' : name.slice(dot).toLowerCase();
}

/** Excel cells arrive typed (number/Date/boolean); the importer wants text. */
function cellToText(value: unknown): string {
  if (value == null) return '';
  if (value instanceof Date) {
    // Only dates we'd ever see are mis-typed columns; ISO keeps them legible.
    return value.toISOString().slice(0, 10);
  }
  return String(value).trim();
}

/**
 * Read the first sheet that actually has rows. CASES21's "export to Excel"
 * produces a single sheet, but admins re-save workbooks with notes tabs and
 * we shouldn't fail on an empty leading sheet.
 */
async function readSpreadsheet(file: File): Promise<{ records: string[][]; note: SisNote | null }> {
  const { default: readXlsxFile } = await import('read-excel-file/browser');
  const sheets = await readXlsxFile(file);

  const populated = sheets
    .map((sheet) => ({
      name: sheet.sheet,
      records: sheet.data
        .map((row) => row.map(cellToText))
        .filter((row) => row.some((cell) => cell !== '')),
    }))
    .filter((sheet) => sheet.records.length > 0);

  if (populated.length === 0) {
    throw new ImportInputError('That spreadsheet has no rows in it');
  }

  const chosen = populated[0];
  const note: SisNote | null =
    sheets.length > 1
      ? {
          code: 'sheet',
          count: sheets.length,
          message: `Read the "${chosen.name}" sheet — that workbook has ${sheets.length} sheets`,
        }
      : null;
  return { records: chosen.records, note };
}

function readTextFile(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new ImportInputError('That file could not be read'));
    reader.onload = (event) => resolve((event.target?.result as string) ?? '');
    reader.readAsText(file);
  });
}

/**
 * Read a picked file into import rows. Spreadsheets go through the lazy xlsx
 * parser; everything else is treated as delimited text.
 */
export async function readImportFile(file: File): Promise<SisParseResult> {
  const extension = extensionOf(file.name);

  if (UNSUPPORTED_SPREADSHEETS.includes(extension)) {
    throw new ImportInputError(
      `Lumi can't read ${extension} files. In Excel choose File → Save As and pick "Excel Workbook (.xlsx)" or "CSV (Comma delimited)", then try again.`
    );
  }

  let records: string[][];
  let sheetNote: SisNote | null = null;
  if (extension === '.xlsx') {
    ({ records, note: sheetNote } = await readSpreadsheet(file));
  } else {
    records = parseDelimited(await readTextFile(file));
  }

  if (records.length === 0) {
    throw new ImportInputError('That file is empty');
  }

  const result = adaptSisRecords(records);
  return sheetNote ? { ...result, notes: [sheetNote, ...result.notes] } : result;
}

/** Read text pasted out of Excel or Sheets (tab-separated) or a CSV snippet. */
export function readPastedText(text: string): SisParseResult {
  const records = parseDelimited(text);
  if (records.length === 0) {
    throw new ImportInputError('Nothing to import — paste the rows including the heading row');
  }
  return adaptSisRecords(records);
}
