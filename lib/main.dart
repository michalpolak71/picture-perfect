import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'screens/sessions_screen.dart';
import 'screens/simple_draw_screen.dart';
import 'models/photo_data.dart';
import 'utils/watermark_util.dart';
import 'utils/session_manager.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    print('Error: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Interklima',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0066CC)),
        useMaterial3: true,
      ),
      home: const SessionsScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final String sessionId;
  final String sessionName;

  const CameraScreen({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  bool _permissionGranted = false;
  bool _isInitialized = false;
  bool _gpsEnabled = false;
  Position? _currentPosition;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 8.0;
  double _baseScale = 1.0;
  int _photoCount = 0;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadPhotoCount();
  }

  Future<void> _loadPhotoCount() async {
    final sessions = await SessionManager.loadSessions();
    try {
      final session = sessions.firstWhere((s) => s.id == widget.sessionId);
      setState(() => _photoCount = session.photoIds.length);
    } catch (_) {}
  }

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final locationStatus = await Permission.location.request();
    if (cameraStatus.isGranted) {
      setState(() => _permissionGranted = true);
      _initializeCamera();
      if (locationStatus.isGranted) _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _gpsEnabled = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
        _gpsEnabled = true;
      });
    } catch (e) {
      setState(() => _gpsEnabled = false);
    }
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) return;
    controller = CameraController(cameras[0], ResolutionPreset.high);
    try {
      await controller!.initialize();
      _maxZoom = await controller!.getMaxZoomLevel();
      _minZoom = await controller!.getMinZoomLevel();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (controller == null || !controller!.value.isInitialized) return;
    await _getCurrentLocation();

    try {
      final image = await controller!.takePicture();
      if (!mounted) return;

      final description = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => PhotoDescriptionScreen(
            imagePath: image.path,
            position: _currentPosition,
          ),
        ),
      );

      if (description != null) {
        await _savePhoto(image.path, description);
        setState(() => _photoCount++);
      }
    } catch (e) {
      print('Error taking picture: $e');
    }
  }

  Future<void> _savePhoto(String imagePath, String description) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/photos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'photo_$timestamp.jpg';
      final finalPath = '${photosDir.path}/$fileName';

      await File(imagePath).copy(finalPath);

      await WatermarkUtil.addWatermark(
        finalPath,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
        altitude: _currentPosition?.altitude,
      );

      final photoData = PhotoData(
        imagePath: finalPath,
        description: description,
        timestamp: timestamp,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
        sessionId: widget.sessionId,
        altitude: _currentPosition?.altitude,
      );

      final metaFile = File('${photosDir.path}/photo_$timestamp.json');
      await metaFile.writeAsString(json.encode(photoData.toJson()));

      await SessionManager.addPhotoToSession(
          widget.sessionId, timestamp.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_currentPosition != null
              ? '✓ Zdjęcie zapisane z GPS'
              : '✓ Zdjęcie zapisane (brak GPS)'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      print('Error saving photo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionGranted) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.sessionName)),
        body: const Center(child: Text('Brak uprawnień do aparatu')),
      );
    }
    if (!_isInitialized || controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.sessionName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Full screen camera
          Positioned.fill(
            child: GestureDetector(
              onScaleStart: (_) => _baseScale = _currentZoom,
              onScaleUpdate: (details) async {
                final newZoom =
                    (_baseScale * details.scale).clamp(_minZoom, _maxZoom);
                await controller!.setZoomLevel(newZoom);
                setState(() => _currentZoom = newZoom);
              },
              child: CameraPreview(controller!),
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.arrow_back,
                            color: Colors.white, size: 24),
                      ),
                    ),

                    // Session name + photo count
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder,
                              color: Colors.white70, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            widget.sessionName,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_photoCount',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // GPS indicator
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  _gpsEnabled ? Colors.green : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _gpsEnabled ? 'GPS' : 'brak GPS',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Logo bottom left
          Positioned(
            bottom: 50,
            left: 20,
            child: Image.asset('assets/logo.png', height: 28),
          ),

          // Capture button
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _takePicture,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5), width: 5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PhotoDescriptionScreen
// ============================================================
class PhotoDescriptionScreen extends StatefulWidget {
  final String imagePath;
  final Position? position;

  const PhotoDescriptionScreen({
    super.key,
    required this.imagePath,
    this.position,
  });

  @override
  State<PhotoDescriptionScreen> createState() =>
      _PhotoDescriptionScreenState();
}

class _PhotoDescriptionScreenState extends State<PhotoDescriptionScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Dodaj opis', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('ZAPISZ',
                style: TextStyle(
                    color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Photo preview
          Expanded(
            child: Stack(
              children: [
                Center(
                  child:
                      Image.file(File(widget.imagePath), fit: BoxFit.contain),
                ),
                // Edit button
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: () async {
                      final edited = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              SimpleDrawScreen(imagePath: widget.imagePath),
                        ),
                      );
                      if (edited == true && mounted) setState(() {});
                    },
                    backgroundColor: Colors.white,
                    child:
                        const Icon(Icons.edit, color: Colors.black, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // Bottom panel
          Container(
            color: Colors.grey[900],
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // GPS info
                if (widget.position != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.green, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.position!.latitude.toStringAsFixed(5)}, ${widget.position!.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                              color: Colors.greenAccent, fontSize: 11),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Colors.red.withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.location_off, color: Colors.red, size: 14),
                        SizedBox(width: 6),
                        Text('Brak GPS',
                            style:
                                TextStyle(color: Colors.redAccent, fontSize: 11)),
                      ],
                    ),
                  ),

                // Description input
                TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Dodaj opis zdjęcia...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    filled: true,
                    fillColor: Colors.grey[800],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  maxLines: 3,
                  autofocus: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
