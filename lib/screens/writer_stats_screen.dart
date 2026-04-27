import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/storage_service.dart';

class WriterStatsScreen extends StatefulWidget {
  const WriterStatsScreen({super.key});

  @override
  State<WriterStatsScreen> createState() => _WriterStatsScreenState();
}

class _WriterStatsScreenState extends State<WriterStatsScreen> {
  List<EpisodeProject> _projects = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  String? _projectFolderPath;
  BookmarkType _selectedFilter = BookmarkType.all;
  bool _isGridView = false;
  final EpubProjectService _service = EpubProjectService();

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final storage = StorageService();
    _hasPermission = await storage.hasPermission();
    if (_hasPermission) {
      _projectFolderPath = storage.projectsPath;
      await _loadProjects();
    }
    setState(() => _isLoading = false);
  }

  List<EpisodeProject> get _filteredProjects {
    if (_selectedFilter == BookmarkType.all) {
      return _projects;
    }
    return _projects.where((p) => p.bookmarks.contains(_selectedFilter)).toList();
  }

  Future<void> _loadProjects() async {
    final storage = StorageService();
    await storage.ensureDirectories();
    _projectFolderPath = storage.projectsPath;
    _projects = [];

    try {
      final folder = Directory(_projectFolderPath!);
      if (await folder.exists()) {
        final entities = folder.listSync();
        for (var entity in entities) {
          if (entity is Directory) {
            final projectName = entity.path.split(Platform.pathSeparator).last;
            final metaFile = File('${entity.path}/project-$projectName.json');
            
            if (await metaFile.exists()) {
              try {
                final content = await metaFile.readAsString();
                final json = jsonDecode(content);
                final project = EpisodeProject.fromJson(json);
                _projects.add(project);
              } catch (e) {
                debugPrint('Error loading project meta in ${entity.path}: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading projects: $e');
    }

    setState(() => _isLoading = false);
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter Projects', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: BookmarkType.values.map((type) {
                final isSelected = _selectedFilter == type;
                return FilterChip(
                  label: Text(_getBookmarkLabel(type)),
                  selected: isSelected,
                  onSelected: (_) {
                    Navigator.pop(ctx);
                    setState(() => _selectedFilter = type);
                  },
                  avatar: isSelected ? const Icon(Icons.check, size: 18) : null,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _getBookmarkLabel(BookmarkType type) {
    switch (type) {
      case BookmarkType.all:
        return 'All';
      case BookmarkType.completed:
        return 'Completed';
      case BookmarkType.inProgress:
        return 'Reading';
      case BookmarkType.dropped:
        return 'Dropped';
      case BookmarkType.favourite:
        return 'Favourite';
      case BookmarkType.custom:
        return 'Custom';
    }
  }

  Color _getBookmarkColor(BookmarkType type) {
    switch (type) {
      case BookmarkType.all:
        return Colors.teal;
      case BookmarkType.completed:
        return Colors.green;
      case BookmarkType.inProgress:
        return Colors.blue;
      case BookmarkType.dropped:
        return Colors.red;
      case BookmarkType.favourite:
        return Colors.amber;
      case BookmarkType.custom:
        return Colors.purple;
    }
  }

  void _openProject(EpisodeProject project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WriterEpubStatsScreen(project: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Writer Stats'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterOptions,
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
                        onPressed: () async {
                          final status = await Permission.manageExternalStorage.request();
                          if (status.isGranted) {
                            setState(() => _hasPermission = true);
                            _loadProjects();
                          }
                        },
                        icon: const Icon(Icons.security),
                        label: const Text('Grant Permission'),
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
                          const Icon(Icons.library_books_outlined, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('No Projects Yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text('Create a project in Writer to see stats', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : _isGridView
                      ? GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _filteredProjects.length,
                          itemBuilder: (context, index) {
                            final project = _filteredProjects[index];
                            return _buildGridItem(project);
                          },
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredProjects.length,
                          separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final project = _filteredProjects[index];
                            return _buildListItem(project);
                          },
                        ),
    );
  }

  Widget _buildListItem(EpisodeProject project) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.teal,
          child: Icon(Icons.book, color: Colors.white),
        ),
        title: Text(project.title),
        subtitle: Text(
          project.epubPath?.split('/').last ?? 'No EPUB',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openProject(project),
      ),
    );
  }

  Widget _buildGridItem(EpisodeProject project) {
    return Card(
      child: InkWell(
        onTap: () => _openProject(project),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.book, size: 48, color: Colors.teal),
              const SizedBox(height: 12),
              Text(
                project.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap for stats',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}