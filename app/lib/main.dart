import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/admin_home.dart';
import 'screens/login_screen.dart';
import 'screens/student_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.instance.loadSession();
  runApp(const FaceAttendanceApp());
}

class FaceAttendanceApp extends StatelessWidget {
  const FaceAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiClient.instance;
    return MaterialApp(
      title: 'Face Attendance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: !api.hasSession
          ? const LoginScreen()
          : api.role == 'student'
              ? const StudentHome()
              : const AdminHome(),
    );
  }
}
