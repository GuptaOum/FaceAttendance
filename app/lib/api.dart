import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

const kDefaultServer = 'http://3.109.177.77';

class ApiClient {
  static final ApiClient instance = ApiClient._();
  ApiClient._();

  String baseUrl = kDefaultServer;
  String? _token;
  String role = '';

  /// Set when the account is still on its issued password (student accounts
  /// start on their roll number). The app blocks everything until it is cleared.
  bool mustChangePassword = false;

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('baseUrl') ?? kDefaultServer;
    _token = prefs.getString('token');
    role = prefs.getString('role') ?? '';
  }

  bool get hasSession => _token != null && baseUrl.isNotEmpty;

  Map<String, String> get _headers => {
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  dynamic _decode(http.Response resp) {
    final body = resp.body.isEmpty ? null : jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode >= 400) {
      var detail = 'Error ${resp.statusCode}';
      if (body is Map && body['detail'] != null) {
        final d = body['detail'];
        detail = d is Map && d['message'] != null ? d['message'] : d.toString();
      }
      throw ApiException(resp.statusCode, detail);
    }
    return body;
  }

  Future<void> _storeSession(String url, dynamic data) async {
    baseUrl = url;
    _token = data['access_token'];
    role = data['role'];
    mustChangePassword = data['must_change_password'] == true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', baseUrl);
    await prefs.setString('token', _token!);
    await prefs.setString('role', role);
  }

  Future<void> login(String server, String username, String password) async {
    final url = server.replaceAll(RegExp(r'/+$'), '');
    final resp = await http.post(
      Uri.parse('$url/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}',
    );
    await _storeSession(url, _decode(resp));
  }

  Future<void> signup(String server, String username, String password) async {
    final url = server.replaceAll(RegExp(r'/+$'), '');
    final resp = await http.post(
      Uri.parse('$url/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    await _storeSession(url, _decode(resp));
  }

  Future<void> logout() async {
    _token = null;
    role = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
  }

  Future<List<dynamic>> listStudents() async {
    final resp = await http.get(Uri.parse('$baseUrl/students'), headers: _headers);
    return _decode(resp) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createStudent(String rollNo, String name, String className,
      {String parentPhone = ''}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/students'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'roll_no': rollNo,
        'name': name,
        'class_name': className,
        'parent_phone': parentPhone,
      }),
    );
    return _decode(resp) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateParentPhone(int studentId, String parentPhone) async {
    final resp = await http.patch(
      Uri.parse('$baseUrl/students/$studentId'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'parent_phone': parentPhone}),
    );
    return _decode(resp) as Map<String, dynamic>;
  }

  Future<void> deleteStudent(int id) async {
    final resp = await http.delete(Uri.parse('$baseUrl/students/$id'), headers: _headers);
    _decode(resp);
  }

  Future<Map<String, dynamic>> enroll(int studentId, List<String> imagePaths) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/students/$studentId/enroll'));
    req.headers.addAll(_headers);
    for (final path in imagePaths) {
      req.files.add(await http.MultipartFile.fromPath('images', path));
    }
    final resp = await http.Response.fromStream(await req.send());
    return _decode(resp) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> recognize(String imagePath, {String? group, int? sessionId}) async {
    final params = <String>[
      if (group != null && group.isNotEmpty) 'group=${Uri.encodeQueryComponent(group)}',
      if (sessionId != null) 'session_id=$sessionId',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/attendance/recognize$query'));
    req.headers.addAll(_headers);
    req.files.add(await http.MultipartFile.fromPath('image', imagePath));
    final resp = await http.Response.fromStream(await req.send());
    return _decode(resp) as Map<String, dynamic>;
  }

  Future<List<dynamic>> listGroups() async {
    final resp = await http.get(Uri.parse('$baseUrl/students/groups'), headers: _headers);
    return _decode(resp) as List<dynamic>;
  }

  Future<Map<String, dynamic>> attendanceReport({String? day, String? group, int? sessionId}) async {
    final params = <String>[
      if (day != null) 'day=$day',
      if (group != null && group.isNotEmpty) 'group=${Uri.encodeQueryComponent(group)}',
      if (sessionId != null) 'session_id=$sessionId',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final resp = await http.get(Uri.parse('$baseUrl/attendance$query'), headers: _headers);
    return _decode(resp) as Map<String, dynamic>;
  }

  Future<List<dynamic>> myAttendance() async {
    final resp = await http.get(Uri.parse('$baseUrl/attendance/me'), headers: _headers);
    return _decode(resp) as List<dynamic>;
  }

  Future<void> deleteAttendance(int attendanceId) async {
    final resp =
        await http.delete(Uri.parse('$baseUrl/attendance/$attendanceId'), headers: _headers);
    _decode(resp);
  }

  Future<List<dynamic>> listSessions() async {
    final resp = await http.get(Uri.parse('$baseUrl/sessions'), headers: _headers);
    return _decode(resp) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createSession(String title, String groupName, String date,
      String startTime, String endTime, String entryUntil, String exitFrom, String exitUntil) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/sessions'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'group_name': groupName,
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'entry_until': entryUntil,
        'exit_from': exitFrom,
        'exit_until': exitUntil,
      }),
    );
    return _decode(resp) as Map<String, dynamic>;
  }

  Future<void> deleteSession(int sessionId) async {
    final resp = await http.delete(Uri.parse('$baseUrl/sessions/$sessionId'), headers: _headers);
    _decode(resp);
  }

  /// Schedule a repeating weekly timetable in advance. Each block becomes one
  /// session per selected weekday, with its periods attached.
  Future<Map<String, dynamic>> createTimetable(Map<String, dynamic> payload) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/sessions/timetable'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _decode(resp) as Map<String, dynamic>;
  }

  /// Turn the optional mid-block roll call on or off for one block.
  Future<void> setSpotCheckEnabled(int sessionId, bool enabled) async {
    final resp = await http.patch(
      Uri.parse('$baseUrl/sessions/$sessionId'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'spot_check_enabled': enabled}),
    );
    _decode(resp);
  }

  /// Students currently marked present in a block, for the roll call list.
  Future<Map<String, dynamic>> whoIsPresent(int sessionId) async {
    final resp =
        await http.get(Uri.parse('$baseUrl/sessions/$sessionId/present'), headers: _headers);
    return _decode(resp) as Map<String, dynamic>;
  }

  /// Record a roll call. [absentStudentIds] are those the teacher could not see;
  /// the server exempts anyone who had not arrived or had already left.
  Future<Map<String, dynamic>> runSpotCheck(int sessionId, List<int> absentStudentIds,
      {String? checkedAt}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/sessions/$sessionId/spot-check'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'absent_student_ids': absentStudentIds, 'checked_at': ?checkedAt}),
    );
    return _decode(resp) as Map<String, dynamic>;
  }

  /// Teacher correction: set a leaving time for a student who forgot to scan out.
  Future<void> overrideExit(int attendanceId, String exitAt, String note) async {
    final resp = await http.patch(
      Uri.parse('$baseUrl/attendance/$attendanceId'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'exit_at': exitAt, 'note': note}),
    );
    _decode(resp);
  }

  /// Change your own password. The only write a student token may perform.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/auth/change-password'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'current_password': currentPassword, 'new_password': newPassword}),
    );
    _decode(resp);
    mustChangePassword = false;
  }

  // --- Parent absence notifications ----------------------------------------

  /// Who would be messaged for [date]/[sessionId], with per-student
  /// notifiability and the exact message preview. Sends nothing.
  Future<Map<String, dynamic>> absentPreview({String? date, int? sessionId}) async {
    final params = <String>[
      if (date != null) 'date=$date',
      if (sessionId != null) 'session_id=$sessionId',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final resp =
        await http.get(Uri.parse('$baseUrl/notifications/absent$query'), headers: _headers);
    return _decode(resp) as Map<String, dynamic>;
  }

  /// Send absence alerts to the parents of exactly [studentIds]. The teacher
  /// chooses the list; there is no implicit send-to-everyone on the server.
  Future<Map<String, dynamic>> sendAbsenceAlerts(List<int> studentIds,
      {String? date, int? sessionId}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/notifications/absent/send'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'student_ids': studentIds,
        'date': ?date,
        'session_id': ?sessionId,
      }),
    );
    return _decode(resp) as Map<String, dynamic>;
  }

  Future<List<dynamic>> notificationLog({String? date}) async {
    final query = date == null ? '' : '?date=$date';
    final resp = await http.get(Uri.parse('$baseUrl/notifications$query'), headers: _headers);
    return _decode(resp) as List<dynamic>;
  }
}
