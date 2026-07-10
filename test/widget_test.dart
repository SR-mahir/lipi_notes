import 'package:flutter_test/flutter_test.dart';
import 'package:lipi_notes/main.dart';
import 'package:lipi_notes/src/views/drawing_canvas_view.dart';

void main() {
  testWidgets('Lipinotes app renders canvas view correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LipinotesApp());

    // Verify that our DrawingCanvasView component is present on the screen.
    expect(find.byType(DrawingCanvasView), findsOneWidget);
  });
}