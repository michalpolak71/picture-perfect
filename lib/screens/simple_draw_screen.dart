import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

class SimpleDrawScreen extends StatefulWidget {
  final String imagePath;

  const SimpleDrawScreen({super.key, required this.imagePath});

  @override
  State<SimpleDrawScreen> createState() => _SimpleDrawScreenState();
}

class _SimpleDrawScreenState extends State<SimpleDrawScreen> {
  final List<DrawnLine> _lines = [];
  DrawnLine? _currentLine;
  Color _selectedColor = Colors.red;
  double _strokeWidth = 3.0;
  final GlobalKey _repaintKey = GlobalKey();

  final List<Color> _colors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.white,
    Colors.black,
  ];

  Future<void> _saveDrawing() async {
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      await File(widget.imagePath).writeAsBytes(bytes);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      print('Save drawing error: $e');
      if (mounted) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        title: const Text('Edytuj zdjęcie'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _lines.isEmpty
                ? null
                : () => setState(() => _lines.removeLast()),
          ),
          TextButton(
            onPressed: _saveDrawing,
            child: const Text('ZAPISZ',
                style: TextStyle(
                    color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Drawing area
          Expanded(
            child: RepaintBoundary(
              key: _repaintKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(widget.imagePath), fit: BoxFit.contain),
                  GestureDetector(
                    onPanStart: (d) {
                      setState(() {
                        _currentLine = DrawnLine(
                          points: [d.localPosition],
                          color: _selectedColor,
                          width: _strokeWidth,
                        );
                      });
                    },
                    onPanUpdate: (d) {
                      setState(() {
                        _currentLine?.points.add(d.localPosition);
                      });
                    },
                    onPanEnd: (_) {
                      setState(() {
                        if (_currentLine != null) {
                          _lines.add(_currentLine!);
                          _currentLine = null;
                        }
                      });
                    },
                    child: CustomPaint(
                      painter: DrawingPainter(
                        lines: _lines,
                        currentLine: _currentLine,
                      ),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Toolbar
          Container(
            color: Colors.grey[900],
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Colors
                ...(_colors.map((color) => GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selectedColor == color
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ))),

                const Spacer(),

                // Stroke width
                const Icon(Icons.line_weight,
                    color: Colors.white70, size: 18),
                Slider(
                  value: _strokeWidth,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (v) => setState(() => _strokeWidth = v),
                  activeColor: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DrawnLine {
  final List<Offset> points;
  final Color color;
  final double width;

  DrawnLine({
    required this.points,
    required this.color,
    required this.width,
  });
}

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final DrawnLine? currentLine;

  DrawingPainter({required this.lines, this.currentLine});

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in [...lines, if (currentLine != null) currentLine!]) {
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = line.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      for (int i = 0; i < line.points.length - 1; i++) {
        canvas.drawLine(line.points[i], line.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}
