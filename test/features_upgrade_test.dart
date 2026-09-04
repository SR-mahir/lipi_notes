import 'package:flutter_test/flutter_test.dart';
import 'package:lipi_notes/src/models/workspace_models.dart';
import 'package:lipi_notes/src/models/text_box_model.dart';
import 'package:lipi_notes/src/models/stroke_model.dart';
import 'package:lipi_notes/src/models/db_helper.dart';
import 'package:lipi_notes/src/controllers/canvas_controller.dart';
import 'package:lipi_notes/src/controllers/workspace_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Feature 11: Hierarchical Subfolders Model & Navigation', () {
    test('Folder serialization preserves parentId for nesting', () {
      final rootFolder = Folder(id: 1, name: "College", colorValue: 0xFF4CAF50);
      expect(rootFolder.parentId, isNull);

      final subFolder = Folder(id: 2, name: "Physics", colorValue: 0xFF2196F3, parentId: 1);
      final map = subFolder.toMap();
      expect(map['parent_id'], 1);

      final parsed = Folder.fromMap(map);
      expect(parsed.id, 2);
      expect(parsed.name, "Physics");
      expect(parsed.parentId, 1);
    });

    test('WorkspaceController breadcrumbs management', () {
      final controller = WorkspaceController();
      expect(controller.breadcrumbs, isEmpty);

      final f1 = Folder(id: 10, name: "Semester 1", colorValue: 0xFF4CAF50);
      final f2 = Folder(id: 11, name: "CSE470", colorValue: 0xFF2196F3, parentId: 10);

      controller.navigateToFolder(f1);
      expect(controller.activeFolder?.id, 10);
      expect(controller.breadcrumbs.length, 1);

      controller.navigateToFolder(f2);
      expect(controller.activeFolder?.id, 11);
      expect(controller.breadcrumbs.length, 2);

      // Navigate back up
      controller.navigateUp();
      expect(controller.activeFolder?.id, 10);
      expect(controller.breadcrumbs.length, 1);

      controller.navigateUp();
      expect(controller.activeFolder, isNull);
      expect(controller.breadcrumbs, isEmpty);
    });
  });

  group('Feature 14: Typography Layer Font Family & Color Support', () {
    test('TextBoxModel supports and serializes fontFamily and custom color', () {
      final box = TextBoxModel(
        pageId: 1,
        text: "Important Lecture Notes",
        x: 100,
        y: 200,
        fontSize: 24,
        fontFamily: 'serif',
        colorValue: 0xFFB91C1C, // Red
      );

      final map = box.toMap();
      expect(map['font_family'], 'serif');
      expect(map['color'], 0xFFB91C1C);

      final restored = TextBoxModel.fromMap(map);
      expect(restored.fontFamily, 'serif');
      expect(restored.colorValue, 0xFFB91C1C);
      expect(restored.fontSize, 24);
    });
  });

  group('Feature 7: Lasso Selection Handles', () {
    test('LassoHandle enum contains scaling and rotation handle definitions', () {
      expect(LassoHandle.values, contains(LassoHandle.topLeft));
      expect(LassoHandle.values, contains(LassoHandle.topRight));
      expect(LassoHandle.values, contains(LassoHandle.bottomLeft));
      expect(LassoHandle.values, contains(LassoHandle.bottomRight));
      expect(LassoHandle.values, contains(LassoHandle.rotate));
      expect(LassoHandle.values, contains(LassoHandle.move));
    });
  });

  group('Feature 2: Stylus Pressure Persistence', () {
    test('Serializes and deserializes stroke points with pressure data', () {
      final points = [
        StrokePoint(point: const Offset(10.5, 20.0), pressure: 0.45, timestamp: DateTime.now()),
        StrokePoint(point: const Offset(15.0, 25.5), pressure: 0.90, timestamp: DateTime.now()),
        StrokePoint(point: const Offset(20.0, 30.0), pressure: 1.35, timestamp: DateTime.now()),
      ];

      final serialized = CanvasController.serializePointsStatic(points);
      expect(serialized, '10.5,20.0,0.45 15.0,25.5,0.90 20.0,30.0,1.35');

      final deserialized = CanvasController.deserializePointsStatic(serialized);
      expect(deserialized.length, 3);
      expect(deserialized[0].point, const Offset(10.5, 20.0));
      expect(deserialized[0].pressure, closeTo(0.45, 0.01));
      expect(deserialized[1].point, const Offset(15.0, 25.5));
      expect(deserialized[1].pressure, closeTo(0.90, 0.01));
      expect(deserialized[2].point, const Offset(20.0, 30.0));
      expect(deserialized[2].pressure, closeTo(1.35, 0.01));
    });

    test('Backward compatibility with legacy 2-token coordinates format', () {
      const legacyData = '10.0,20.0 30.0,40.0';
      final deserialized = CanvasController.deserializePointsStatic(legacyData);
      expect(deserialized.length, 2);
      expect(deserialized[0].point, const Offset(10.0, 20.0));
      expect(deserialized[0].pressure, 1.0);
      expect(deserialized[1].point, const Offset(30.0, 40.0));
      expect(deserialized[1].pressure, 1.0);
    });
  });

  group('Feature 16: Notebook Dark Mode Persistence', () {
    test('Notebook model serializes and restores dark_mode state', () {
      final lightNotebook = Notebook(id: 1, name: "Chemistry Notes", isDarkMode: false);
      expect(lightNotebook.toMap()['dark_mode'], 0);

      final darkNotebook = Notebook(id: 2, name: "Physics Notes", isDarkMode: true);
      expect(darkNotebook.toMap()['dark_mode'], 1);

      final restored = Notebook.fromMap({
        'id': 2,
        'name': 'Physics Notes',
        'dark_mode': 1,
      });
      expect(restored.isDarkMode, isTrue);
    });
  });

  group('Database: Foreign Keys & Cascading Deletions', () {
    test('PRAGMA foreign_keys is enabled on database connection', () async {
      final db = await DBHelper.database;
      final result = await db.rawQuery('PRAGMA foreign_keys');
      expect(result.first.values.first, 1);
    });

    test('Deleting folder sets notebooks folder_id to NULL and cascades subfolders', () async {
      // 1. Create parent folder, subfolder, and notebook inside parent folder
      final parentFolderId = await DBHelper.insertFolder("Parent Folder", 0xFF2196F3);
      final subFolderId = await DBHelper.insertFolder("Child Folder", 0xFF4CAF50, parentId: parentFolderId);
      final notebookId = await DBHelper.insertNotebook("Inside Notebook", parentFolderId);

      // Verify initial setup
      var allNb = await DBHelper.getAllNotebooks();
      var nb = allNb.firstWhere((n) => n['id'] == notebookId);
      expect(nb['folder_id'], parentFolderId);

      var subFolders = await DBHelper.getFolders(parentId: parentFolderId);
      expect(subFolders.any((f) => f['id'] == subFolderId), isTrue);

      // 2. Delete parent folder
      await DBHelper.deleteFolder(parentFolderId);

      // 3. Verify subfolder was deleted via CASCADE
      final allFolders = await DBHelper.getAllFolders();
      expect(allFolders.any((f) => f['id'] == subFolderId), isFalse);

      // 4. Verify notebook folder_id was set to NULL via ON DELETE SET NULL
      allNb = await DBHelper.getAllNotebooks();
      nb = allNb.firstWhere((n) => n['id'] == notebookId);
      expect(nb['folder_id'], isNull);

      // Clean up notebook
      await DBHelper.deleteNotebook(notebookId);
    });

    test('Deleting notebook cascades deletion to pages, strokes, and text boxes', () async {
      final db = await DBHelper.database;

      // 1. Create notebook, page, stroke, and text box
      final nbId = await DBHelper.insertNotebook("Cascade Test Notebook", null);
      final pageId = await DBHelper.insertPage(nbId, 0, 'blank');

      final strokeId = await DBHelper.insertStroke(
        '10.0,10.0,1.0 20.0,20.0,1.0',
        0xFF000000,
        2.0,
        'fountain',
        pageId,
      );

      final textBox = TextBoxModel(
        pageId: pageId,
        text: 'Test text box overlay',
        x: 100.0,
        y: 150.0,
        width: 200.0,
        height: 50.0,
        fontSize: 16.0,
        colorValue: 0xFF000000,
        fontFamily: 'sans',
      );
      final textBoxId = await DBHelper.insertTextBox(textBox.toMap());

      // Verify they exist
      expect((await DBHelper.getPagesForNotebook(nbId)).length, 1);
      expect((await DBHelper.getSavedStrokesForPage(pageId)).length, 1);
      expect((await DBHelper.getTextBoxesForPage(pageId)).length, 1);

      // 2. Delete notebook
      await DBHelper.deleteNotebook(nbId);

      // 3. Verify pages, strokes, and text boxes were all deleted via CASCADE
      final pagesAfter = await DBHelper.getPagesForNotebook(nbId);
      expect(pagesAfter, isEmpty);

      final strokesAfter = await db.query('strokes', where: 'id = ?', whereArgs: [strokeId]);
      expect(strokesAfter, isEmpty);

      final textBoxesAfter = await db.query('text_boxes', where: 'id = ?', whereArgs: [textBoxId]);
      expect(textBoxesAfter, isEmpty);
    });
  });

  group('CanvasController: flushUnsavedStrokes', () {
    test('flushUnsavedStrokes executes cleanly on empty or populated queue', () async {
      final nbId = await DBHelper.insertNotebook("Flush Test Notebook", null);
      final testNotebook = Notebook(id: nbId, name: "Flush Test Notebook");
      final controller = CanvasController(notebook: testNotebook);

      // Calling flush on fresh controller shouldn't throw
      await expectLater(controller.flushUnsavedStrokes(), completes);
      controller.dispose();
      await DBHelper.deleteNotebook(nbId);
    });
  });
}
