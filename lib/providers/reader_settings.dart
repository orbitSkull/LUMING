import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/storage_service.dart';

class ReaderSettings extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  double _fontSize = 16.0;
  double _lineHeight = 1.6;
  String _fontFamily = 'Serif';
  bool _darkMode = false;
  bool? _showWordCount;
  bool? _focusMode;
  bool? _typewriterScrolling;
  bool _libraryGridView = false;
  List<String> _globalCustomLabels = [];
  List<BookmarkType> _globalBookmarks = [];

  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  String get fontFamily => _fontFamily;
  bool get darkMode => _darkMode;
  bool get showWordCount => _showWordCount ?? true;
  bool get focusMode => _focusMode ?? false;
  bool get typewriterScrolling => _typewriterScrolling ?? false;
  bool get libraryGridView => _libraryGridView;
  List<String> get globalCustomLabels => _globalCustomLabels;
  List<BookmarkType> get globalBookmarks => _globalBookmarks;

  ReaderSettings() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Load from external storage first
    try {
      final file = File(_storageService.settingsFile);
      if (await file.exists()) {
        final data = await file.readAsString();
        final json = jsonDecode(data);
        _fontSize = json['fontSize']?.toDouble() ?? 16.0;
        _lineHeight = json['lineHeight']?.toDouble() ?? 1.6;
        _fontFamily = json['fontFamily'] ?? 'Serif';
        _darkMode = json['darkMode'] ?? false;
        _showWordCount = json['showWordCount'];
        _focusMode = json['focusMode'];
        _typewriterScrolling = json['typewriterScrolling'];
        _libraryGridView = json['libraryGridView'] ?? false;
        _globalCustomLabels = List<String>.from(json['globalCustomLabels'] ?? []);
        _globalBookmarks = (json['globalBookmarks'] as List?)
                ?.map((b) => BookmarkType.values.firstWhere((e) => e.name == b))
                .toList() ??
            [];
        notifyListeners();
        return;
      }
    } catch (e) {
      print('Error loading settings from external storage: $e');
    }

    // Fallback to SharedPreferences if external not available or first run
    final prefs = await SharedPreferences.getInstance();
    _fontSize = prefs.getDouble('defaultFontSize') ?? 16.0;
    _lineHeight = prefs.getDouble('defaultLineHeight') ?? 1.6;
    _fontFamily = prefs.getString('defaultFontFamily') ?? 'Serif';
    _darkMode = prefs.getBool('darkMode') ?? false;
    _showWordCount = prefs.getBool('writer_showWordCount');
    _focusMode = prefs.getBool('writer_focusMode');
    _typewriterScrolling = prefs.getBool('writer_typewriterScrolling');
    _libraryGridView = prefs.getBool('libraryGridView') ?? false;
    _globalCustomLabels = prefs.getStringList('globalCustomLabels') ?? [];
    _globalBookmarks = (prefs.getStringList('globalBookmarks') ?? [])
        .map((name) {
          try {
            return BookmarkType.values.firstWhere((b) => b.name == name);
          } catch (_) {
            return null;
          }
        })
        .whereType<BookmarkType>()
        .toList();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    try {
      await _storageService.ensureDirectories();
      final file = File(_storageService.settingsFile);
      final data = {
        'fontSize': _fontSize,
        'lineHeight': _lineHeight,
        'fontFamily': _fontFamily,
        'darkMode': _darkMode,
        'showWordCount': _showWordCount,
        'focusMode': _focusMode,
        'typewriterScrolling': _typewriterScrolling,
        'libraryGridView': _libraryGridView,
        'globalCustomLabels': _globalCustomLabels,
        'globalBookmarks': _globalBookmarks.map((b) => b.name).toList(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      print('Error saving settings to external storage: $e');
    }

    // Also save to SharedPreferences for backup/compatibility
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('defaultFontSize', _fontSize);
    await prefs.setDouble('defaultLineHeight', _lineHeight);
    await prefs.setString('defaultFontFamily', _fontFamily);
    await prefs.setBool('darkMode', _darkMode);
    if (_showWordCount != null) await prefs.setBool('writer_showWordCount', _showWordCount!);
    if (_focusMode != null) await prefs.setBool('writer_focusMode', _focusMode!);
    if (_typewriterScrolling != null) await prefs.setBool('writer_typewriterScrolling', _typewriterScrolling!);
    await prefs.setBool('libraryGridView', _libraryGridView);
    await prefs.setStringList('globalCustomLabels', _globalCustomLabels);
    await prefs.setStringList('globalBookmarks', _globalBookmarks.map((b) => b.name).toList());
  }

  Future<void> setLibraryGridView(bool value) async {
    _libraryGridView = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setGlobalCustomLabels(List<String> labels) async {
    _globalCustomLabels = labels;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> addGlobalCustomLabel(String label) async {
    if (!_globalCustomLabels.contains(label)) {
      _globalCustomLabels.add(label);
      await _saveSettings();
      notifyListeners();
    }
  }

  Future<void> setGlobalBookmarks(List<BookmarkType> bookmarks) async {
    _globalBookmarks = bookmarks;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size.clamp(12.0, 32.0);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setLineHeight(double height) async {
    _lineHeight = height.clamp(1.2, 2.0);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setFontFamily(String family) async {
    _fontFamily = family;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    await setDarkMode(!_darkMode);
  }

  void increaseFontSize() {
    if (_fontSize < 32.0) {
      setFontSize(_fontSize + 2.0);
    }
  }

  void decreaseFontSize() {
    if (_fontSize > 12.0) {
      setFontSize(_fontSize - 2.0);
    }
  }

  Future<void> setShowWordCount(bool value) async {
    _showWordCount = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setFocusMode(bool value) async {
    _focusMode = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setTypewriterScrolling(bool value) async {
    _typewriterScrolling = value;
    await _saveSettings();
    notifyListeners();
  }
}