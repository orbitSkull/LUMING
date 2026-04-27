import 'dart:convert';
import 'dart:io';
import 'storage_service.dart';

class WriterStats {
  int totalWords = 0;
  int sessionWords = 0;
  int dailyGoal = 500;
  int currentStreak = 0;
  int longestStreak = 0;
  DateTime? lastWritingDate;
  DateTime? sessionStartTime;
  int sessionStartWords = 0;

  WriterStats();

  double get velocity => sessionWords > 0 && sessionDuration > 0 
      ? sessionWords / (sessionDuration / 60) 
      : 0;

  int get sessionDuration => sessionStartTime != null 
      ? DateTime.now().difference(sessionStartTime!).inMinutes 
      : 0;

  bool get goalReachedToday => sessionWords >= dailyGoal;

  Map<String, dynamic> toJson() => {
    'totalWords': totalWords,
    'dailyGoal': dailyGoal,
    'currentStreak': currentStreak,
    'longestStreak': longestStreak,
    'lastWritingDate': lastWritingDate?.toIso8601String(),
  };

  factory WriterStats.fromJson(Map<String, dynamic> json) {
    final stats = WriterStats()
      ..totalWords = json['totalWords'] ?? 0
      ..dailyGoal = json['dailyGoal'] ?? 500
      ..currentStreak = json['currentStreak'] ?? 0
      ..longestStreak = json['longestStreak'] ?? 0
      ..lastWritingDate = json['lastWritingDate'] != null 
          ? DateTime.parse(json['lastWritingDate']) 
          : null;
    return stats;
  }
}

class DailyStats {
  final int wordCount;
  final DateTime date;

  DailyStats({required this.wordCount, required this.date});

  Map<String, dynamic> toJson() => {
    'wordCount': wordCount,
    'date': date.toIso8601String(),
  };

  factory DailyStats.fromJson(Map<String, dynamic> json) => DailyStats(
    wordCount: json['wordCount'] ?? 0,
    date: DateTime.parse(json['date']),
  );
}

class WriterService {
  static final WriterService _instance = WriterService._internal();
  factory WriterService() => _instance;
  WriterService._internal();

  final StorageService _storageService = StorageService();
  final WriterStats _stats = WriterStats();
  WriterStats get stats => _stats;

  Future<void> loadStats() async {
    // Writer stats are now per-project and calculated on the fly in the UI.
    // Daily word count streaks might still use global tracking if desired,
    // but the request asks for writer stats inside the Project folder.
  }

  Future<void> _saveStats() async {
    // No longer saving to global stats.json
  }

  Future<void> _updateDailyStats(int wordsAdded) async {
    try {
      await _storageService.ensureDirectories();
      final now = DateTime.now();
      final file = File(_storageService.getDailyStatsFile(now));
      
      int currentDailyWords = 0;
      if (await file.exists()) {
        final data = await file.readAsString();
        final json = jsonDecode(data);
        currentDailyWords = json['wordCount'] ?? 0;
      }
      
      final dailyStats = DailyStats(
        wordCount: currentDailyWords + wordsAdded,
        date: now,
      );
      
      await file.writeAsString(jsonEncode(dailyStats.toJson()));
    } catch (e) {
      // ignore: avoid_print
      print('Error updating daily stats: $e');
    }
  }

  void checkStreak() {
    if (_stats.lastWritingDate != null) {
      final now = DateTime.now();
      final lastDate = DateTime(_stats.lastWritingDate!.year, _stats.lastWritingDate!.month, _stats.lastWritingDate!.day);
      final today = DateTime(now.year, now.month, now.day);
      final difference = today.difference(lastDate).inDays;
      
      if (difference > 1) {
        _stats.currentStreak = 0;
      }
    }
  }

  void startSession() {
    _stats.sessionStartTime = DateTime.now();
    _stats.sessionStartWords = _stats.totalWords;
  }

  void updateWordCount(int totalProjectWords) {
    final wordsInSession = totalProjectWords - _stats.sessionStartWords;
    _stats.sessionWords = wordsInSession > 0 ? wordsInSession : 0;
    _stats.totalWords = totalProjectWords;
  }

  Future<void> endSession() async {
    if (_stats.sessionWords > 0) {
      final now = DateTime.now();
      await _updateDailyStats(_stats.sessionWords);

      if (_stats.lastWritingDate != null) {
        final lastDate = DateTime(_stats.lastWritingDate!.year, _stats.lastWritingDate!.month, _stats.lastWritingDate!.day);
        final today = DateTime(now.year, now.month, now.day);
        final difference = today.difference(lastDate).inDays;

        if (difference == 1) {
          _stats.currentStreak++;
        } else if (difference > 1) {
          _stats.currentStreak = 1;
        } else if (difference == 0) {
          // Already wrote today, streak stays the same
        }
      } else {
        _stats.currentStreak = 1;
      }
      
      if (_stats.currentStreak > _stats.longestStreak) {
        _stats.longestStreak = _stats.currentStreak;
      }
      
      _stats.lastWritingDate = now;
      await _saveStats();
    }
    
    _stats.sessionStartTime = null;
    _stats.sessionWords = 0;
    _stats.sessionStartWords = _stats.totalWords;
  }

  Future<void> setDailyGoal(int goal) async {
    _stats.dailyGoal = goal;
    await _saveStats();
  }
}