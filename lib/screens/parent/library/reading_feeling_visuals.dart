import '../../../data/models/reading_log_model.dart';

/// Blob asset + label for a logged reading feeling. Shared by the Library
/// activity rows and the session-detail sheet.
String feelingAsset(ReadingFeeling feeling) {
  switch (feeling) {
    case ReadingFeeling.hard:
      return 'assets/blobs/blob-hard.png';
    case ReadingFeeling.tricky:
      return 'assets/blobs/blob-tricky.png';
    case ReadingFeeling.okay:
      return 'assets/blobs/blob-okay.png';
    case ReadingFeeling.good:
      return 'assets/blobs/blob-good.png';
    case ReadingFeeling.great:
      return 'assets/blobs/blob-great.png';
  }
}

String feelingLabel(ReadingFeeling feeling) =>
    feeling.name[0].toUpperCase() + feeling.name.substring(1);
