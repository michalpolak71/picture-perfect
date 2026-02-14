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
  final GlobalKey _imageKey = GlobalKey();

  void _addText() {
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
                      position: const Offset(100, 200),
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

      // Load original image
      final bytes = await File(widget.imagePath).readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) return;

      // Create canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Draw original image
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      canvas.drawImage(uiImage, Offset.zero, Paint());

      // Get scale factor
      final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
      final scaleX = originalImage.width / (renderBox?.size.width ?? originalImage.width.toDouble());
      final scaleY = originalImage.height / (renderBox?.size.height ?? originalImage.height.toDouble());

      // Draw lines
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

      // Draw shapes
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
            ..lineTo(end.dx - arrowSize * cos(angle - pi / 6), end.dy - arrowSize * sin(angle - pi / 6))
            ..moveTo(end.dx, end.dy)
            ..lineTo(end.dx - arrowSize * cos(angle + pi / 6), end.dy - arrowSize * sin(angle + pi / 6));
          canvas.drawPath(path, paint);
        } else if (shape.tool == DrawingTool.circle) {
          final radius = ((end - start).distance / 2) * scaleX;
          final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
          canvas.drawCircle(center, radius, paint);
        }
      }

      // Draw texts
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

      // Convert to image
      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(originalImage.width, originalImage.height);
      final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) return;

      // Convert to JPG and save
      final pngBytes = byteData.buffer.asUint8List();
      final image = img.decodeImage(pngBytes);
      if (image != null) {
        final jpg = img.encodeJpg(image, quality: 95);
        await File(widget.imagePath).writeAsBytes(jpg);
      }

      if (mounted) {
        Navigator.pop(context); // Close loading
        Navigator.pop(context, true); // Return success
      }
    } catch (e) {
      print('Error saving edits: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd zapisu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen image with drawing
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                if (selectedTool == DrawingTool.pen) {
                  setState(() {
                    lines.add(DrawnLine([details.localPosition], selectedColor, strokeWidth));
                  });
                } else if (selectedTool == DrawingTool.arrow || selectedTool == DrawingTool.circle) {
                  setState(() {
                    shapeStart = details.localPosition;
                  });
                }
              },
              onPanUpdate: (details) {
                setState(() {
                  if (selectedTool == DrawingTool.pen && lines.isNotEmpty) {
                    lines.last.points.add(details.localPosition);
                  }
                });
              },
              onPanEnd: (details) {
                if (selectedTool == DrawingTool.arrow && shapeStart != null) {
                  setState(() {
                    shapes.add(DrawnShape(
                      start: shapeStart!,
                      end: details.localPosition,
                      color: selectedColor,
                      type: ShapeType.arrow,
                    ));
                    shapeStart = null;
                  });
                } else if (selectedTool == DrawingTool.circle && shapeStart != null) {
                  setState(() {
                    shapes.add(DrawnShape(
                      start: shapeStart!,
                      end: details.localPosition,
                      color: selectedColor,
                      type: ShapeType.circle,
                    ));
                    shapeStart = null;
                  });
                }
              },
              child: RepaintBoundary(
                key: _imageKey,
                child: Stack(
                  children: [
                    Center(
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                    CustomPaint(
                      painter: DrawingPainter(
                        lines: lines,
                        shapes: shapes,
                        texts: texts,
                        currentShape: shapeStart,
                        selectedTool: selectedTool,
                        selectedColor: selectedColor,
                      ),
                      size: Size.infinite,
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Top floating buttons
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ),
                    // Save button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.check, color: Colors.white, size: 28),
                        onPressed: _saveEdits,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Bottom floating toolbar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tools row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _floatingToolButton(DrawingTool.pen, Icons.edit, 'Rysuj'),
                        _floatingToolButton(DrawingTool.arrow, Icons.arrow_forward, 'Strzałka'),
                        _floatingToolButton(DrawingTool.circle, Icons.circle_outlined, 'Kółko'),
                        _floatingToolButton(DrawingTool.text, Icons.text_fields, 'Tekst', onTap: _addText),
                        // Undo button
                        _floatingActionButton(Icons.undo, 'Cofnij', () {
                          setState(() {
                            if (shapes.isNotEmpty) {
                              shapes.removeLast();
                            } else if (lines.isNotEmpty) {
                              lines.removeLast();
                            } else if (texts.isNotEmpty) {
                              texts.removeLast();
                            }
                          });
                        }),
                      ],
                    ),
                    
                    // Color palette (show only when tool selected)
                    if (selectedTool != DrawingTool.text) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
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
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingToolButton(DrawingTool tool, IconData icon, String label, {VoidCallback? onTap}) {
    final isSelected = selectedTool == tool;
    return GestureDetector(
      onTap: onTap ?? () {
        setState(() {
          selectedTool = tool;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[700],
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _floatingActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.grey[700], size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorButton(Color color) {
    final isSelected = selectedColor == color;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedColor = color;
        });
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[300]!,
            width: isSelected ? 4 : 2,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.blue.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)]
              : null,
        ),
      ),
    );
  }

  Widget _toolButton(DrawingTool tool, IconData icon, String label) {
    final isSelected = selectedTool == tool;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedTool = tool;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.blue : Colors.grey,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Colors.blue : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Drawing classes
enum ShapeType { arrow, circle }

class DrawnLine {
                    child: Image.file(
                      File(widget.imagePath),
                      key: _imageKey,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      onPanStart: (details) {
                        if (selectedTool == DrawingTool.pen) {
                          setState(() {
                            lines.add(DrawnLine([details.localPosition], selectedColor, strokeWidth));
                          });
                        } else {
                          shapeStart = details.localPosition;
                        }
                      },
                      onPanUpdate: (details) {
                        if (selectedTool == DrawingTool.pen && lines.isNotEmpty) {
                          setState(() {
                            lines.last.path.add(details.localPosition);
                          });
                        }
                      },
                      onPanEnd: (details) {
                        if (selectedTool != DrawingTool.pen && shapeStart != null) {
                          setState(() {
                            shapes.add(DrawnShape(
                              start: shapeStart!,
                              end: details.localPosition,
                              color: selectedColor,
                              width: strokeWidth,
                              tool: selectedTool,
                            ));
                          });
                          shapeStart = null;
                        }
                      },
                      child: CustomPaint(
                        painter: DrawingPainter(lines: lines, shapes: shapes, texts: texts),
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
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.blue : Colors.grey, size: 32),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: isSelected ? Colors.blue : Colors.grey)),
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
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey, width: isSelected ? 4 : 2),
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
  DrawnShape({required this.start, required this.end, required this.color, required this.width, required this.tool});
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

  DrawingPainter({required this.lines, required this.shapes, required this.texts});

  @override
  void paint(Canvas canvas, Size size) {
    for (var line in lines) {
      final paint = Paint()..color = line.color..strokeWidth = line.width..strokeCap = StrokeCap.round;
      for (int i = 0; i < line.path.length - 1; i++) {
        canvas.drawLine(line.path[i], line.path[i + 1], paint);
      }
    }

    for (var shape in shapes) {
      final paint = Paint()..color = shape.color..strokeWidth = shape.width..style = PaintingStyle.stroke;
      if (shape.tool == DrawingTool.arrow) {
        canvas.drawLine(shape.start, shape.end, paint);
        final angle = atan2(shape.end.dy - shape.start.dy, shape.end.dx - shape.start.dx);
        const arrowSize = 25.0;
        final path = Path()
          ..moveTo(shape.end.dx, shape.end.dy)
          ..lineTo(shape.end.dx - arrowSize * cos(angle - pi / 6), shape.end.dy - arrowSize * sin(angle - pi / 6))
          ..moveTo(shape.end.dx, shape.end.dy)
          ..lineTo(shape.end.dx - arrowSize * cos(angle + pi / 6), shape.end.dy - arrowSize * sin(angle + pi / 6));
        canvas.drawPath(path, paint);
      } else if (shape.tool == DrawingTool.circle) {
        final radius = (shape.end - shape.start).distance / 2;
        final center = Offset((shape.start.dx + shape.end.dx) / 2, (shape.start.dy + shape.end.dy) / 2);
        canvas.drawCircle(center, radius, paint);
      }
    }

    for (var textItem in texts) {
      final textPainter = TextPainter(
        text: TextSpan(text: textItem.text, style: TextStyle(color: textItem.color, fontSize: 32, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, textItem.position);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
