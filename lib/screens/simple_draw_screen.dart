import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edytuj zdjęcie'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: () {
              setState(() {
                if (shapes.isNotEmpty) {
                  shapes.removeLast();
                } else if (lines.isNotEmpty) {
                  lines.removeLast();
                } else if (texts.isNotEmpty) {
                  texts.removeLast();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _toolButton(DrawingTool.pen, Icons.edit, 'Rysuj'),
                    _toolButton(DrawingTool.arrow, Icons.arrow_forward, 'Strzałka'),
                    _toolButton(DrawingTool.circle, Icons.circle_outlined, 'Kółko'),
                    GestureDetector(
                      onTap: _addText,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: const [
                            Icon(Icons.text_fields, color: Colors.grey, size: 32),
                            SizedBox(height: 4),
                            Text('Tekst', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                    child: Image.file(File(widget.imagePath), fit: BoxFit.contain),
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
