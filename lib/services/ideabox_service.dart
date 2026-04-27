import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';

class IdeaNote {
  final String id;
  final String content;
  final String category;
  final List<String> tags;
  final DateTime createdAt;
  final bool isVoiceNote;

  IdeaNote({
    required this.id,
    required this.content,
    this.category = 'general',
    this.tags = const [],
    required this.createdAt,
    this.isVoiceNote = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'category': category,
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'isVoiceNote': isVoiceNote,
  };

  factory IdeaNote.fromJson(Map<String, dynamic> json) => IdeaNote(
    id: json['id'],
    content: json['content'],
    category: json['category'] ?? 'general',
    tags: List<String>.from(json['tags'] ?? []),
    createdAt: DateTime.parse(json['createdAt']),
    isVoiceNote: json['isVoiceNote'] ?? false,
  );
}

class WritingPrompt {
  static final List<String> _prompts = [
    'What if the main character woke up with a mysterious ability?',
    'Describe a world where dreams are currency.',
    'A letter arrives 50 years too late.',
    'The last human meets an alien who loves poetry.',
    'Two strangers are trapped in an elevator.',
    'A detective discovers the victim was their future self.',
    'What happens when time starts moving backward?',
    'A character must choose between saving one person or many.',
    'The map leads to somewhere impossible.',
    'A gift that changes everything about the recipient.',
    'Two enemies must work together to survive.',
    'What would happen if no one could lie?',
    'A character discovers their memory is fake.',
    'The power was inside them all along.',
    'Three wishes, but with unexpected consequences.',
  ];

  static final List<String> _genres = ['Fantasy', 'Sci-Fi', 'Mystery', 'Romance', 'Horror', 'Thriller'];

  static String getRandomPrompt() {
    _prompts.shuffle();
    return _prompts.first;
  }

  static String getRandomGenre() {
    _genres.shuffle();
    return _genres.first;
  }

  static Map<String, String> getPromptWithGenre() {
    return {
      'prompt': getRandomPrompt(),
      'genre': getRandomGenre(),
    };
  }
}

class IdeaBoxService {
  static final IdeaBoxService _instance = IdeaBoxService._internal();
  factory IdeaBoxService() => _instance;
  IdeaBoxService._internal();

  final StorageService _storageService = StorageService();
  List<IdeaNote> _ideas = [];
  final List<String> _categories = ['general', 'character', 'plot', 'dialogue', 'setting', 'world'];

  List<IdeaNote> get ideas => _ideas;
  List<String> get categories => _categories;

  Future<void> loadIdeas() async {
    try {
      final file = File(_storageService.ideaboxFile);
      if (await file.exists()) {
        final data = await file.readAsString();
        final list = jsonDecode(data) as List;
        _ideas = list.map((e) => IdeaNote.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Error loading ideabox ideas: $e');
    }
  }

  Future<void> _saveIdeas() async {
    try {
      await _storageService.ensureDirectories();
      final file = File(_storageService.ideaboxFile);
      final data = jsonEncode(_ideas.map((e) => e.toJson()).toList());
      await file.writeAsString(data);
    } catch (e) {
      debugPrint('Error saving ideabox ideas: $e');
    }
  }

  Future<void> addIdea(String content, {String category = 'general', List<String>? tags, bool isVoiceNote = false}) async {
    final idea = IdeaNote(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      category: category,
      tags: tags ?? [],
      createdAt: DateTime.now(),
      isVoiceNote: isVoiceNote,
    );
    _ideas.insert(0, idea);
    await _saveIdeas();
  }

  Future<void> deleteIdea(String id) async {
    _ideas.removeWhere((idea) => idea.id == id);
    await _saveIdeas();
  }

  Future<void> addCategory(String name) async {
    if (!_categories.contains(name.toLowerCase())) {
      _categories.add(name.toLowerCase());
    }
  }

  List<IdeaNote> getIdeasByCategory(String category) {
    if (category == 'all') return _ideas;
    return _ideas.where((idea) => idea.category == category).toList();
  }

  List<IdeaNote> searchIdeas(String query) {
    final lowerQuery = query.toLowerCase();
    return _ideas.where((idea) => 
      idea.content.toLowerCase().contains(lowerQuery) ||
      idea.tags.any((tag) => tag.toLowerCase().contains(lowerQuery))
    ).toList();
  }
}