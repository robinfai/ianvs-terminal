import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'package:app/features/shell/instant_replay_store.dart';

void main() {
  TerminalFrameDiff frameWithRows(List<String> rows) {
    return TerminalFrameDiff(
      rows: [
        for (var index = 0; index < rows.length; index += 1)
          TerminalRow(index: index, text: rows[index]),
      ],
      cursor: const TerminalCursor(row: 0, col: 0, visible: true),
      viewportRows: rows.length,
      viewportCols: 80,
      dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
      scrollbackOffset: 0,
      scrollbackMaxOffset: 0,
    );
  }

  test('records non-empty frames newest first and skips duplicates', () {
    final store = InstantReplayStore();

    store.record('1', frameWithRows(['first']));
    store.record('1', frameWithRows(['first']));
    store.record('1', frameWithRows(['second']));
    store.record('1', frameWithRows(['   ']));

    final frames = store.framesFor('1');

    expect(frames, hasLength(2));
    expect(frames.first.text, 'second');
    expect(frames.last.text, 'first');
  });

  test('limits frames per session', () {
    final store = InstantReplayStore(frameLimit: 2);

    store.record('1', frameWithRows(['one']));
    store.record('1', frameWithRows(['two']));
    store.record('1', frameWithRows(['three']));

    expect(store.framesFor('1').map((frame) => frame.text), ['three', 'two']);
  });

  test('clear removes only the requested session', () {
    final store = InstantReplayStore();

    store.record('1', frameWithRows(['one']));
    store.record('2', frameWithRows(['two']));
    store.clear('1');

    expect(store.framesFor('1'), isEmpty);
    expect(store.framesFor('2').single.text, 'two');
  });
}
