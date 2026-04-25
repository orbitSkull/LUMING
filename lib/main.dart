import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'screens/reader_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/stats_screen.dart';
import 'providers/reader_settings.dart';
import 'services/tts_service.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final darkMode = prefs.getBool('darkMode') ?? false;
  
  runApp(DaPubReaderApp(initialDarkMode: darkMode));
}

class DaPubReaderApp extends StatelessWidget {
  final bool initialDarkMode;

  const DaPubReaderApp({super.key, required this.initialDarkMode});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ReaderSettings()),
        ChangeNotifierProvider(create: (_) => TtsService()),
      ],
      child: MaterialApp(
        title: 'DaPub Reader',
        debugShowCheckedModeBanner: false,
        themeMode: initialDarkMode ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<BookEntry> _books = [];
  Set<BookmarkType> _selectedFilters = {};
  String _sortBy = 'date';
  bool _isLoading = false;
  int _currentIndex = 0;

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

  Future<void> _continueReading() async {
    final prefs = await SharedPreferences.getInstance();
    final lastPath = prefs.getString('lastOpenedPath');
    if (lastPath != null && File(lastPath).existsSync()) {
      final chapterIndex = prefs.getInt('chapter_$lastPath') ?? 0;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReaderScreen(
            filePath: lastPath,
            startChapter: chapterIndex,
          ),
        ),
      ).then((_) => _loadBooks());
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No book to continue')),
        );
      }
    }
  }

  void _showWriterToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming Soon')),
    );
  }

  Future<void> _openFile() async {
    setState(() => _isLoading = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'mobi', 'azw3', 'fb2'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String filePath;

        if (!kIsWeb && file.path != null) {
          filePath = file.path!;
        } else if (file.bytes != null) {
          final tempDir = Directory.systemTemp;
          final tempFile = File('${tempDir.path}/${file.name}');
          await tempFile.writeAsBytes(file.bytes!);
          filePath = tempFile.path;
        } else if (file.path != null) {
          filePath = file.path!;
        } else {
          throw Exception('No file selected');
        }

        if (mounted) {
          final isNew = !_books.any((b) => b.filePath == filePath);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReaderScreen(
                filePath: filePath,
                startChapter: 0,
              ),
            ),
          ).then((_) {
            _loadBooks();
            if (isNew) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Added to the library')),
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
        onOpen: () => _openBook(book),
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

  void _openBook(BookEntry book) async {
    final prefs = await SharedPreferences.getInstance();
    final chapterIndex = prefs.getInt('chapter_${book.filePath}') ?? 0;
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(
          filePath: book.filePath,
          startChapter: chapterIndex,
        ),
      ),
    ).then((_) => _loadBooks());
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

  Widget _buildLibrary() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: _books.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.library_books_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No books in library'),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap + to add your first book',
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
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  trailing: const Icon(Icons.more_vert),
                  onTap: () => _openBook(book),
                  onLongPress: () => _showBookOptions(book),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => _onNavTap(index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        selectedItemColor: isDark ? Colors.deepPurple[300] : Colors.deepPurple,
        unselectedItemColor: isDark ? Colors.grey[500] : Colors.grey[600],
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books_outlined),
            activeIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle_outline),
            activeIcon: Icon(Icons.play_circle),
            label: 'Continue',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.edit_outlined),
            activeIcon: Icon(Icons.edit),
            label: 'Writer',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _openFile,
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildLibrary();
      case 2:
        return const StatsScreen();
      case 3:
        return const SizedBox.shrink();
      case 4:
        return const SettingsScreen();
      default:
        return _buildLibrary();
    }
  }

  void _onNavTap(int index) {
    if (index == 1) {
      _continueReading();
      return;
    }
    if (index == 3) {
      _showWriterToast();
      return;
    }
    setState(() => _currentIndex = index);
  }
}

class _BookOptionsSheet extends StatelessWidget {
  final BookEntry book;
  final Function(BookmarkType) onBookmarkToggle;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _BookOptionsSheet({
    required this.book,
    required this.onBookmarkToggle,
    required this.onOpen,
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.book),
              label: const Text('Open Book'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmDelete(context),
              icon: const Icon(Icons.delete_forever, color: Colors.red),
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

  void _confirmDelete(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Book'),
        content: Text('Remove "${book.title}" from library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}