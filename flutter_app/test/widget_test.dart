import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import 'package:flutter_identification_mobile/screens/identification_screen.dart';

void main() {
  testWidgets('identification screen renders fallback state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: IdentificationScreen(),
        ),
      ),
    );

    expect(find.text('Paciente não encontrado'), findsOneWidget);
    expect(find.text('Nova identificação'), findsOneWidget);
  });
}
