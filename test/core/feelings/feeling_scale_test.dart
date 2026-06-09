import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/feelings/feeling_scale.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';

void main() {
  test('scale values run hard=1 … great=5', () {
    expect(ReadingFeeling.hard.value, 1);
    expect(ReadingFeeling.tricky.value, 2);
    expect(ReadingFeeling.okay.value, 3);
    expect(ReadingFeeling.good.value, 4);
    expect(ReadingFeeling.great.value, 5);
  });

  test('asset path matches the blob art naming', () {
    expect(ReadingFeeling.great.asset, 'assets/blobs/blob-great.png');
    expect(ReadingFeeling.hard.asset, 'assets/blobs/blob-hard.png');
  });

  test('labels are human-readable', () {
    expect(ReadingFeeling.okay.label, 'Okay');
    expect(ReadingFeeling.great.label, 'Great');
  });

  test('feelingFromValue round-trips and rejects out-of-range', () {
    for (final f in ReadingFeeling.values) {
      expect(feelingFromValue(f.value), f);
    }
    expect(feelingFromValue(0), isNull);
    expect(feelingFromValue(6), isNull);
  });

  test('tier map covers all five values', () {
    expect(feelingTierByValue.length, 5);
    expect(feelingTierByValue[1], 'Hard');
    expect(feelingTierByValue[5], 'Great');
  });
}
