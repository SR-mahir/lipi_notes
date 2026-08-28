import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/stroke_model.dart';
import '../models/workspace_models.dart';
import '../models/db_helper.dart';

class PDFExporter {
  static List<StrokePoint> _deserializePoints(String dataString) {
    if (dataString.isEmpty) return [];
    return dataString.split(' ').map((pair) {
      final coordinates = pair.split(',');
      final dx = double.tryParse(coordinates[0]) ?? 0.0;
      final dy = double.tryParse(coordinates[1]) ?? 0.0;
      return StrokePoint(
        point: Offset(dx, dy),
        pressure: 1.0,
        timestamp: DateTime.now(),
      );
    }).toList();
  }

  static Future<void> exportNotebook(Notebook notebook) async {
    final pdf = pw.Document();

    // 1. Fetch pages
    final pagesData = await DBHelper.getPagesForNotebook(notebook.id!);
    final pages = pagesData.map((map) => NotebookPage.fromMap(map)).toList();

    for (var page in pages) {
      // 2. Fetch strokes for each page
      final strokesData = await DBHelper.getSavedStrokesForPage(page.id!);
      final List<DrawingStroke> pageStrokes = [];
      for (var row in strokesData) {
        final points = _deserializePoints(row['path_string'] as String);
        if (points.isNotEmpty) {
          final penTypeString = row['pen_type'] as String? ?? 'fountain';
          final penType = PenType.values.firstWhere(
            (e) => e.name == penTypeString,
            orElse: () => PenType.fountain,
          );
          pageStrokes.add(DrawingStroke(
            id: row['id'] as int?,
            pageId: row['page_id'] as int?,
            points: points,
            color: Color(row['color'] as int),
            strokeWidth: row['stroke_width'] as double,
            penType: penType,
          ));
        }
      }

      // 3. Calculate bounding box for coordinates scaling
      double minX = double.infinity;
      double maxX = double.negativeInfinity;
      double minY = double.infinity;
      double maxY = double.negativeInfinity;

      for (var stroke in pageStrokes) {
        for (var pt in stroke.points) {
          if (pt.point.dx < minX) minX = pt.point.dx;
          if (pt.point.dx > maxX) maxX = pt.point.dx;
          if (pt.point.dy < minY) minY = pt.point.dy;
          if (pt.point.dy > maxY) maxY = pt.point.dy;
        }
      }

      final hasDrawing = minX != double.infinity;

      // 4. Add Page to PDF
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.CustomPaint(
                size: const PdfPoint(595.27, 841.89), // Standard A4 points
                painter: (PdfGraphics canvas, PdfPoint size) {
                  // --- Step A: Draw Background Template ---
                  if (page.backgroundType == 'ruled') {
                    canvas.setStrokeColor(PdfColor.fromInt(0xFFBBDEFB)); // Light Blue
                    canvas.setLineWidth(0.8);
                    const double lineSpacing = 28.0;
                    for (double y = lineSpacing; y < size.y; y += lineSpacing) {
                      // Invert Y coordinate for PDF coordinate space (draw horizontal lines bottom-to-top)
                      canvas.moveTo(0, y);
                      canvas.lineTo(size.x, y);
                      canvas.strokePath();
                    }
                    // Red margin vertical line
                    canvas.setStrokeColor(PdfColor.fromInt(0xFFFFCDD2)); // Light Red
                    canvas.setLineWidth(1.2);
                    canvas.moveTo(70, 0);
                    canvas.lineTo(70, size.y);
                    canvas.strokePath();
                  } else if (page.backgroundType == 'grid') {
                    canvas.setStrokeColor(PdfColor.fromInt(0xFFECEFF1)); // Light Gray
                    canvas.setLineWidth(0.6);
                    const double gridSize = 24.0;
                    for (double y = gridSize; y < size.y; y += gridSize) {
                      canvas.moveTo(0, y);
                      canvas.lineTo(size.x, y);
                      canvas.strokePath();
                    }
                    for (double x = gridSize; x < size.x; x += gridSize) {
                      canvas.moveTo(x, 0);
                      canvas.lineTo(x, size.y);
                      canvas.strokePath();
                    }
                  } else if (page.backgroundType == 'dotted') {
                    canvas.setFillColor(PdfColor.fromInt(0xFFCFD8DC)); // Dotted gray
                    const double dotSpacing = 24.0;
                    for (double y = dotSpacing; y < size.y; y += dotSpacing) {
                      for (double x = dotSpacing; x < size.x; x += dotSpacing) {
                        canvas.drawEllipse(x, y, 1.0, 1.0);
                        canvas.fillPath();
                      }
                    }
                  }

                  // --- Step B: Render Vector Ink Path Strokes ---
                  if (!hasDrawing) return;

                  final printableW = size.x - 40; // Leave 20pt margin left/right
                  final printableH = size.y - 40; // Leave 20pt margin top/bottom

                  final bWidth = maxX - minX;
                  final bHeight = maxY - minY;

                  final scaleX = bWidth > 0 ? printableW / bWidth : 1.0;
                  final scaleY = bHeight > 0 ? printableH / bHeight : 1.0;
                  
                  // Limit max scale to 1.0 to avoid inflating small notes too much
                  final scale = math.min(math.min(scaleX, scaleY), 1.0);

                  final drawW = bWidth * scale;
                  final drawH = bHeight * scale;

                  // Shift offsets to center drawing inside the PDF page
                  final shiftX = (size.x - drawW) / 2 - minX * scale;
                  final shiftY = (size.y - drawH) / 2 - minY * scale;

                  // Transform coordinates (and invert Y for PDF bottom-left origin)
                  double pdfX(double fx) => fx * scale + shiftX;
                  double pdfY(double fy) => size.y - (fy * scale + shiftY);

                  for (var stroke in pageStrokes) {
                    if (stroke.points.isEmpty) continue;

                    final color = stroke.color;
                    
                    if (stroke.penType == PenType.highlighter) {
                      // Highlighter translucency (mix opacity with color hex)
                      final hexColor = (color.toARGB32() & 0x00FFFFFF) | 0x55000000;
                      canvas.setStrokeColor(PdfColor.fromInt(hexColor));
                      canvas.setLineCap(PdfLineCap.square);
                      canvas.setLineWidth(stroke.strokeWidth * 3.0 * scale);
                    } else {
                      canvas.setStrokeColor(PdfColor.fromInt(color.toARGB32()));
                      canvas.setLineCap(PdfLineCap.round);
                      canvas.setLineWidth(stroke.strokeWidth * scale);
                    }

                    final first = stroke.points.first.point;
                    canvas.moveTo(pdfX(first.dx), pdfY(first.dy));

                    for (int i = 1; i < stroke.points.length; i++) {
                      final pt = stroke.points[i].point;
                      canvas.lineTo(pdfX(pt.dx), pdfY(pt.dy));
                    }
                    canvas.strokePath();
                  }
                },
              ),
            );
          },
        ),
      );
    }

    // 5. Compile and share PDF file
    final outputDir = await getTemporaryDirectory();
    final sanitizedTitle = notebook.name.replaceAll(RegExp(r'[^\w\s\-]'), '').trim();
    final filePath = "${outputDir.path}/$sanitizedTitle.pdf";
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    // 6. Launch iOS Sharesheet share action
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: "Exported '${notebook.name}' from Lipinotes",
    );
  }
}
