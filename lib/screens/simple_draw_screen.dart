import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:flutter/rendering.dart';

class SimpleDrawScreen extends StatefulWidget {
  final String imagePath;

  const SimpleDrawScreen({super.key, required this.imagePath});

  @override
  State<SimpleDrawScreen> createState() => _SimpleDrawScreenState();
}

enum DrawingTool { pen, arrow, circle, text }

class _SimpleDrawScreenState extends State<SimpleDrawScreen> {
  final List<DrawnLine> lines = [];
  final List<DrawnShape> shapes = [];
  final List<DrawnText> texts = [];
  Color selectedColor = Colors.red;
  double strokeWidth = 5.0;
  DrawingTool selectedTool = DrawingTool.pen;
  Offset? shapeStart;
  Offset? _currentShapeEnd;
  final GlobalKey _imageKey = GlobalKey();

  void _handleTapForText(Offset position) {
    showDialog(
      context: context,
      builder: (context) {
        String text = '';
        return AlertDialog(
          title: const Text('Dodaj tekst'),
          content: TextField(
            onChanged: (value) => text = value,
            decoration: const InputDecoration(hintText: 'Wpisz tekst...'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () {
                if (text.isNotEmpty) {
                  setState(() {
                    texts.add(DrawnText(
                      text: text,
                      position: position,
                      color: selectedColor,
                    ));
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Dodaj'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveEdits() async {
    if (lines.isEmpty && shapes.isEmpty && texts.isEmpty) {
      Navigator.pop(context, false);
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final bytes = await File(widget.imagePath).readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) return;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      canvas.drawImage(uiImage, Offset.zero, Paint());

      final RenderBox? renderBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      final scaleX = originalImage.width /
          (renderBox?.size.width ?? originalImage.width.toDouble());
      final scaleY = originalImage.height /
          (renderBox?.size.height ?? originalImage.height.toDouble());

      for (var line in lines) {
        final paint = Paint()
          ..color = line.color
          ..strokeWidth = line.width * scaleX
          ..strokeCap = StrokeCap.round;
        for (int i = 0; i < line.path.length - 1; i++) {
          canvas.drawLine(
            Offset(line.path[i].dx * scaleX, line.path[i].dy * scaleY),
            Offset(line.path[i + 1].dx * scaleX, line.path[i + 1].dy * scaleY),
            paint,
          );
        }
      }

      for (var shape in shapes) {
        final paint = Paint()
          ..color = shape.color
          ..strokeWidth = shape.width * scaleX
          ..style = PaintingStyle.stroke;

        final start = Offset(shape.start.dx * scaleX, shape.start.dy * scaleY);
        final end = Offset(shape.end.dx * scaleX, shape.end.dy * scaleY);

        if (shape.tool == DrawingTool.arrow) {
          canvas.drawLine(start, end, paint);
          final angle = atan2(end.dy - start.dy, end.dx - start.dx);
          final arrowSize = 25.0 * scaleX;
          final path = Path()
            ..moveTo(end.dx, end.dy)
            ..lineTo(end.dx - arrowSize * cos(angle - pi / 6),
                end.dy - arrowSize * sin(angle - pi / 6))
            ..moveTo(end.dx, end.dy)
            ..lineTo(end.dx - arrowSize * cos(angle + pi / 6),
                end.dy - arrowSize * sin(angle + pi / 6));
          canvas.drawPath(path, paint);
        } else if (shape.tool == DrawingTool.circle) {
          final radius = (end - start).distance / 2;
          final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
          canvas.drawCircle(center, radius, paint);
        }
      }

      for (var textItem in texts) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: textItem.text,
            style: TextStyle(
              color: textItem.color,
              fontSize: 32 * scaleX,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(textItem.position.dx * scaleX, textItem.position.dy * scaleY),
        );
      }

      final picture = recorder.endRecording();
      final finalImage =
          await picture.toImage(originalImage.width, originalImage.height);
      final byteData =
          await finalImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final image = img.decodeImage(pngBytes);
      if (image != null) {
        final jpg = img.encodeJpg(image, quality: 95);
        await File(widget.imagePath).writeAsBytes(jpg);
      }

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd zapisu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edytuj zdjęcie'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: () {
              setState(() {
                if (texts.isNotEmpty) {
                  texts.removeLast();
                } else if (shapes.isNotEmpty) {
                  shapes.removeLast();
                } else if (lines.isNotEmpty) {
                  lines.removeLast();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveEdits,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _toolButton(DrawingTool.pen, Icons.edit, 'Rysuj'),
                    _toolButton(DrawingTool.arrow, Icons.arrow_forward, 'Strzałka'),
                    _toolButton(DrawingTool.circle, Icons.circle_outlined, 'Kółko'),
                    _toolButton(DrawingTool.text, Icons.text_fields, 'Tekst'),
                  ],
                ),
                const SizedBox(height: 4),
                if (selectedTool == DrawingTool.text)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Dotknij miejsce na zdjęciu aby wstawić tekst',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Colors.red,
                      Colors.blue,
                      Colors.green,
                      Colors.yellow,
                      Colors.black,
                      Colors.white,
                    ].map((c) => Expanded(child: _colorButton(c))).toList(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.grey[300],
              child: Stack(
                children: [
                  Center(
                    child: Image.file(
                      File(widget.imagePath),
                      key: _imageKey,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      onTapUp: (details) {
                        if (selectedTool == DrawingTool.text) {
                          _handleTapForText(details.localPosition);
                        }
                      },
                      onPanStart: (details) {
                        if (selectedTool == DrawingTool.pen) {
                          setState(() {
                            lines.add(DrawnLine(
                                [details.localPosition], selectedColor, strokeWidth));
                          });
                        } else if (selectedTool != DrawingTool.text) {
                          setState(() {
                            shapeStart = details.localPosition;
                            _currentShapeEnd = details.localPosition;
                          });
                        }
                      },
                      onPanUpdate: (details) {
                        if (selectedTool == DrawingTool.pen && lines.isNotEmpty) {
                          setState(() {
                            lines.last.path.add(details.localPosition);
                          });
                        } else if (selectedTool != DrawingTool.text &&
                            shapeStart != null) {
                          setState(() {
                            _currentShapeEnd = details.localPosition;
                          });
                        }
                      },
                      onPanEnd: (details) {
                        if (selectedTool != DrawingTool.pen &&
                            selectedTool != DrawingTool.text &&
                            shapeStart != null &&
                            _currentShapeEnd != null) {
                          setState(() {
                            shapes.add(DrawnShape(
                              start: shapeStart!,
                              end: _currentShapeEnd!,
                              color: selectedColor,
                              width: strokeWidth,
                              tool: selectedTool,
                            ));
                            shapeStart = null;
                            _currentShapeEnd = null;
                          });
                        }
                      },
                      child: CustomPaint(
                        painter: DrawingPainter(
                          lines: lines,
                          shapes: shapes,
                          texts: texts,
                          previewStart: shapeStart,
                          previewEnd: _currentShapeEnd,
                          previewTool: selectedTool,
                          previewColor: selectedColor,
                          previewWidth: strokeWidth,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(DrawingTool tool, IconData icon, String label) {
    final isSelected = selectedTool == tool;
    return GestureDetector(
      onTap: () => setState(() => selectedTool = tool),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: isSelected
            ? BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.black : Colors.grey, size: 32),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? Colors.black : Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _colorButton(Color color) {
    final isSelected = color == selectedColor;
    return GestureDetector(
      onTap: () => setState(() => selectedColor = color),
      child: Container(
        height: 40,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: isSelected ? Colors.black : Colors.grey,
              width: isSelected ? 4 : 2),
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

class DrawnShape {
  final Offset start, end;
  final Color color;
  final double width;
  final DrawingTool tool;
  DrawnShape(
      {required this.start,
      required this.end,
      required this.color,
      required this.width,
      required this.tool});
}

class DrawnText {
  final String text;
  final Offset position;
  final Color color;
  DrawnText({required this.text, required this.position, required this.color});
}

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final List<DrawnShape> shapes;
  final List<DrawnText> texts;
  final Offset? previewStart;
  final Offset? previewEnd;
  final DrawingTool? previewTool;
  final Color? previewColor;
  final double? previewWidth;

  DrawingPainter({
    required this.lines,
    required this.shapes,
    required this.texts,
    this.previewStart,
    this.previewEnd,
    this.previewTool,
    this.previewColor,
    this.previewWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var line in lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = line.width
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < line.path.length - 1; i++) {
        canvas.drawLine(line.path[i], line.path[i + 1], paint);
      }
    }

    for (var shape in shapes) {
      _drawShape(canvas, shape.start, shape.end, shape.color, shape.width, shape.tool);
    }

    if (previewStart != null &&
        previewEnd != null &&
        previewTool != null &&
        previewTool != DrawingTool.pen &&
        previewTool != DrawingTool.text) {
      _drawShape(canvas, previewStart!, previewEnd!, previewColor ?? Colors.red,
          previewWidth ?? 5.0, previewTool!);
    }

    for (var textItem in texts) {
      final textPainter = TextPainter(
        text: TextSpan(
            text: textItem.text,
            style: TextStyle(
                color: textItem.color,
                fontSize: 32,
                fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, textItem.position);
    }
  }

  void _drawShape(Canvas canvas, Offset start, Offset end, Color color,
      double width, DrawingTool tool) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;

    if (tool == DrawingTool.arrow) {
      canvas.drawLine(start, end, paint);
      final angle = atan2(end.dy - start.dy, end.dx - start.dx);
      const arrowSize = 25.0;
      final path = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(end.dx - arrowSize * cos(angle - pi / 6),
            end.dy - arrowSize * sin(angle - pi / 6))
        ..moveTo(end.dx, end.dy)
        ..lineTo(end.dx - arrowSize * cos(angle + pi / 6),
            end.dy - arrowSize * sin(angle + pi / 6));
      canvas.drawPath(path, paint);
    } else if (tool == DrawingTool.circle) {
      final radius = (end - start).distance / 2;
      final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
