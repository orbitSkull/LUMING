import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:just_audio_background/just_audio_background.dart';
import 'services/storage_service.dart';
import 'services/ideabox_service.dart';
import 'models/bookmark_type.dart';
import 'models/book_entry.dart';
import 'screens/reader_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/writer_stats_screen.dart';
import 'screens/writer_portal_screen.dart';
import 'screens/writer_settings_screen.dart';
import 'screens/ideabox_screen.dart';
import 'screens/writer_projects_screen.dart';
import 'providers/reader_settings.dart';
import 'services/tts_service.dart';
import 'services/writer_service.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.orbitskull.luming.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  final prefs = await SharedPreferences.getInstance();
  final darkMode = prefs.getBool('darkMode') ?? false;
  
  runApp(LumingApp(initialDarkMode: darkMode));
}

class LumingApp extends StatelessWidget {
  final bool initialDarkMode;

  const LumingApp({super.key, required this.initialDarkMode});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ReaderSettings()),
        ChangeNotifierProvider(create: (_) => TtsService()),
      ],
      child: Consumer<ReaderSettings>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'LUMING',
            debugShowCheckedModeBanner: false,
            themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
              useMaterial3: true,
              fontFamily: 'Inter',
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6C63FF),
                brightness: Brightness.dark,
                surface: const Color(0xFF121212),
              ),
              useMaterial3: true,
              fontFamily: 'Inter',
            ),
            initialRoute: '/',
            routes: {
              '/': (context) => const SplashScreen(),
              '/home': (context) => const HomeScreen(),
            },
          );
        },
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
  bool _isWriterMode = false;
  bool _hasPermission = false;
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    _hasPermission = await _storage.hasPermission();
    if (_hasPermission) {
      await _storage.ensureDirectories();
      await _loadData();
    }
    setState(() {});
  }

  Future<void> _loadData() async {
    _loadBooks();
    WriterService().loadStats();
    IdeaBoxService().loadIdeas();
    _ensureStatsInitialized();
  }

  Future<void> _ensureStatsInitialized() async {
    final statsFile = File(_storage.overallStatsFile);
    if (!statsFile.existsSync()) {
      await statsFile.writeAsString(jsonEncode({
        'totalBooks': 0,
        'booksCompleted': 0,
        'chaptersRead': 0,
        'totalListeningMinutes': 0,
        'currentStreak': 0,
        'avgTtsSpeed': 1.0,
        'listeningSessions': 0,
        'wordsRead': 0,
        'completedBooksPaths': [],
        'lastActiveDate': '',
      }));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    if (!_hasPermission) return;
    try {
      final libraryDir = Directory(_storage.libraryPath);
      if (libraryDir.existsSync()) {
        final List<BookEntry> books = [];
        final entities = libraryDir.listSync();
        for (var entity in entities) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              final content = await entity.readAsString();
              books.add(BookEntry.fromJson(jsonDecode(content)));
            } catch (_) {}
          }
        }
        setState(() {
          _books = books;
          _books.removeWhere((b) => !b.fileExists);
        });
      }
    } catch (_) {}
  }

  Future<void> _saveBooks() async {
    // Books are saved individually in their own files now.
    // This method might not be needed globally anymore, but for backward compatibility
    // or batch updates, it could iterate through _books.
    for (var book in _books) {
      final file = File(_storage.getBookEntryFile(book.title));
      await file.writeAsString(jsonEncode(book.toJson()));
    }
  }

  Future<void> _continueReading() async {
    if (!_hasPermission) {
       _requestPermission();
       return;
    }
    final continueFile = File(_storage.continueFile);
    if (continueFile.existsSync()) {
      try {
        final data = jsonDecode(await continueFile.readAsString());
        final lastPath = data['lastOpenedPath'];
        if (lastPath != null && File(lastPath).existsSync()) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReaderScreen(
                filePath: lastPath,
                startChapter: data['chapterIndex'] ?? 0,
                isTts: data['isTts'] ?? false,
                startChunk: data['chunkIndex'] ?? 0,
              ),
            ),
          ).then((_) => _loadBooks());
          return;
        }
      } catch (_) {}
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No book to continue')),
      );
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
      isScrollControlled: true,
      builder: (context, settings, child) => _BookOptionsSheet(
        book: book,
        globalCustomLabels: settings.globalCustomLabels,
        onBookmarkToggle: (type) => _toggleBookmark(book, type),
        onCustomLabelAdd: (name) => _addCustomLabel(book, name),
        onCustomLabelRemove: (name) => _removeCustomLabel(book, name),
        onOpen: () {
          Navigator.pop(context);
          _openBook(book);
        },
        onDelete: () {
          Navigator.pop(context);
          _deleteBook(book);
        },
      ),
    );
  }

  void _addCustomLabel(BookEntry book, String name) {
    final settings = Provider.of<ReaderSettings>(context, listen: false);
    settings.addGlobalCustomLabel(name);

    setState(() {
      final idx = _books.indexWhere((b) => b.filePath == book.filePath);
      if (idx != -1) {
        final customLabels = List<String>.from(_books[idx].customLabels);
        if (!customLabels.contains(name)) {
          customLabels.add(name);
        }
        _books[idx] = _books[idx].copyWith(customLabels: customLabels);
        _saveBooks();
      }
    });
  }

  void _removeCustomLabel(BookEntry book, String name) {
    setState(() {
      final idx = _books.indexWhere((b) => b.filePath == book.filePath);
      if (idx != -1) {
        final customLabels = List<String>.from(_books[idx].customLabels);
        customLabels.remove(name);
        _books[idx] = _books[idx].copyWith(customLabels: customLabels);
        _saveBooks();
      }
    });
  }

  void _toggleBookmark(BookEntry book, BookmarkType type) {
    setState(() {
      final idx = _books.indexWhere((b) => b.filePath == book.filePath);
      if (idx != -1) {
        final bookmarks = List<BookmarkType>.from(_books[idx].bookmarks);
        
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
        
        _books[idx] = _books[idx].copyWith(bookmarks: bookmarks);
        _saveBooks();
      }
    });
    Navigator.pop(context);
  }

  void _openBook(BookEntry book) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(
          filePath: book.filePath,
          startChapter: book.lastChapter,
          isTts: book.lastWasTts,
          startChunk: book.ttsLastChunk,
        ),
      ),
    ).then((_) => _loadBooks());
  }

  void _deleteBook(BookEntry book) {
    if (book.coverPath != null && book.coverPath!.isNotEmpty) {
      final coverFile = File(book.coverPath!);
      if (coverFile.existsSync()) {
        try {
          coverFile.deleteSync();
        } catch (_) {}
      }
    }
    setState(() {
      _books.removeWhere((b) => b.filePath == book.filePath);
      _saveBooks();
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
    return Consumer<ReaderSettings>(
      builder: (context, settings, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Library'),
            actions: [
              IconButton(
                icon: Icon(settings.libraryGridView ? Icons.view_list : Icons.grid_view),
                onPressed: () => settings.setLibraryGridView(!settings.libraryGridView),
                tooltip: settings.libraryGridView ? 'Switch to List View' : 'Switch to Grid View',
              ),
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilterSheet,
                tooltip: 'Filter & Sort',
              ),
            ],
          ),
          body: !_hasPermission 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_open, size: 64, color: Color(0xFF6C63FF)),
                      const SizedBox(height: 16),
                      const Text('Storage Permission Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _requestPermission,
                        icon: const Icon(Icons.security),
                        label: const Text('Set Up Storage'),
                      ),
                    ],
                  ),
                )
              : _books.isEmpty
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
                  : settings.libraryGridView ? _buildGridView() : _buildListView(),
        );
      },
    );
  }

  Future<void> _requestPermission() async {
    final granted = await _storage.requestPermission();
    if (granted) {
      setState(() => _hasPermission = true);
      _loadData();
    }
  }

  Widget _buildListView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _filteredBooks.length,
      itemBuilder: (context, index) {
        final book = _filteredBooks[index];
        final progress = book.totalChapters > 1 
            ? (book.lastChapter / book.totalChapters * 100).clamp(0, 100).toInt() 
            : 0;

        return Card(
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.15),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openBook(book),
            onLongPress: () => _showBookOptions(book),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBookCover(book, width: 56, height: 80, borderRadius: 8),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: book.bookmarks.map((b) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getBookmarkColor(b).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _getBookmarkColor(b).withOpacity(0.3)),
                              ),
                              child: Text(
                                _getBookmarkLabel(b),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _getBookmarkColor(b),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: book.totalChapters > 1 ? book.lastChapter / book.totalChapters : 0,
                                backgroundColor: isDark ? Colors.white24 : Colors.black12,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$progress%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showBookOptions(book),
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: 16,
        mainAxisSpacing: 24,
      ),
      itemCount: _filteredBooks.length,
      itemBuilder: (context, index) {
        final book = _filteredBooks[index];
        final progress = book.totalChapters > 1 
            ? (book.lastChapter / book.totalChapters * 100).clamp(0, 100).toInt() 
            : 0;

        return GestureDetector(
          onTap: () => _openBook(book),
          onLongPress: () => _showBookOptions(book),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: _buildBookCover(book, width: double.infinity, height: double.infinity, borderRadius: 12),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8, bottom: 6, right: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: book.totalChapters > 1 ? book.lastChapter / book.totalChapters : 0,
                                    backgroundColor: Colors.white.withOpacity(0.3),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
                                    minHeight: 3,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$progress%',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13, 
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBookCover(BookEntry book, {required double width, required double height, double borderRadius = 4}) {
    Widget fallback = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Text(
          book.title.isNotEmpty ? book.title[0].toUpperCase() : '?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
            fontSize: width > 50 ? 24 : 16,
          ),
        ),
      ),
    );

    if (book.coverPath != null && File(book.coverPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.file(
          File(book.coverPath!),
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      );
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: _isWriterMode ? _buildWriterNav(isDark) : _buildReaderNav(isDark),
      floatingActionButton: _isWriterMode ? null : FloatingActionButton(
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

  Widget _buildReaderNav(bool isDark) {
    return BottomNavigationBar(
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
    );
  }

  Widget _buildWriterNav(bool isDark) {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) => _onNavTap(index),
      type: BottomNavigationBarType.fixed,
      backgroundColor: isDark ? Colors.teal[900] : Colors.teal[50],
      selectedItemColor: isDark ? Colors.teal[300] : Colors.teal,
      unselectedItemColor: isDark ? Colors.grey[500] : Colors.grey[600],
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.folder_outlined),
          activeIcon: Icon(Icons.folder),
          label: 'Projects',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.lightbulb_outline),
          activeIcon: Icon(Icons.lightbulb),
          label: 'IdeaBox',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.analytics_outlined),
          activeIcon: Icon(Icons.analytics),
          label: 'Stats',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.menu_book_outlined),
          activeIcon: Icon(Icons.menu_book),
          label: 'Reader',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isWriterMode) {
      switch (_currentIndex) {
        case 0:
          return _buildWriterProjects();
        case 1:
          return _buildWriterIdeaBox();
        case 2:
          return _buildWriterStats();
        case 3:
          return ReaderPortalScreen(onGoToLibrary: () {
            setState(() => _isWriterMode = false);
          });
        case 4:
          return _buildWriterSettings();
        default:
          return _buildWriterProjects();
      }
    }
    switch (_currentIndex) {
      case 0:
        return _buildLibrary();
      case 2:
        return const StatsScreen();
      case 4:
        return const SettingsScreen();
      default:
        return _buildLibrary();
    }
  }

  Widget _buildWriterProjects() {
    return const WriterProjectsScreen();
  }

  Widget _buildWriterIdeaBox() {
    return const IdeaBoxScreen();
  }

  Widget _buildWriterStats() {
    return const WriterStatsScreen();
  }

  Widget _buildWriterSettings() {
    return const WriterSettingsScreen();
  }

  void _onNavTap(int index) {
    if (_isWriterMode) {
      if (index == 3) {
        setState(() => _isWriterMode = false);
        return;
      }
      setState(() => _currentIndex = index);
      return;
    }
    if (index == 1) {
      _continueReading();
      return;
    }
    if (index == 3) {
      setState(() {
        _isWriterMode = true;
        _currentIndex = 0;
      });
      return;
    }
    setState(() => _currentIndex = index);
  }
}

class _BookOptionsSheet extends StatelessWidget {
  final BookEntry book;
  final List<String> globalCustomLabels;
  final Function(BookmarkType) onBookmarkToggle;
  final Function(String) onCustomLabelAdd;
  final Function(String) onCustomLabelRemove;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _BookOptionsSheet({
    required this.book,
    required this.globalCustomLabels,
    required this.onBookmarkToggle,
    required this.onCustomLabelAdd,
    required this.onCustomLabelRemove,
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
          const Text('Custom Labels:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...book.customLabels.map((label) => Chip(
                    label: Text(label),
                    backgroundColor: Colors.purple.withOpacity(0.2),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => onCustomLabelRemove(label),
                  )),
            ],
          ),
          const SizedBox(height: 8),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: const Text('Add Label'),
            onPressed: () => _showAddLabelDialog(context),
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

  void _showAddLabelDialog(BuildContext ctx) {
    final controller = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Add Custom Label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter label name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                onCustomLabelAdd(name);
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Add'),
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