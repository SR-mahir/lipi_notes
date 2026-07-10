import 'package:flutter/material.dart';
import 'src/views/drawing_canvas_view.dart';

void main() {
  runApp(const LipinotesApp());
}

class LipinotesApp extends StatelessWidget {
  const LipinotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lipinotes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      home: const Scaffold(
        backgroundColor: Color(0xFFF6F6F6),
        body: SafeArea(
          child: DrawingCanvasView(),
        ),
      ),
    );
  }
}