import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String _lumingDir = '/storage/emulated/0/LUMING';
  
  String get rootPath => _lumingDir;
  String get libraryPath => '$rootPath/Library';
  String get projectsPath => '$rootPath/Projects';
  String get statsPath => '$rootPath/Stats';
  String get ideaboxPath => '$rootPath/Ideabox';
  
  String get settingsFile => '$rootPath/settings.json';
  String get continueFile => '$rootPath/continue.json';
  String get ideaboxFile => '$ideaboxPath/ideabox.json';
  String get overallStatsFile => '$statsPath/stats.json';
  String get publishedFile => '$rootPath/published.json';

  Future<bool> hasPermission() async {
    return await Permission.manageExternalStorage.status.isGranted;
  }

  Future<bool> requestPermission() async {
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      await ensureDirectories();
      return true;
    }
    return false;
  }

  Future<void> ensureDirectories() async {
    final dirs = [
      rootPath,
      libraryPath,
      projectsPath,
      statsPath,
      ideaboxPath,
    ];
    for (final path in dirs) {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    }
  }

  String getDailyStatsFile(DateTime date) {
    final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    return '$statsPath/$dateStr.json';
  }

  String getBookEntryFile(String title) {
    // Sanitize title for filename
    final sanitized = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$libraryPath/$sanitized.json';
  }

  String getProjectDir(String projectName) {
    final sanitized = projectName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$projectsPath/$sanitized';
  }
}
