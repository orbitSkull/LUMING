import 'bookmark_type.dart';
import 'dart:io';

class BookEntry {
  final String filePath;
  final String title;
  final String? coverPath;
  final List<BookmarkType> bookmarks;
  final DateTime addedAt;
  final DateTime updatedAt;
  final int lastChapter;
  final int totalChapters;
  final List<String> customLabels;
  final bool lastWasTts;
  final int ttsLastChunk;
  final int ttsTotalChunks;

  BookEntry({
    required this.filePath,
    required this.title,
    this.coverPath,
    required this.bookmarks,
    required this.addedAt,
    DateTime? updatedAt,
    this.lastChapter = 0,
    this.totalChapters = 1,
    this.customLabels = const [],
    this.lastWasTts = false,
    this.ttsLastChunk = 0,
    this.ttsTotalChunks = 0,
  }) : updatedAt = updatedAt ?? addedAt;

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'title': title,
        'coverPath': coverPath,
        'bookmarks': bookmarks.map((b) => b.name).toList(),
        'addedAt': addedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastChapter': lastChapter,
        'totalChapters': totalChapters,
        'customLabels': customLabels,
        'lastWasTts': lastWasTts,
        'ttsLastChunk': ttsLastChunk,
        'ttsTotalChunks': ttsTotalChunks,
      };

  factory BookEntry.fromJson(Map<String, dynamic> json) => BookEntry(
        filePath: json['filePath'],
        title: json['title'],
        coverPath: json['coverPath'],
        bookmarks: (json['bookmarks'] as List)
            .map((b) => BookmarkType.values.firstWhere((e) => e.name == b))
            .toList(),
        addedAt: DateTime.parse(json['addedAt']),
        updatedAt: json['updatedAt'] != null 
            ? DateTime.parse(json['updatedAt']) 
            : DateTime.parse(json['addedAt']),
        lastChapter: json['lastChapter'] ?? 0,
        totalChapters: json['totalChapters'] ?? 1,
        customLabels: (json['customLabels'] as List?)?.cast<String>() ?? [],
        lastWasTts: json['lastWasTts'] ?? false,
        ttsLastChunk: json['ttsLastChunk'] ?? 0,
        ttsTotalChunks: json['ttsTotalChunks'] ?? 0,
      );

  BookEntry copyWith({
    String? filePath,
    String? title,
    String? coverPath,
    List<BookmarkType>? bookmarks,
    DateTime? addedAt,
    DateTime? updatedAt,
    int? lastChapter,
    int? totalChapters,
    List<String>? customLabels,
    bool? lastWasTts,
    int? ttsLastChunk,
    int? ttsTotalChunks,
  }) {
    return BookEntry(
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      coverPath: coverPath ?? this.coverPath,
      bookmarks: bookmarks ?? this.bookmarks,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastChapter: lastChapter ?? this.lastChapter,
      totalChapters: totalChapters ?? this.totalChapters,
      customLabels: customLabels ?? this.customLabels,
      lastWasTts: lastWasTts ?? this.lastWasTts,
      ttsLastChunk: ttsLastChunk ?? this.ttsLastChunk,
      ttsTotalChunks: ttsTotalChunks ?? this.ttsTotalChunks,
    );
  }

  String get fileName => filePath.split('/').last;
  bool get fileExists => File(filePath).existsSync();
}
