import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ideabox_service.dart';

class IdeaBoxScreen extends StatefulWidget {
  const IdeaBoxScreen({super.key});

  @override
  State<IdeaBoxScreen> createState() => _IdeaBoxScreenState();
}

class _IdeaBoxScreenState extends State<IdeaBoxScreen> {
  final IdeaBoxService _service = IdeaBoxService();
  String _selectedCategory = 'all';
  String _searchQuery = '';
  final Set<String> _selectedIdeas = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _service.loadIdeas();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIdeas.contains(id)) {
        _selectedIdeas.remove(id);
      } else {
        _selectedIdeas.add(id);
      }
    });
  }

  void _deleteSelected() async {
    if (_selectedIdeas.isEmpty) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Ideas'),
        content: Text('Delete ${_selectedIdeas.length} selected idea(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (final id in _selectedIdeas) {
        await _service.deleteIdea(id);
      }
      setState(() {
        _selectedIdeas.clear();
        _isSelectionMode = false;
      });
    }
  }

  Future<void> _exportIdeas() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        final ideas = _service.ideas;
        final data = ideas.map((e) => e.toJson()).toList();
        final jsonString = const JsonEncoder.withIndent('  ').convert(data);
        
        final file = File('$result/ideabox_export.json');
        await file.writeAsString(jsonString);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported to $result/ideabox_export.json')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _importIdeas() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        final content = await file.readAsString();
        final List<dynamic> data = jsonDecode(content);
        
        int imported = 0;
        for (final item in data) {
          await _service.addIdea(
            item['content'] ?? '',
            category: item['category'] ?? 'general',
            tags: List<String>.from(item['tags'] ?? []),
          );
          imported++;
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported $imported ideas')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showAddIdeaDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        String category = 'general';
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('New Idea'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Write your idea...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  items: _service.categories.map((c) => 
                    DropdownMenuItem(value: c, child: Text(c.toUpperCase()))
                  ).toList(),
                  onChanged: (value) => setDialogState(() => category = value!),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  if (controller.text.isNotEmpty) {
                    await _service.addIdea(controller.text, category: category);
                    if (ctx.mounted) {
                      setState(() {});
                      Navigator.pop(ctx);
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _searchQuery.isEmpty 
        ? _service.getIdeasByCategory(_selectedCategory)
        : _service.searchIdeas(_searchQuery);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? '${_selectedIdeas.length} selected' : 'IdeaBox'),
        backgroundColor: Colors.teal,
        leading: _isSelectionMode 
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectedIdeas.clear();
                  _isSelectionMode = false;
                }),
              )
            : null,
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteSelected,
            )
          else ...[
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'export') {
                  _exportIdeas();
                } else if (value == 'import') {
                  _importIdeas();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'export', child: Text('Export IdeaBox')),
                const PopupMenuItem(value: 'import', child: Text('Import IdeaBox')),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search ideas...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                'all', ..._service.categories
              ].map((cat) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(cat.toUpperCase()),
                  selected: _selectedCategory == cat,
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                  selectedColor: Colors.teal[200],
                ),
              )).toList(),
            ),
          ),
          const Divider(),
          Expanded(
            child: filtered.isEmpty 
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lightbulb_outline, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        const Text('No ideas yet', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _showAddIdeaDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Idea'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final idea = filtered[index];
                      final isSelected = _selectedIdeas.contains(idea.id);
                      return Card(
                        color: isSelected ? Colors.teal[50] : null,
                        child: ListTile(
                          leading: _isSelectionMode
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (_) => _toggleSelection(idea.id),
                                )
                              : Icon(
                                  idea.isVoiceNote ? Icons.mic : Icons.lightbulb,
                                  color: Colors.teal,
                                ),
                          title: Text(
                            idea.content.length > 50 
                                ? '${idea.content.substring(0, 50)}...'
                                : idea.content,
                            maxLines: 2,
                          ),
                          subtitle: Text(
                            '${idea.category.toUpperCase()} • ${_formatDate(idea.createdAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: _isSelectionMode 
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () async {
                                    await _service.deleteIdea(idea.id);
                                    setState(() {});
                                  },
                                ),
                          onTap: () {
                            if (_isSelectionMode) {
                              _toggleSelection(idea.id);
                            } else {
                              _showIdeaDetail(idea);
                            }
                          },
                          onLongPress: () {
                            setState(() {
                              _isSelectionMode = true;
                              _selectedIdeas.add(idea.id);
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddIdeaDialog,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showIdeaDetail(IdeaNote idea) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(idea.category.toUpperCase()),
        content: SingleChildScrollView(child: Text(idea.content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              await _service.deleteIdea(idea.id);
              if (ctx.mounted) {
                setState(() {});
                Navigator.pop(ctx);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}