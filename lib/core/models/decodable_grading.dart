// Grading schemas for decodable readers.
// Australian decodable reader publishers each use their own levelling
// convention. This model defines the supported schemas so the app can
// present the right level picker for each series and store a consistent
// metadata key alongside the human-readable readingLevel string.

// ── Enum ──────────────────────────────────────────────────────────────────────

enum GradingSchema {
  llllStages,
  levels,
  readingDoctor,
  phases,
  custom,
}

// ── Level ─────────────────────────────────────────────────────────────────────

/// A single selectable level within a grading schema.
class GradingLevel {
  const GradingLevel({
    required this.value,
    required this.display,
    this.sublabel,
    this.sortKey = 0,
  });

  /// Stored in the Firestore `readingLevel` field (e.g. "Stage 3", "Level 7", "1A").
  final String value;

  /// Short label shown on the selection chip (e.g. "Stage 3", "1A").
  final String display;

  /// Optional descriptor line shown below the chip label (e.g. "CVC Words").
  final String? sublabel;

  /// Numeric key used to sort levels within the schema; lower = earlier.
  final double sortKey;
}

// ── Schema definition ─────────────────────────────────────────────────────────

class GradingSchemaDefinition {
  const GradingSchemaDefinition({
    required this.schema,
    required this.metadataKey,
    required this.displayName,
    required this.description,
    required this.levels,
  });

  final GradingSchema schema;

  /// Stored as `metadata['gradingSchema']` in Firestore.
  final String metadataKey;

  /// Short name shown on the schema selector chip (e.g. "LLLL Stages").
  final String displayName;

  /// One-line description shown below the chip when selected.
  final String description;

  /// Ordered list of selectable levels. Empty for [GradingSchema.custom].
  final List<GradingLevel> levels;
}

// ── Schema catalogue ──────────────────────────────────────────────────────────

/// Little Learners Love Literacy — the dominant Australian SSP decodable series.
/// 7 stages plus the "Stage Plus 4" bridge stage between Stage 3 and Stage 4.
const GradingSchemaDefinition llllStagesSchema = GradingSchemaDefinition(
  schema: GradingSchema.llllStages,
  metadataKey: 'llll_stages',
  displayName: 'LLLL Stages',
  description: 'Little Learners Love Literacy — Stages 1 to 7',
  levels: [
    GradingLevel(
      value: 'Stage 1',
      display: 'Stage 1',
      sublabel: 'CVC Words',
      sortKey: 1,
    ),
    GradingLevel(
      value: 'Stage 2',
      display: 'Stage 2',
      sublabel: 'Blends & Digraphs',
      sortKey: 2,
    ),
    GradingLevel(
      value: 'Stage 3',
      display: 'Stage 3',
      sublabel: 'Complex Digraphs',
      sortKey: 3,
    ),
    GradingLevel(
      value: 'Stage Plus 4',
      display: 'Stage\n+4',
      sublabel: 'Bridge',
      sortKey: 3.5,
    ),
    GradingLevel(
      value: 'Stage 4',
      display: 'Stage 4',
      sublabel: 'Magic E',
      sortKey: 4,
    ),
    GradingLevel(
      value: 'Stage 5',
      display: 'Stage 5',
      sublabel: 'Vowel Teams',
      sortKey: 5,
    ),
    GradingLevel(
      value: 'Stage 6',
      display: 'Stage 6',
      sublabel: 'Extended Code',
      sortKey: 6,
    ),
    GradingLevel(
      value: 'Stage 7',
      display: 'Stage 7',
      sublabel: 'Complex Code',
      sortKey: 7,
    ),
  ],
);

