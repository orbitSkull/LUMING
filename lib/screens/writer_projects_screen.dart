import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:io';
import 'writer_screen.dart';

enum ProjectBookmark {
  all,
  recent,
  favourite,
}

class Chapter {
  final String id;
  final String title;
  final String content;
  final int order;

  Chapter({
    required this.id,
    required this.title,
    this.content = '',
    required this.order,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'order': order,
  };

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    id: json['id'],
    title: json['title'],
    content: json['content'] ?? '',
    order: json['order'] ?? 0,
  );
}

class WriterProject {
  final String id;
  final String title;
  final String? epubPath;
  final List<Chapter> chapters;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProjectBookmark> bookmarks;

  WriterProject({
    required this.id,
    required this.title,
    this.epubPath,
    this.chapters = const [],
    required this.createdAt,
    required this.updatedAt,
    this.bookmarks = const [ProjectBookmark.all],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'epubPath': epubPath,
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'bookmarks': bookmarks.map((b) => b.name).toList(),
  };

  factory WriterProject.fromJson(Map<String, dynamic> json) => WriterProject(
    id: json['id'],
    title: json['title'],
    epubPath: json['epubPath'],
    chapters: (json['chapters'] as List?)?.map((c) => Chapter.fromJson(c)).toList() ?? [],
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
    bookmarks: (json['bookmarks'] as List?)?.map((b) => ProjectBookmark.values.firstWhere(
      (e) => e.name == b,
      orElse: () => ProjectBookmark.all,
    )).toList() ?? [ProjectBookmark.all],
  );
}

class WriterProjectsScreen extends StatefulWidget {
  const WriterProjectsScreen({super.key});

