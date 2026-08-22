import 'package:flutter/material.dart';
import 'src/views/home_explorer_view.dart';

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
      home: const HomeExplorerView(),
    );
  }
}