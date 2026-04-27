import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'writer_screen.dart';
import '../services/epub_project_service.dart';
import '../services/storage_service.dart';
import '../models/bookmark_type.dart';
import '../models/episode_project.dart';

class WriterProjectsScreen extends StatefulWidget {
  const WriterProjectsScreen({super.key});

  @override
  State<WriterProjectsScreen> createState() => _WriterProjectsScreenState();
}

class _WriterProjectsScreenState extends State<WriterProjectsScreen> {
  List<EpisodeProject> _projects = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  final StorageService _storage = StorageService();
  bool _isGridView = false;
  final EpubProjectService _service = EpubProjectService();
  Set<BookmarkType> _selectedFilters = {};
  String _sortBy = 'date';

  List<EpisodeProject> get _filteredProjects {
    var projects = List<EpisodeProject>.from(_projects);
    
    if (_selectedFilters.isNotEmpty) {
      projects = projects.where((project) {
        return project.bookmarks.any((b) => _selectedFilters.contains(b));
      }).toList();
    }

    if (_sortBy == 'date') {
      projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else if (_sortBy == 'title') {
      projects.sort((a, b) => a.title.compareTo(b.title));
    }

    return projects;
  }

  void _toggleBookmark(EpisodeProject project, BookmarkType type) {
    setState(() {
      final idx = _projects.indexWhere((p) => p.id == project.id);
      if (idx != -1) {
        final projectEntry = _projects[idx];
        final bookmarks = List<BookmarkType>.from(projectEntry.bookmarks);
        
        if (type == BookmarkType.all) {
          if (bookmarks.contains(BookmarkType.all)) {
            bookmarks.remove(BookmarkType.all);
          } else {
            bookmarks.add(BookmarkType.all);
          }
        } else {
          if (bookmarks.contains(type)) {
            bookmarks.remove(type);
          } else {
            bookmarks.add(type);
          }
          if (!bookmarks.contains(BookmarkType.all)) {
            bookmarks.add(BookmarkType.all);
          }
        }
        
        final updated = EpisodeProject(
          id: projectEntry.id,
          title: projectEntry.title,
          epubPath: projectEntry.epubPath,
          coverPath: projectEntry.coverPath,
          createdAt: projectEntry.createdAt,
          updatedAt: projectEntry.updatedAt,
          bookmarks: bookmarks,
        );
        _projects[idx] = updated;
        _saveProject(updated);
      }
    });
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Filter & Sort',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        _selectedFilters = {};
                        _sortBy = 'date';
                      });
                      setState(() {});
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Sort by:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Date Modified'),
                    selected: _sortBy == 'date',
                    onSelected: (_) {
                      setSheetState(() => _sortBy = 'date');
                      setState(() {});
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Title'),
                    selected: _sortBy == 'title',
                    onSelected: (_) {
                      setSheetState(() => _sortBy = 'title');
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Filter by Bookmark:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: BookmarkType.values.map((type) {
                  return FilterChip(
                    label: Text(_getBookmarkLabel(type)),
                    selected: _selectedFilters.contains(type),
                    onSelected: (selected) {
                      setSheetState(() {
                        if (selected) {
                          _selectedFilters.add(type);
                        } else {
                          _selectedFilters.remove(type);
                        }
                      });
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _getBookmarkLabel(BookmarkType type) {
    switch (type) {
      case BookmarkType.all: return 'All';
      case BookmarkType.completed: return 'Completed';
      case BookmarkType.inProgress: return 'In Progress';
      case BookmarkType.dropped: return 'Dropped';
      case BookmarkType.favourite: return 'Favourite';
      case BookmarkType.custom: return 'Custom';
    }
  }

  Color _getBookmarkColor(BookmarkType type) {
    switch (type) {
      case BookmarkType.all: return Colors.grey;
      case BookmarkType.completed: return Colors.green;
      case BookmarkType.inProgress: return Colors.blue;
      case BookmarkType.dropped: return Colors.red;
      case BookmarkType.favourite: return Colors.amber;
      case BookmarkType.custom: return Colors.purple;
    }
  }

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    _hasPermission = await _storage.hasPermission();
    if (_hasPermission) {
      await _storage.ensureDirectories();
      await _loadProjects();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);

    try {
      final projectsDir = Directory(_storage.projectsPath);
      if (projectsDir.existsSync()) {
        final List<EpisodeProject> projects = [];
        final projectFolders = projectsDir.listSync();

        for (var projectFolder in projectFolders) {
          if (projectFolder is Directory) {
            final entities = projectFolder.listSync();
            for (var entity in entities) {
              if (entity is File && entity.path.endsWith('.json')) {
                try {
                  final content = await entity.readAsString();
                  final json = jsonDecode(content);
                  final project = EpisodeProject.fromJson(json);
                  projects.add(project);
                } catch (e) {
                  debugPrint('Error loading project ${entity.path}: $e');
                }
              }
            }
          }
        }
        _projects = projects;
      }
    } catch (e) {
      debugPrint('Error loading projects: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveProject(EpisodeProject project) async {
    final projectDir = Directory(_storage.getProjectDir(project.title));
    if (!projectDir.existsSync()) {
      projectDir.createSync(recursive: true);
    }
    
    final filePath = '${projectDir.path}/${_getJsonName(project.id, project.title)}';
    final file = File(filePath);
    await file.writeAsString(jsonEncode(project.toJson()));
  }

  String _getJsonName(String id, String title) {
    final sanitized = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$sanitized-$id.json';
  }

  void _showAddOptions() {
    if (!_hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please grant storage permission first')),
      );
      return;
    }
    
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
              leading: const Icon(Icons.file_upload, color: Colors.orange),
              title: const Text('Import EPUB'),
              subtitle: const Text('Import existing epub file'),
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
                final title = controller.text;
                final now = DateTime.now();
                final id = now.millisecondsSinceEpoch.toString();
                final projectDir = _storage.getProjectDir(title);
                
                String? epubPath;
                try {
                  epubPath = await _service.createEmptyEpub(
                    title,
                    id,
                    projectDir,
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error creating project: $e')),
                    );
                  }
                  return;
                }
                
                final project = EpisodeProject(
                  id: id,
                  title: title,
                  epubPath: epubPath,
                  createdAt: now,
                  updatedAt: now,
                  bookmarks: [BookmarkType.all],
                );
                
                await _saveProject(project);
                _projects.insert(0, project);
                if (mounted) {
                  setState(() {});
                  Navigator.pop(ctx);
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _importEpub() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );
      
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) {
          final now = DateTime.now();
          final id = now.millisecondsSinceEpoch.toString();
          
          // Get title from epub file name
          final fileName = path.split('/').last.split('\\').last;
          var title = fileName.replaceAll('.epub', '').replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
          
          // Create project folder
          final sanitizedTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
          final projectDir = '${_storage.projectsPath}/$sanitizedTitle';
          final dir = Directory(projectDir);
          if (!dir.existsSync()) dir.createSync(recursive: true);
          
          // Copy original epub to project folder with new name
          final epubPath = '$projectDir/$sanitizedTitle-$id.epub';
          File(path).copySync(epubPath);
          
          // Create project JSON
          final project = EpisodeProject(
            id: id,
            title: title,
            epubPath: epubPath,
            coverPath: null,
            createdAt: now,
            updatedAt: now,
            bookmarks: [BookmarkType.all],
          );
          
          await _saveProject(project);
          if (mounted) {
            _projects.insert(0, project);
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Imported: ${project.title}')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error importing epub: $e');
    }
  }

  Future<void> _deleteProject(EpisodeProject project) async {
    final projectDir = Directory(_storage.getProjectDir(project.title));
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }
    
    _projects.removeWhere((p) => p.id == project.id);
    setState(() {});
  }

  void _openProject(EpisodeProject project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WriterScreen(project: project, onSave: _saveProject),
      ),
    ).then((_) => _loadProjects());
  }

  @override
  Widget build(BuildContext context) {
    final filteredProjects = _filteredProjects;
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
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
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
              : filteredProjects.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.library_books_outlined, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('No Projects Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text('Tap + to create your first project or check filters', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : _isGridView
                      ? GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.75,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: filteredProjects.length,
                          itemBuilder: (context, index) {
                            final project = filteredProjects[index];
                            return _buildGridItem(project);
                          },
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredProjects.length,
                          separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final project = filteredProjects[index];
                            return _buildListItem(project);
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

  Widget _buildListItem(EpisodeProject project) {
    return Card(
      child: ListTile(
        leading: project.coverPath != null && File(project.coverPath!).existsSync()
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(project.coverPath!),
                  width: 40,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              )
            : CircleAvatar(
                backgroundColor: Colors.teal,
                child: Text(
                  project.title.isNotEmpty ? project.title[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
        title: Text(project.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last edited: ${_formatDate(project.updatedAt)}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: project.bookmarks.map((b) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getBookmarkColor(b).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getBookmarkLabel(b),
                  style: TextStyle(fontSize: 10, color: _getBookmarkColor(b), fontWeight: FontWeight.bold),
                ),
              )).toList(),
            ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
          ],
          onSelected: (value) async {
            if (value == 'delete') {
              await _deleteProject(project);
            } else if (value == 'rename') {
              _showRenameDialog(project);
            }
          },
        ),
        onTap: () => _openProject(project),
        onLongPress: () => _showProjectOptions(project),
      ),
    );
  }

  Widget _buildGridItem(EpisodeProject project) {
    return Card(
      child: InkWell(
        onTap: () => _openProject(project),
        onLongPress: () => _showProjectOptions(project),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                height: 100,
                child: project.coverPath != null && File(project.coverPath!).existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          File(project.coverPath!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          cacheHeight: 200,
                        ),
                      )
                    : Center(
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.teal,
                          child: Text(
                            project.title.isNotEmpty ? project.title[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                project.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                _formatDate(project.updatedAt),
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: project.bookmarks.take(3).map((b) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getBookmarkColor(b).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getBookmarkLabel(b),
                    style: TextStyle(fontSize: 8, color: _getBookmarkColor(b), fontWeight: FontWeight.bold),
                  ),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProjectOptions(EpisodeProject project) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              const Text('Bookmarks:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: BookmarkType.values.map((type) {
                  final isSelected = project.bookmarks.contains(type);
                  return FilterChip(
                    label: Text(_getBookmarkLabel(type)),
                    selected: isSelected,
                    onSelected: (_) {
                      _toggleBookmark(project, type);
                      setModalState(() {});
                    },
                  );
                }).toList(),
              ),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('Change Cover'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final path = await _service.pickCoverImage();
                  if (path != null) {
                    final projectDir = Directory(_storage.getProjectDir(project.title));
                    if (!projectDir.existsSync()) projectDir.createSync(recursive: true);
                    final ext = p.extension(path);
                    final newPath = '${projectDir.path}/cover$ext';
                    File(path).copySync(newPath);
                    
                    // Also update the internal EPUB's cover if it exists
                    if (project.epubPath != null) {
                      final imageBytes = await File(path).readAsBytes();
                      await _service.setCover(project.epubPath!, imageBytes, ext.replaceAll('.', ''));
                    }
                    
                    final updated = EpisodeProject(
                      id: project.id,
                      title: project.title,
                      epubPath: project.epubPath,
                      coverPath: newPath,
                      createdAt: project.createdAt,
                      updatedAt: DateTime.now(),
                      bookmarks: project.bookmarks,
                    );
                    await _saveProject(updated);
                    setState(() {
                      final idx = _projects.indexWhere((p) => p.id == project.id);
                      if (idx != -1) _projects[idx] = updated;
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Rename'),
                onTap: () { Navigator.pop(ctx); _showRenameDialog(project); },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () { 
                  Navigator.pop(ctx); 
                  _showDeleteConfirm(project);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirm(EpisodeProject project) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: Text('This will permanently delete "${project.title}" and all its files from storage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteProject(project);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(EpisodeProject project) {
    final controller = TextEditingController(text: project.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Project Title', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final updated = EpisodeProject(
                  id: project.id,
                  title: controller.text,
                  epubPath: project.epubPath,
                  coverPath: project.coverPath,
                  createdAt: project.createdAt,
                  updatedAt: DateTime.now(),
                  bookmarks: project.bookmarks,
                );
                await _saveProject(updated);
                setState(() {
                  final idx = _projects.indexWhere((p) => p.id == project.id);
                  if (idx != -1) _projects[idx] = updated;
                });
                if (mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _requestPermission() async {
    if (_hasPermission) {
      _loadProjects();
      return;
    }
    final granted = await _storage.requestPermission();
    if (granted) {
      setState(() => _hasPermission = true);
      _loadProjects();
    }
  }

  Future<void> refresh() async {
    await _loadProjects();
  }
}
