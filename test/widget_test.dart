import 'package:flutter_test/flutter_test.dart';
import 'package:lipi_notes/main.dart';
import 'package:lipi_notes/src/views/home_explorer_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Initialize FFI for local SQLite testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('Lipinotes app renders home explorer correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LipinotesApp());

    // Verify that our HomeExplorerView component is present on the screen.
    expect(find.byType(HomeExplorerView), findsOneWidget);
  });
}