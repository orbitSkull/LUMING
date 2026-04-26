import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

class WriterService {
  static final WriterService _instance = WriterService._internal();
  factory WriterService() => _instance;
  WriterService._internal();

  WriterStats _stats = WriterStats();
  WriterStats get stats => _stats;

  Future<void> loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('writerStats');
    if (data != null) {
      _stats = WriterStats.fromJson(jsonDecode(data));
      _checkStreak();
    }
  }

  Future<void> _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('writerStats', jsonEncode(_stats.toJson()));
  }

  void _checkStreak() {
    if (_stats.lastWritingDate != null) {
      final now = DateTime.now();
      final daysSince = now.difference(_stats.lastWritingDate!).inDays;
      if (daysSince > 1) {
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
      if (_stats.lastWritingDate != null) {
        final daysSince = now.difference(_stats.lastWritingDate!).inDays;
        if (daysSince == 1) {
          _stats.currentStreak++;
        } else if (daysSince > 1) {
          _stats.currentStreak = 1;
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