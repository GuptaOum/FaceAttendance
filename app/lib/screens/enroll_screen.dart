import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import 'widgets/face_overlay.dart';

const _poses = [
  'Look straight at the camera',
  'Turn head slightly LEFT',
  'Turn head slightly RIGHT',
  'Tilt head slightly UP',
  'Look straight and smile',
];

class EnrollScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  const EnrollScreen({super.key, required this.studentId, required this.studentName});

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  CameraController? _camera;
  final List<String> _captured = [];
  bool _busy = false;
  String? _status;

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
    _camera = CameraController(front, ResolutionPreset.high, enableAudio: false);
    await _camera!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _capture() async {
    if (_camera == null || !_camera!.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await _camera!.takePicture();
      _captured.add(file.path);
      setState(() => _status = null);
    } catch (e) {
      setState(() => _status = 'Capture failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _status = 'Uploading and processing faces...';
    });
    try {
      final result = await ApiClient.instance.enroll(widget.studentId, _captured);
      if (!mounted) return;
      final rejected = result['rejected'] as List<dynamic>;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enrollment complete'),
          content: Text(
            '${result['enrolled_images']} face images enrolled for ${widget.studentName}.'
            '${rejected.isEmpty ? '' : '\n\nRejected: ${rejected.map((r) => r['reason']).join(', ')}'}',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() {
        _status = 'Enrollment failed: ${e.message}\nRetake the photos and try again.';
        _captured.clear();
      });
    } catch (e) {
      setState(() => _status = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _camera != null && _camera!.value.isInitialized;
    final done = _captured.length >= _poses.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text('Enroll ${widget.studentName}')),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_camera!),
                      const FaceOverlay(),
                      Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Text(
                          done ? 'All photos captured!' : 'Photo ${_captured.length + 1} of ${_poses.length}\n${_poses[_captured.length]}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_status != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_status!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.orange)),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: _busy || _captured.isEmpty
                                ? null
                                : () => setState(() => _captured.clear()),
                            child: const Text('Retake all'),
                          ),
                          FloatingActionButton.large(
                            onPressed: _busy || done ? null : _capture,
                            child: const Icon(Icons.camera),
                          ),
                          FilledButton(
                            onPressed: _busy || !done ? null : _upload,
                            child: _busy
                                ? const SizedBox(
                                    width: 20, height: 20, child: CircularProgressIndicator())
                                : const Text('Upload'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
