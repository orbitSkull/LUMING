import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

enum BookmarkType {
  all,
  completed,
  inProgress,
  dropped,
  favourite,
  custom,
}

class BookEntry {
  final String filePath;
  final String title;
  final String? coverPath;
  final List<BookmarkType> bookmarks;
  final DateTime addedAt;
  final int lastChapter;

  BookEntry({
    required this.filePath,
    required this.title,
    this.coverPath,
    required this.bookmarks,
    required this.addedAt,
    this.lastChapter = 0,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'title': title,
        'coverPath': coverPath,
        'bookmarks': bookmarks.map((b) => b.name).toList(),
        'addedAt': addedAt.toIso8601String(),
        'lastChapter': lastChapter,
      };

  factory BookEntry.fromJson(Map<String, dynamic> json) => BookEntry(
        filePath: json['filePath'],
        title: json['title'],
        coverPath: json['coverPath'],
        bookmarks: (json['bookmarks'] as List)
            .map((b) => BookmarkType.values.firstWhere((e) => e.name == b))
            .toList(),
        addedAt: DateTime.parse(json['addedAt']),
        lastChapter: json['lastChapter'] ?? 0,
      );

  String get fileName => filePath.split('/').last;

  bool get fileExists => File(filePath).existsSync();
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<BookEntry> _books = [];
  Set<BookmarkType> _selectedFilters = {};
  String _sortBy = 'date';
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBooks();
  }

  Future<void> refresh() async {
    await _loadBooks();
  }

  Future<void> _loadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('library');
    if (data != null) {
      final list = jsonDecode(data) as List;
      setState(() {
        _books = list.map((e) => BookEntry.fromJson(e)).toList();
        _books.removeWhere((b) => !b.fileExists);
      });
    }
  }

  Future<void> _saveBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_books.map((e) => e.toJson()).toList());
    await prefs.setString('library', data);
  }

  Future<void> addToLibrary(String filePath, String title) async {
    final exists = _books.any((b) => b.filePath == filePath);
    if (!exists) {
      setState(() {
        _books.add(BookEntry(
          filePath: filePath,
          title: title,
          bookmarks: [BookmarkType.all],
          addedAt: DateTime.now(),
        ));
      });
      await _saveBooks();
    }
  }

  List<BookEntry> get _filteredBooks {
    var books = List<BookEntry>.from(_books);
    
    if (_selectedFilters.isNotEmpty) {
      books = books.where((book) {
        return book.bookmarks.any((b) => _selectedFilters.contains(b));
      }).toList();
    }

    if (_sortBy == 'date') {
      books.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    } else if (_sortBy == 'title') {
      books.sort((a, b) => a.title.compareTo(b.title));
    }

    return books;
  }

  void _showBookOptions(BookEntry book) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _BookOptionsSheet(
        book: book,
        onBookmarkToggle: (type) => _toggleBookmark(book, type),
        onDelete: () => _deleteBook(book),
      ),
    );
  }

  void _toggleBookmark(BookEntry book, BookmarkType type) {
    setState(() {
      final idx = _books.indexWhere((b) => b.filePath == book.filePath);
      if (idx != -1) {
        final bookEntry = _books[idx];
        final bookmarks = List<BookmarkType>.from(bookEntry.bookmarks);
        
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
        
        _books[idx] = BookEntry(
          filePath: bookEntry.filePath,
          title: bookEntry.title,
          coverPath: bookEntry.coverPath,
          bookmarks: bookmarks,
          addedAt: bookEntry.addedAt,
          lastChapter: bookEntry.lastChapter,
        );
        _saveBooks();
      }
    });
    Navigator.pop(context);
  }

  void _deleteBook(BookEntry book) {
    setState(() {
      _books.removeWhere((b) => b.filePath == book.filePath);
      _saveBooks();
    });
    Navigator.pop(context);
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
                    label: const Text('Date Added'),
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
      case BookmarkType.all:
        return 'All';
      case BookmarkType.completed:
        return 'Completed';
      case BookmarkType.inProgress:
        return 'In Progress';
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
        return Colors.grey;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_list : Icons.filter_list_outlined),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: _books.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.library_books_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No books in library'),
                  SizedBox(height: 8),
                  Text(
                    'Open an EPUB to add it here',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _filteredBooks.length,
              itemBuilder: (context, index) {
                final book = _filteredBooks[index];
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        book.title.isNotEmpty ? book.title[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: book.bookmarks.map((b) {
                      return Chip(
                        label: Text(
                          _getBookmarkLabel(b),
                          style: TextStyle(
                            fontSize: 10,
                            color: _getBookmarkColor(b),
                          ),
                        ),
                        backgroundColor: _getBookmarkColor(b).withOpacity(0.1),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  trailing: const Icon(Icons.more_vert),
                  onTap: () => _showBookOptions(book),
                  onLongPress: () => _showBookOptions(book),
                );
              },
            ),
    );
  }
}

class _BookOptionsSheet extends StatelessWidget {
  final BookEntry book;
  final Function(BookmarkType) onBookmarkToggle;
  final VoidCallback onDelete;

  const _BookOptionsSheet({
    required this.book,
    required this.onBookmarkToggle,
    required this.onDelete,
  });

  String _getBookmarkLabel(BookmarkType type) {
    switch (type) {
      case BookmarkType.all:
        return 'All';
      case BookmarkType.completed:
        return 'Completed';
      case BookmarkType.inProgress:
        return 'In Progress';
      case BookmarkType.dropped:
        return 'Dropped';
      case BookmarkType.favourite:
        return 'Favourite';
      case BookmarkType.custom:
        return 'Custom';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            book.title,
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            book.fileName,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          const Text('Bookmarks:'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: BookmarkType.values.map((type) {
              final isSelected = book.bookmarks.contains(type);
              return FilterChip(
                label: Text(_getBookmarkLabel(type)),
                selected: isSelected,
                onSelected: (_) => onBookmarkToggle(type),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onDelete();
              },
              icon: const Icon(Icons.delete, color: Colors.red),
              label: const Text(
                'Remove from Library',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }
}