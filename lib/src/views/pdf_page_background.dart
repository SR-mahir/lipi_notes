import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class PdfPageBackground extends StatefulWidget {
  final String pdfPath;
  final int pageNumber;

  const PdfPageBackground({
    super.key,
    required this.pdfPath,
    required this.pageNumber,
  });

  @override
  State<PdfPageBackground> createState() => _PdfPageBackgroundState();
}

class _PdfPageBackgroundState extends State<PdfPageBackground> {
  static final Map<String, PdfDocument> _documentCache = {};
  Uint8List? _imageBytes;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void didUpdateWidget(PdfPageBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfPath != widget.pdfPath || oldWidget.pageNumber != widget.pageNumber) {
      setState(() {
        _imageBytes = null;
        _hasError = false;
      });
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    try {
      PdfDocument? doc = _documentCache[widget.pdfPath];
      if (doc == null) {
        doc = await PdfDocument.openFile(widget.pdfPath);
        _documentCache[widget.pdfPath] = doc;
      }

      final page = await doc.getPage(widget.pageNumber);
      
      // Render page. We scale it up by 2.0x for high-fidelity zoom clarity!
      final pageImage = await page.render(
        width: page.width * 2.0,
        height: page.height * 2.0,
        format: PdfPageImageFormat.png,
      );

      if (mounted) {
        setState(() {
          _imageBytes = pageImage?.bytes;
        });
      }
    } catch (e) {
      debugPrint("Failed to load PDF page background: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              SizedBox(height: 8),
              Text(
                "Could not render PDF slide backdrop",
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    if (_imageBytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.green),
      );
    }

    return Image.memory(
      _imageBytes!,
      fit: BoxFit.contain,
    );
  }
}
