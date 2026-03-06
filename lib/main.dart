import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'screens/photo_list_screen.dart';
import 'screens/simple_draw_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/work_tracking_screen.dart';
import 'models/photo_data.dart';
import 'models/photo_session.dart';
import 'utils/watermark_util.dart';
import 'utils/session_manager.dart';
import 'widgets/floor_picker_widget.dart';

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
      title: 'Picture Perfect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  bool _permissionGranted = false;
  bool _isInitialized = false;
  bool _gpsEnabled = true;
  Position? _currentPosition;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 8.0;
  double _baseScale = 1.0;
  String? _selectedSessionId;
  String _selectedSessionName = 'Brak sesji';

  // V9: Floor/height state
  FloorData? _selectedFloor;
  double? _customHeight;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
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
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
        _gpsEnabled = true;
      });
    } catch (e) {
      print('Error getting location: $e');
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
    if (_gpsEnabled) await _getCurrentLocation();

    try {
      final image = await controller!.takePicture();
      if (!mounted) return;

      final description = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => PhotoDescriptionScreen(
            imagePath: image.path,
            position: _currentPosition,
            selectedFloor: _selectedFloor,
          ),
        ),
      );

      if (description != null) {
        await _savePhoto(image.path, description);
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

      // V9: Watermark with floor + height
      await WatermarkUtil.addWatermark(
        finalPath,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
        altitude: _currentPosition?.altitude,
        floorLabel: _selectedFloor?.label,
        relativeHeight: _selectedFloor?.defaultHeight,
      );

      // V9: Save metadata with floor/height
      final photoData = PhotoData(
        imagePath: finalPath,
        description: description,
        timestamp: timestamp,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
        sessionId: _selectedSessionId,
        altitude: _currentPosition?.altitude,
        floor: _selectedFloor?.number,
        relativeHeight: _selectedFloor?.defaultHeight,
        floorLabel: _selectedFloor?.label,
      );

      final metaFile = File('${photosDir.path}/photo_$timestamp.json');
      await metaFile.writeAsString(json.encode(photoData.toJson()));

      if (_selectedSessionId != null) {
        await SessionManager.addPhotoToSession(
            _selectedSessionId!, timestamp.toString());
      }

      if (mounted) {
        String msg = _currentPosition != null
            ? 'Zdjęcie zapisane z GPS'
            : 'Zdjęcie zapisane';
        if (_selectedFloor != null) {
          msg += ' • ${_selectedFloor!.label}';
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      print('Error saving photo: $e');
    }
  }

  Future<void> _showSessionSelector() async {
    final sessions = await SessionManager.loadSessions();
    if (!mounted) return;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wybierz sesję'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Brak sesji'),
                onTap: () => Navigator.pop(context, 'none'),
              ),
              const Divider(),
              ...sessions.map((session) => ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(session.name),
                    subtitle: Text('${session.photoIds.length} zdjęć'),
                    onTap: () => Navigator.pop(context, session.id),
                  )),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Utwórz nową sesję'),
                onTap: () => Navigator.pop(context, 'create'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == 'none') {
      setState(() {
        _selectedSessionId = null;
        _selectedSessionName = 'Brak sesji';
      });
    } else if (result == 'create') {
      final ctrl = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nowa sesja'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Nazwa sesji',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Anuluj')),
            TextButton(
                onPressed: () => Navigator.pop(context, ctrl.text),
                child: const Text('Utwórz')),
          ],
        ),
      );
      if (name != null && name.isNotEmpty) {
        final session = await SessionManager.createSession(name);
        setState(() {
          _selectedSessionId = session.id;
          _selectedSessionName = session.name;
        });
      }
    } else if (result != null) {
      final session = sessions.firstWhere((s) => s.id == result);
      setState(() {
        _selectedSessionId = session.id;
        _selectedSessionName = session.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionGranted) {
      return const Scaffold(
          body: Center(child: Text('Brak uprawnień do aparatu')));
    }
    if (!_isInitialized || controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          // Camera preview with pinch zoom
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

          // Top left: Logo + GPS dot
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/logo.png', height: 32),
                    const SizedBox(width: 8),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _gpsEnabled ? Colors.green : Colors.red,
                        boxShadow: [
                          BoxShadow(
                            color: (_gpsEnabled ? Colors.green : Colors.red)
                                .withOpacity(0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Top right: Hamburger menu
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.menu, color: Colors.white, size: 32),
                padding: const EdgeInsets.all(20),
                onPressed: _showMainMenu,
              ),
            ),
          ),

          // V9: Floor picker - bottom left above capture button
          Positioned(
            bottom: 140,
            left: 16,
            right: 16,
            child: Row(
              children: [
                FloorPickerWidget(
                  selectedFloor: _selectedFloor?.number,
                  onFloorSelected: (floor) {
                    setState(() => _selectedFloor = floor);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            '📍 ${floor.label} (${floor.defaultHeight >= 0 ? '+' : ''}${floor.defaultHeight.toStringAsFixed(1)}m)'),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                if (_selectedFloor != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _selectedFloor = null),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white70, size: 16),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // V9: Floor info chip (shows selected floor)
          if (_selectedFloor != null)
            Positioned(
              bottom: 175,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_selectedFloor!.label} • ${_selectedFloor!.defaultHeight >= 0 ? '+' : ''}${_selectedFloor!.defaultHeight.toStringAsFixed(1)}m',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),

          // Capture button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _takePicture,
                child: Container(
                  width: 110,
                  height: 110,
                  alignment: Alignment.center,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.5), width: 6),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMainMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.access_time, size: 32),
                title:
                    const Text('Praca', style: TextStyle(fontSize: 18)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => WorkTrackingScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open, size: 32),
                title:
                    const Text('Sesje', style: TextStyle(fontSize: 18)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SessionsScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, size: 32),
                title:
                    const Text('Galeria', style: TextStyle(fontSize: 18)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PhotoListScreen()));
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.folder,
                    size: 32,
                    color: _selectedSessionId == null
                        ? Colors.grey
                        : Colors.blue),
                title: Text(_selectedSessionName,
                    style: const TextStyle(fontSize: 16)),
                subtitle: const Text('Aktualna sesja'),
                trailing: const Icon(Icons.edit),
                onTap: () {
                  Navigator.pop(context);
                  _showSessionSelector();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PhotoDescriptionScreen V9 - with floor info display
// ============================================================
class PhotoDescriptionScreen extends StatefulWidget {
  final String imagePath;
  final Position? position;
  final FloorData? selectedFloor;

  const PhotoDescriptionScreen({
    super.key,
    required this.imagePath,
    this.position,
    this.selectedFloor,
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
          IconButton(
            icon: const Icon(Icons.check, size: 28),
            onPressed: () => Navigator.pop(context, _controller.text),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: Image.file(File(widget.imagePath),
                      fit: BoxFit.contain),
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton(
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
                    child: const Icon(Icons.edit, color: Colors.black),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.grey[900],
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // GPS chip
                if (widget.position != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green[900]!.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.green, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'GPS: ${widget.position!.latitude.toStringAsFixed(5)}, ${widget.position!.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.greenAccent),
                        ),
                      ],
                    ),
                  ),

                // V9: Floor chip
                if (widget.selectedFloor != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue[900]!.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.layers,
                            color: Colors.blue, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.selectedFloor!.label} • ${widget.selectedFloor!.defaultHeight >= 0 ? '+' : ''}${widget.selectedFloor!.defaultHeight.toStringAsFixed(1)}m',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.lightBlueAccent),
                        ),
                      ],
                    ),
                  ),

                // Description field
                TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Dodaj opis zdjęcia...',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: Colors.grey[800],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  maxLines: 2,
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
