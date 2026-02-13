import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

class SimpleDrawScreen extends StatefulWidget {
  final String imagePath;

  const SimpleDrawScreen({super.key, required this.imagePath});

  @override
  State<SimpleDrawScreen> createState() => _SimpleDrawScreenState();
}

class _SimpleDrawScreenState extends State<SimpleDrawScreen> {
  final List<DrawnLine> lines = [];
  Color selectedColor = Colors.red;
  double strokeWidth = 3.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rysuj na zdjęciu'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: () {
              setState(() {
                if (lines.isNotEmpty) lines.removeLast();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Tools
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _colorButton(Colors.red),
                _colorButton(Colors.blue),
                _colorButton(Colors.green),
                _colorButton(Colors.yellow),
                _colorButton(Colors.black),
                _colorButton(Colors.white),
              ],
            ),
          ),
          // Canvas
          Expanded(
            child: GestureDetector(
              onPanStart: (details) {
                setState(() {
                  lines.add(DrawnLine([details.localPosition], selectedColor, strokeWidth));
                });
              },
              onPanUpdate: (details) {
                setState(() {
                  lines.last.path.add(details.localPosition);
                });
              },
              child: CustomPaint(
                painter: DrawingPainter(
                  lines: lines,
                  imagePath: widget.imagePath,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorButton(Color color) {
    final isSelected = color == selectedColor;
    return GestureDetector(
      onTap: () => setState(() => selectedColor = color),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey,
            width: isSelected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class DrawnLine {
  final List<Offset> path;
  final Color color;
  final double width;

  DrawnLine(this.path, this.color, this.width);
}

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final String imagePath;
  ui.Image? _image;

  DrawingPainter({required this.lines, required this.imagePath});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw image
    if (_image == null) {
      _loadImage();
    } else {
      canvas.drawImage(_image!, Offset.zero, Paint());
    }

    // Draw lines
    for (var line in lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = line.width
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < line.path.length - 1; i++) {
        canvas.drawLine(line.path[i], line.path[i + 1], paint);
      }
    }
  }

  Future<void> _loadImage() async {
    final file = File(imagePath);
    final bytes = await file.readAsBytes();
    _image = await decodeImageFromList(bytes);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
