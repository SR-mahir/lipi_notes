import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import '../models/stroke_model.dart';
import '../models/workspace_models.dart';
import '../models/text_box_model.dart';
import '../models/db_helper.dart';

class PDFExportController {
  static List<StrokePoint> _deserializePoints(String dataString) {
    if (dataString.isEmpty) return [];
    return dataString.split(' ').map((pair) {
      final coordinates = pair.split(',');
      final dx = double.tryParse(coordinates[0]) ?? 0.0;
      final dy = double.tryParse(coordinates[1]) ?? 0.0;
      final pressure = coordinates.length > 2 
          ? (double.tryParse(coordinates[2]) ?? 1.0) 
          : 1.0;
      return StrokePoint(
        point: Offset(dx, dy),
        pressure: pressure,
        timestamp: DateTime.now(),
      );
    }).toList();
  }

  static pw.Font _fontForFamily(String family) {
    switch (family) {
      case 'serif':
        return pw.Font.times();
      case 'mono':
        return pw.Font.courier();
      case 'script':
        return pw.Font.timesItalic();
      case 'sans':
      default:
        return pw.Font.helvetica();
    }
  }

  static Future<void> exportNotebook(Notebook notebook, {Rect? sharePositionOrigin}) async {
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

      // 2.5 Fetch text boxes for each page
      final textBoxesData = await DBHelper.getTextBoxesForPage(page.id!);
      final List<TextBoxModel> pageTextBoxes = textBoxesData
          .map((m) => TextBoxModel.fromMap(m))
          .toList();

      // 2.6 Fetch PDF page background if available
      Uint8List? bgImageBytes;
      if (page.pdfPath != null && page.pdfPageIndex != null) {
        try {
          final doc = await pdfx.PdfDocument.openFile(page.pdfPath!);
          final pdfPage = await doc.getPage(page.pdfPageIndex!);
          final pageImage = await pdfPage.render(
            width: pdfPage.width * 2.0,
            height: pdfPage.height * 2.0,
            format: pdfx.PdfPageImageFormat.png,
          );
          bgImageBytes = pageImage?.bytes;
          await pdfPage.close();
          await doc.close();
        } catch (e) {
          debugPrint("Failed to render background PDF page for export: $e");
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

      for (var tb in pageTextBoxes) {
        if (tb.x < minX) minX = tb.x;
        if (tb.x + 100 > maxX) maxX = tb.x + 100;
        if (tb.y < minY) minY = tb.y;
        if (tb.y + 40 > maxY) maxY = tb.y + 40;
      }

      final hasContent = minX != double.infinity;
      const pageSize = PdfPoint(595.27, 841.89); // Standard A4 points
      const printableW = 595.27 - 40; // Leave 20pt margin left/right
      const printableH = 841.89 - 40; // Leave 20pt margin top/bottom

      final double scale;
      final double shiftX;
      final double shiftY;

      if (hasContent) {
        final bWidth = maxX - minX;
        final bHeight = maxY - minY;
        final scaleX = bWidth > 0 ? printableW / bWidth : 1.0;
        final scaleY = bHeight > 0 ? printableH / bHeight : 1.0;
        scale = math.min(math.min(scaleX, scaleY), 1.0);
        final drawW = bWidth * scale;
        final drawH = bHeight * scale;
        shiftX = (pageSize.x - drawW) / 2 - minX * scale;
        shiftY = (pageSize.y - drawH) / 2 - minY * scale;
      } else {
        scale = 1.0;
        shiftX = 20.0;
        shiftY = 20.0;
      }

      double pdfX(double fx) => fx * scale + shiftX;
      double pdfY(double fy) => pageSize.y - (fy * scale + shiftY);

      // 4. Add Page to PDF
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Stack(
                children: [
                  // Step A: Background PDF page if imported
                  if (bgImageBytes != null)
                    pw.Positioned.fill(
                      child: pw.Image(
                        pw.MemoryImage(bgImageBytes),
                        fit: pw.BoxFit.contain,
                      ),
                    ),

                  // Step B: Canvas painter for paper grid templates & vector ink paths
                  pw.CustomPaint(
                    size: pageSize,
                    painter: (PdfGraphics canvas, PdfPoint size) {
                      // Draw Background Template only if no imported PDF
                      if (bgImageBytes == null) {
                        if (page.backgroundType == 'ruled') {
                          canvas.setStrokeColor(PdfColor.fromInt(0xFFBBDEFB));
                          canvas.setLineWidth(0.8);
                          const double lineSpacing = 28.0;
                          for (double y = lineSpacing; y < size.y; y += lineSpacing) {
                            canvas.moveTo(0, y);
                            canvas.lineTo(size.x, y);
                            canvas.strokePath();
                          }
                          canvas.setStrokeColor(PdfColor.fromInt(0xFFFFCDD2));
                          canvas.setLineWidth(1.2);
                          canvas.moveTo(70, 0);
                          canvas.lineTo(70, size.y);
                          canvas.strokePath();
                        } else if (page.backgroundType == 'grid') {
                          canvas.setStrokeColor(PdfColor.fromInt(0xFFECEFF1));
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
                          canvas.setFillColor(PdfColor.fromInt(0xFFCFD8DC));
                          const double dotSpacing = 24.0;
                          for (double y = dotSpacing; y < size.y; y += dotSpacing) {
                            for (double x = dotSpacing; x < size.x; x += dotSpacing) {
                              canvas.drawEllipse(x, y, 1.0, 1.0);
                              canvas.fillPath();
                            }
                          }
                        }
                      }

                      // Render Vector Ink Path Strokes
                      if (!hasContent) return;

                      for (var stroke in pageStrokes) {
                        if (stroke.points.isEmpty) continue;

                        final color = stroke.color;
                        
                        if (stroke.penType == PenType.highlighter) {
                          Color hlColor = stroke.color;
                          if (hlColor == Colors.black || hlColor == const Color(0xFF000000)) {
                            hlColor = const Color(0xFFFFD54F);
                          }
                          final hexColor = (hlColor.toARGB32() & 0x00FFFFFF) | 0x66000000;
                          canvas.setStrokeColor(PdfColor.fromInt(hexColor));
                          canvas.setLineCap(PdfLineCap.round);
                          canvas.setLineJoin(PdfLineJoin.round);
                          canvas.setLineWidth(stroke.strokeWidth * 3.5 * scale);
                        } else {
                          canvas.setStrokeColor(PdfColor.fromInt(color.toARGB32()));
                          canvas.setLineCap(PdfLineCap.round);
                          canvas.setLineWidth(stroke.strokeWidth * scale);
                        }

                        if (stroke.penType == PenType.fountain || stroke.penType == PenType.brush) {
                          for (int i = 1; i < stroke.points.length; i++) {
                            final p0 = stroke.points[i - 1];
                            final p1 = stroke.points[i];
                            final dynamicWidth = stroke.strokeWidth * p1.pressure.clamp(0.2, 2.0) * scale;
                            canvas.setLineWidth(dynamicWidth);
                            canvas.moveTo(pdfX(p0.point.dx), pdfY(p0.point.dy));
                            canvas.lineTo(pdfX(p1.point.dx), pdfY(p1.point.dy));
                            canvas.strokePath();
                          }
                        } else {
                          final first = stroke.points.first.point;
                          canvas.moveTo(pdfX(first.dx), pdfY(first.dy));

                          for (int i = 1; i < stroke.points.length; i++) {
                            final pt = stroke.points[i].point;
                            canvas.lineTo(pdfX(pt.dx), pdfY(pt.dy));
                          }
                          canvas.strokePath();
                        }
                      }
                    },
                  ),

                  // Step C: Render Typed Text Box Overlays
                  for (var tb in pageTextBoxes)
                    pw.Positioned(
                      left: pdfX(tb.x),
                      top: tb.y * scale + shiftY,
                      child: pw.Text(
                        tb.text,
                        style: pw.TextStyle(
                          font: _fontForFamily(tb.fontFamily),
                          fontSize: tb.fontSize * scale,
                          color: PdfColor.fromInt(tb.colorValue),
                        ),
                      ),
                    ),
                ],
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
    // On iPad, sharePositionOrigin is required by iOS to anchor the popover.
    final origin = sharePositionOrigin ?? const Rect.fromLTWH(0, 0, 100, 100);
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: "Exported '${notebook.name}' from Lipinotes",
      sharePositionOrigin: origin,
    );
  }
}
