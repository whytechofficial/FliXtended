import 'dart:convert';
import 'dart:io';

import 'package:flixquest/mobile/screens/imdb_import_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('import stages map to distinct keys present in every locale',
      () {
    final keys = ImdbImportStage.values.map(imdbImportStageKey).toList();
    expect(keys.toSet().length, keys.length);
    expect(keys, everyElement(isNotEmpty));

    final localeFiles = Directory('assets/translations')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();
    expect(localeFiles.length, 6);
    for (final file in localeFiles) {
      final catalog =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final key in keys) {
        final value = catalog[key];
        expect(value, isA<String>(), reason: '${file.path}: $key');
        expect((value as String).isNotEmpty, isTrue,
            reason: '${file.path}: $key');
      }
    }
  });
}
