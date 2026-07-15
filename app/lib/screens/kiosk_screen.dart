import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import 'widgets/face_overlay.dart';

const _sound = MethodChannel('face_attendance/sound');

class KioskScreen extends StatefulWidget {
  final String? group;
  final int? sessionId;
  final String? sessionTitle;
  const KioskScreen({super.key, this.group, this.sessionId, this.sessionTitle});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  CameraController? _camera;
  Timer? _timer;
  bool _processing = false;
  bool _paused = false;

  String _message = 'Stand in front of the camera';
  Color _color = Colors.white;
  IconData _icon = Icons.face_retouching_natural;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _camera = CameraController(front, ResolutionPreset.medium, enableAudio: false);
    await _camera!.initialize();
    if (!mounted) return;
    setState(() {});
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_processing || _paused || _camera == null || !_camera!.value.isInitialized) return;
    _processing = true;
    String? path;
    try {
      final file = await _camera!.takePicture();
      path = file.path;
      final result = await ApiClient.instance
          .recognize(path, group: widget.group, sessionId: widget.sessionId);
      if (!mounted) return;

      if (result['matched'] == true) {
        final student = result['student'];
        final event = result['event'] as String?;
        final already = result['already_marked'] == true ||
            event == 'entry_already' ||
            event == 'exit_already';
        final failure = event == 'no_entry';
        if (!already && !failure) {
          try {
            _sound.invokeMethod('playRing');
            Future.delayed(const Duration(seconds: 1), () => _sound.invokeMethod('stopRing'));
          } on PlatformException {
            // sound is best-effort; attendance is already saved
          }
        }
        setState(() {
          if (failure) {
            _icon = Icons.error_outline;
            _color = Colors.red;
            _message =
                '${student['name']}, no entry record found.\nYou must scan at the start of class too.';
          } else if (already) {
            _icon = Icons.info;
            _color = Colors.blue;
            _message = event == 'exit_already'
                ? '${student['name']}, exit already recorded at ${result['exit_at']}'
                : '${student['name']}, already marked at ${result['marked_at'] ?? ''}';
          } else if (event == 'exit_marked') {
            _icon = Icons.logout;
            _color = Colors.green;
            _message = 'Goodbye ${student['name']}!\nExit recorded ✔';
          } else {
            _icon = Icons.check_circle;
            _color = Colors.green;
            _message = event == 'entry_marked'
                ? 'Welcome ${student['name']}!\nEntry marked ✔'
                : 'Welcome ${student['name']}!\nAttendance marked ✔';
          }
        });
        _paused = true;
        await Future.delayed(const Duration(seconds: 3));
        _paused = false;
        if (mounted) {
          setState(() {
            _icon = Icons.face_retouching_natural;
            _color = Colors.white;
            _message = 'Stand in front of the camera';
          });
        }
      } else if (result['reason'] == 'window_closed') {
        setState(() {
          _icon = Icons.schedule;
          _color = Colors.orange;
          _message =
              'Attendance window is closed.\nEntry: ${result['entry_window']}\nExit: ${result['exit_window']}';
        });
      } else if (result['reason'] == 'wrong_day') {
        setState(() {
          _icon = Icons.event_busy;
          _color = Colors.orange;
          _message = 'This session is scheduled for ${result['session_date']}';
        });
      } else if (result['reason'] == 'no_face') {
        setState(() {
          _icon = Icons.face_retouching_natural;
          _color = Colors.white;
          _message = 'Position your face inside the oval';
        });
      } else if (result['reason'] == 'multiple_faces') {
        setState(() {
          _icon = Icons.groups;
          _color = Colors.orange;
          _message = 'One person at a time please';
        });
      } else if (result['reason'] == 'not_centered') {
        setState(() {
          _icon = Icons.center_focus_strong;
          _color = Colors.orange;
          _message = 'Bring your face into the oval';
        });
      } else if (result['reason'] == 'turned_away') {
        setState(() {
          _icon = Icons.face_retouching_natural;
          _color = Colors.orange;
          _message = 'Look straight at the camera';
        });
      } else if (result['reason'] == 'too_dark') {
        setState(() {
          _icon = Icons.brightness_low;
          _color = Colors.orange;
          _message = 'Too dark here\nMove to brighter light';
        });
      } else if (result['reason'] == 'spoof') {
        setState(() {
          _icon = Icons.no_photography;
          _color = Colors.red;
          _message = 'Photo detected!\nPlease show your real face';
        });
      } else {
        setState(() {
          _icon = Icons.help_outline;
          _color = Colors.orange;
          _message = 'Face not recognized.\nMove closer and look at the camera.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _icon = Icons.wifi_off;
          _color = Colors.red;
          _message = 'Server error: $e';
        });
      }
    } finally {
      if (path != null) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      _processing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _camera != null && _camera!.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_camera!),
                FaceOverlay(color: _color),
                Positioned(
                  top: 48,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      Icon(_icon, color: _color, size: 56),
                      const SizedBox(height: 8),
                      Text(
                        _message,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _color, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 40,
                  left: 4,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                if (widget.sessionTitle != null || widget.group != null)
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Text(
                      widget.sessionTitle != null
                          ? 'Session: ${widget.sessionTitle}'
                          : 'Group: ${widget.group}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),
              ],
            ),
    );
  }
}
