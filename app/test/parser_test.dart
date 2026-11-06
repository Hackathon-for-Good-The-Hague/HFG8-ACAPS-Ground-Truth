import 'package:flutter_test/flutter_test.dart';
import 'package:ground_truth/csv.dart';
import 'package:ground_truth/models.dart';

void main() {
  test('CSV parser handles quotes and multi-line fields', () {
    final rows = parseCsv('a,b\n"x, ""y""","line1\nline2"\n');
    expect(rows.length, 2);
    expect(rows[1][0], 'x, "y"');
    expect(rows[1][1], 'line1\nline2');
  });

  test('Trigger parser extracts title, description and completion', () {
    const raw = 'Trigger ID: R1043 - T0618\n'
        'Title: Expansion of cross-border attacks\n'
        'Description: \n:Additional drone strikes near the border\n'
        'Sources: \n(x)\nCompletion rate: 40%\n';
    final t = parseTriggers(raw);
    expect(t.length, 1);
    expect(t.first.id, 'R1043 - T0618');
    expect(t.first.title, 'Expansion of cross-border attacks');
    expect(t.first.description, 'Additional drone strikes near the border');
    expect(t.first.completion, 40);
  });
}