/// Numbered levels 1–12, covering Dandelion Launchers (12 levels),
/// Decodable Readers Australia (8 levels), and similar series.
const GradingSchemaDefinition levelsSchema = GradingSchemaDefinition(
  schema: GradingSchema.levels,
  metadataKey: 'levels',
  displayName: 'Levels 1–12',
  description: 'Dandelion Launchers, DRA & other numbered series',
  levels: [
    GradingLevel(value: 'Level 1', display: 'Level 1', sortKey: 1),
    GradingLevel(value: 'Level 2', display: 'Level 2', sortKey: 2),
    GradingLevel(value: 'Level 3', display: 'Level 3', sortKey: 3),
    GradingLevel(value: 'Level 4', display: 'Level 4', sortKey: 4),
    GradingLevel(value: 'Level 5', display: 'Level 5', sortKey: 5),
    GradingLevel(value: 'Level 6', display: 'Level 6', sortKey: 6),
    GradingLevel(value: 'Level 7', display: 'Level 7', sortKey: 7),
    GradingLevel(value: 'Level 8', display: 'Level 8', sortKey: 8),
    GradingLevel(value: 'Level 9', display: 'Level 9', sortKey: 9),
    GradingLevel(value: 'Level 10', display: 'Level 10', sortKey: 10),
    GradingLevel(value: 'Level 11', display: 'Level 11', sortKey: 11),
    GradingLevel(value: 'Level 12', display: 'Level 12', sortKey: 12),
  ],
);

/// Reading Doctor — freely available Australian decodable series.
/// Two parts: Basic Code (1A–1C) and Intermediate Code (2A–2C).
const GradingSchemaDefinition readingDoctorSchema = GradingSchemaDefinition(
  schema: GradingSchema.readingDoctor,
  metadataKey: 'reading_doctor',
  displayName: 'Reading Doctor',
  description: 'Part I Basic Code (1A–1C) · Part II Intermediate (2A–2C)',
  levels: [
    GradingLevel(
      value: '1A',
      display: '1A',
      sublabel: 'Basic CVC',
      sortKey: 10,
    ),
    GradingLevel(
      value: '1B',
      display: '1B',
      sublabel: 'Clusters',
      sortKey: 11,
    ),
    GradingLevel(
      value: '1C',
      display: '1C',
      sublabel: 'Final Clusters',
      sortKey: 12,
    ),
    GradingLevel(
      value: '2A',
      display: '2A',
      sublabel: 'Split Digraphs',
      sortKey: 20,
    ),
    GradingLevel(
      value: '2B',
      display: '2B',
      sublabel: 'Vowel Teams',
      sortKey: 21,
    ),
    GradingLevel(
      value: '2C',
      display: '2C',
      sublabel: 'Extended Vowels',
      sortKey: 22,
    ),
  ],
);

/// Phase-based grading aligned to Sounds-Write, Hero Academy, and
/// the UK Letters and Sounds programme (widely used in Australian schools).
const GradingSchemaDefinition phasesSchema = GradingSchemaDefinition(
  schema: GradingSchema.phases,
  metadataKey: 'phases',
  displayName: 'Phases',
  description: 'Sounds-Write, Hero Academy & Letters and Sounds',
  levels: [
    GradingLevel(
      value: 'Phase 2',
      display: 'Phase 2',
      sublabel: 'Initial GPCs',
      sortKey: 2,
    ),
    GradingLevel(
      value: 'Phase 3',
      display: 'Phase 3',
      sublabel: 'Digraphs',
      sortKey: 3,
    ),
    GradingLevel(
      value: 'Phase 4',
      display: 'Phase 4',
      sublabel: 'Clusters',
      sortKey: 4,
    ),
    GradingLevel(
      value: 'Phase 5',
      display: 'Phase 5',
      sublabel: 'Extended Code',
      sortKey: 5,
    ),
  ],
);

/// Custom grading — teacher enters a free-text label.
/// No predefined levels; the level input renders as a text field.
const GradingSchemaDefinition customSchema = GradingSchemaDefinition(
  schema: GradingSchema.custom,
  metadataKey: 'custom',
  displayName: 'Custom',
  description: 'Enter your own label (e.g. Set 3, Unit 12)',
  levels: [],
);

/// All supported grading schemas, in display order.
const List<GradingSchemaDefinition> gradingSchemas = [
  llllStagesSchema,
  levelsSchema,
  readingDoctorSchema,
  phasesSchema,
  customSchema,
];

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Returns the [GradingSchemaDefinition] for the given Firestore metadata key,
/// or null if the key is unrecognised.
GradingSchemaDefinition? gradingSchemaByKey(String? key) {
  if (key == null) return null;
  try {
    return gradingSchemas.firstWhere((s) => s.metadataKey == key);
  } catch (_) {
    return null;
  }
}
