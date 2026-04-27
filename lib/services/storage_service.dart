import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

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
  String get readerStatsFile => '$statsPath/stats.json';
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

  String getBookDir(String title) {
    final sanitized = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$libraryPath/$sanitized';
  }

  String getBookEntryFile(String title) {
    final dir = getBookDir(title);
    return '$dir/metadata.json';
  }

  String getBookFilePath(String title, String originalPath) {
    final ext = originalPath.split('.').last;
    final dir = getBookDir(title);
    final sanitized = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$dir/$sanitized.$ext';
  }

  String getProjectDir(String projectName) {
    final sanitized = projectName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$projectsPath/$sanitized';
  }
}