  @override
  State<WriterProjectsScreen> createState() => _WriterProjectsScreenState();
}

class _WriterProjectsScreenState extends State<WriterProjectsScreen> {
  List<WriterProject> _projects = [];
  String? _projectFolderPath;
  bool _isLoading = true;
  bool _hasPermission = false;
  bool _isGridView = false;
  ProjectBookmark _selectedBookmark = ProjectBookmark.all;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
    _hasPermission = await Permission.manageExternalStorage.isGranted;
    if (_hasPermission) {
      await _loadSettingsAndProjects();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSettingsAndProjects() async {
    final prefs = await SharedPreferences.getInstance();
    _projectFolderPath = prefs.getString('writerProjectFolder');
    
    await _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() {
      _isLoading = true;
      _projects = [];
    });

    if (_projectFolderPath != null) {
      try {
        final folder = Directory(_projectFolderPath!);
        if (await folder.exists()) {
          final files = folder.listSync();
          for (final entity in files) {
            if (entity is File && entity.path.endsWith('.json')) {
              try {
                final content = await entity.readAsString();
                final json = jsonDecode(content);
                final project = WriterProject.fromJson(json);
                _projects.add(project);
              } catch (e) {
                debugPrint('Error loading project ${entity.path}: $e');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading projects: $e');
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  List<WriterProject> get _filteredProjects {
    if (_selectedBookmark == ProjectBookmark.all) {
      return _projects;
    }
    return _projects.where((p) => p.bookmarks.contains(_selectedBookmark)).toList();
  }

  Future<void> _requestPermission() async {
    if (_hasPermission) {
      if (_projectFolderPath == null) {
        final folder = Directory('/storage/emulated/0/LUMING');
        if (!await folder.exists()) {
          await folder.create(recursive: true);
        }
        _projectFolderPath = folder.path;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('writerProjectFolder', folder.path);
      }
      _loadProjects();
      return;
    }

    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      _hasPermission = true;
      final folder = Directory('/storage/emulated/0/LUMING');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      _projectFolderPath = folder.path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('writerProjectFolder', folder.path);
      await _loadProjects();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission granted! Folder created.')),
        );
      }
    } else {
      await openAppSettings();
    }
    setState(() {});
  }

  Future<void> _saveProject(WriterProject project) async {
    if (_projectFolderPath == null) return;
    
    final sanitizedTitle = project.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final filePath = '$_projectFolderPath/$sanitizedTitle.json';
    
    final file = File(filePath);
    await file.writeAsString(jsonEncode(project.toJson()));
  }

  Future<void> _toggleBookmark(WriterProject project, ProjectBookmark bookmark) async {
    final updatedBookmarks = List<ProjectBookmark>.from(project.bookmarks);
    if (updatedBookmarks.contains(bookmark)) {
      updatedBookmarks.remove(bookmark);
    } else {
      updatedBookmarks.add(bookmark);
    }
    
    final updatedProject = WriterProject(
      id: project.id,
      title: project.title,
      epubPath: project.epubPath,
      chapters: project.chapters,
      createdAt: project.createdAt,
      updatedAt: project.updatedAt,
      bookmarks: updatedBookmarks,
    );
    
    await _saveProject(updatedProject);
    
    setState(() {
      final index = _projects.indexWhere((p) => p.id == project.id);
      if (index != -1) {
        _projects[index] = updatedProject;
      }
    });
  }

  Future<void> _deleteProject(WriterProject project) async {
    final sanitizedTitle = project.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final filePath = '$_projectFolderPath/$sanitizedTitle.json';
    
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
    
    _projects.removeWhere((p) => p.id == project.id);
    setState(() {});
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create, color: Colors.teal),
              title: const Text('New Empty Project'),
              subtitle: const Text('Start from scratch'),
              onTap: () {
                Navigator.pop(ctx);
                _showNewProjectDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.orange),
              title: const Text('Import EPUB to Edit'),
              subtitle: const Text('Import existing EPUB to write on'),
              onTap: () {
                Navigator.pop(ctx);
                _importEpub();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showNewProjectDialog() {
    if (!_hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please grant storage permission first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Project Title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final now = DateTime.now();
                final project = WriterProject(
                  id: now.millisecondsSinceEpoch.toString(),
                  title: controller.text,
                  createdAt: now,
                  updatedAt: now,
                );
                
                await _saveProject(project);
                _projects.insert(0, project);
                setState(() {});
                if (mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showBookmarkSheet(WriterProject project) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bookmarks for "${project.title}"',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: ProjectBookmark.values.map((bookmark) {
                final isSelected = project.bookmarks.contains(bookmark);
                return FilterChip(
                  label: Text(bookmark.name.toUpperCase()),
                  selected: isSelected,
                  selectedColor: Colors.teal[200],
                  onSelected: (_) {
                    _toggleBookmark(project, bookmark);
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _openProject(WriterProject project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WriterScreen(project: project, onSave: _saveProject),
      ),
    ).then((_) => _loadProjects());
  }

  Future<void> _importEpub() async {
    if (!_hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please grant storage permission first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported: ${file.name}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        backgroundColor: Colors.teal,
        leading: IconButton(
          icon: const Icon(Icons.folder),
          onPressed: _requestPermission,
        ),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          PopupMenuButton<ProjectBookmark>(
            icon: const Icon(Icons.filter_list),
            onSelected: (bookmark) => setState(() => _selectedBookmark = bookmark),
            itemBuilder: (ctx) => ProjectBookmark.values.map((bookmark) {
              return PopupMenuItem(
                value: bookmark,
                child: Text(bookmark.name.toUpperCase()),
              );
            }).toList(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_hasPermission
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_open, size: 64, color: Colors.teal),
                      const SizedBox(height: 16),
                      const Text('Storage Permission Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Grant access to save your projects', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _requestPermission,
                        icon: const Icon(Icons.security),
                        label: const Text('Set Up Storage'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                      ),
                    ],
                  ),
                )
              : _filteredProjects.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.edit_note, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('No projects yet', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _showNewProjectDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Create Project'),
                          ),
                        ],
                      ),
                    )
                  : _isGridView
                      ? GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _filteredProjects.length,
                          itemBuilder: (context, index) {
                            final project = _filteredProjects[index];
                            return Card(
                              child: InkWell(
                                onTap: () => _openProject(project),
                                onLongPress: () => _showBookmarkSheet(project),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        width: double.infinity,
                                        color: Colors.teal[100],
                                        child: const Icon(Icons.book, size: 48, color: Colors.teal),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            project.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            '${project.chapters.length} chapters',
                                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _filteredProjects.length,
                          itemBuilder: (context, index) {
                            final project = _filteredProjects[index];
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Colors.teal,
                                  child: Icon(Icons.book, color: Colors.white),
                                ),
                                title: Text(project.title),
                                subtitle: Text('${project.chapters.length} chapters'),
                                trailing: PopupMenuButton(
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'bookmark',
                                      child: Text('Bookmark'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                  onSelected: (value) async {
                                    if (value == 'delete') {
                                      await _deleteProject(project);
                                    } else if (value == 'bookmark') {
                                      _showBookmarkSheet(project);
                                    }
                                  },
                                ),
                                onTap: () => _openProject(project),
                                onLongPress: () => _showBookmarkSheet(project),
                              ),
                            );
                          },
                        ),
      floatingActionButton: _hasPermission
          ? FloatingActionButton(
              onPressed: _showAddOptions,
              backgroundColor: Colors.teal,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}