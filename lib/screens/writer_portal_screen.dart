import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import '../services/storage_service.dart';

class ReaderPortalScreen extends StatefulWidget {
  final VoidCallback onGoToLibrary;
  
  const ReaderPortalScreen({super.key, required this.onGoToLibrary});

  @override
  State<ReaderPortalScreen> createState() => _ReaderPortalScreenState();
}

class _ReaderPortalScreenState extends State<ReaderPortalScreen> {
  List<YourCreation> _creations = [];
  
  @override
  void initState() {
    super.initState();
    _loadCreations();
  }

  Future<void> _loadCreations() async {
    final storage = StorageService();
    final file = File(storage.publishedFile);

    if (await file.exists()) {
      try {
        final data = await file.readAsString();
        final list = jsonDecode(data) as List;
        setState(() {
          _creations = list.map((e) => YourCreation.fromJson(e)).toList();
        });
        return;
      } catch (e) {
        debugPrint('Error loading creations from external storage: $e');
      }
    }

    // Fallback to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('yourCreations');
    if (data != null) {
      final list = jsonDecode(data) as List;
      setState(() {
        _creations = list.map((e) => YourCreation.fromJson(e)).toList();
      });
      // Migrate to external storage if possible
      try {
        await storage.ensureDirectories();
        await file.writeAsString(data);
      } catch (e) {
        debugPrint('Error migrating creations to external storage: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reader Portal'),
        backgroundColor: Colors.teal,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: Colors.teal[50],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.menu_book, size: 64, color: Colors.teal),
                  const SizedBox(height: 16),
                  Text(
                    '${_creations.length} Your Creations',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                  const Text('Published works from Writer mode', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: widget.onGoToLibrary,
                    icon: const Icon(Icons.library_books),
                    label: const Text('Go to Library'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 3,
            child: _creations.isEmpty 
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No creations yet', style: TextStyle(color: Colors.grey)),
                        Text('Publish from Writer mode to see them here', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _creations.length,
                    itemBuilder: (context, index) {
                      final creation = _creations[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.book, color: Colors.teal),
                          title: Text(creation.title),
                          subtitle: Text('${creation.wordCount} words • ${creation.chapters} chapters'),
                          trailing: IconButton(
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => _openCreation(creation),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openCreation(YourCreation creation) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening: ${creation.title}')),
    );
  }
}

class YourCreation {
  final String id;
  final String title;
  final int wordCount;
  final int chapters;
  final DateTime createdAt;
  final String? filePath;

  YourCreation({
    required this.id,
    required this.title,
    required this.wordCount,
    required this.chapters,
    required this.createdAt,
    this.filePath,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'wordCount': wordCount,
    'chapters': chapters,
    'createdAt': createdAt.toIso8601String(),
    'filePath': filePath,
  };

  factory YourCreation.fromJson(Map<String, dynamic> json) => YourCreation(
    id: json['id'],
    title: json['title'],
    wordCount: json['wordCount'] ?? 0,
    chapters: json['chapters'] ?? 0,
    createdAt: DateTime.parse(json['createdAt']),
    filePath: json['filePath'],
  );
}