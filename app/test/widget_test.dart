import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_attendance/screens/login_screen.dart';

void main() {
  testWidgets('login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Face Attendance'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
