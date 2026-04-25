import 'dart:io';
import 'package:flutter/material.dart';
import 'package:epub_pro/epub_pro.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import '../providers/reader_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ReaderScreen extends StatefulWidget {
  final String filePath;

  const ReaderScreen({super.key, required this.filePath});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  EpubBook? _book;
  List<EpubChapter> _chapters = [];
  int _currentChapterIndex = 0;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadBook();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBook() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final file = File(widget.filePath);
      final bytes = await file.readAsBytes();

      final book = await EpubReader.readBook(bytes);

      final chapters = _extractChapters(book);

      await _addToLibrary(widget.filePath, book.title ?? 'Untitled');

      if (mounted) {
        _showBookAddedToast();
      }

      setState(() {
        _book = book;
        _chapters = chapters;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<EpubChapter> _extractChapters(EpubBook book) {
    final chapters = <EpubChapter>[];

    if (book.chapters != null) {
      for (final chapter in book.chapters!) {
        chapters.add(chapter);
        if (chapter.subChapters != null) {
          chapters.addAll(_extractSubChapters(chapter.subChapters!));
        }
      }
    }

    return chapters;
  }

  List<EpubChapter> _extractSubChapters(List<EpubChapter> subChapters) {
    final chapters = <EpubChapter>[];
    for (final chapter in subChapters) {
      chapters.add(chapter);
      if (chapter.subChapters != null) {
        chapters.addAll(_extractSubChapters(chapter.subChapters!));
      }
    }
    return chapters;
  }

  void _goToChapter(int index) {
    if (index >= 0 && index < _chapters.length) {
      setState(() {
        _currentChapterIndex = index;
      });
      _scrollController.jumpTo(0);
    }
  }

  void _nextChapter() {
    if (_currentChapterIndex < _chapters.length - 1) {
      _goToChapter(_currentChapterIndex + 1);
    }
  }

  void _previousChapter() {
    if (_currentChapterIndex > 0) {
      _goToChapter(_currentChapterIndex - 1);
    }
  }

  Future<void> _addToLibrary(String filePath, String title) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('library');
      List<Map<String, dynamic>> books = [];
      
      if (data != null) {
        books = List<Map<String, dynamic>>.from(
          (jsonDecode(data) as List).map((e) => Map<String, dynamic>.from(e))
        );
      }

      final exists = books.any((b) => b['filePath'] == filePath);
      if (!exists) {
        books.add({
          'filePath': filePath,
          'title': title,
          'bookmarks': ['all'],
          'addedAt': DateTime.now().toIso8601String(),
          'lastChapter': 0,
        });
        await prefs.setString('library', jsonEncode(books));
      }
    } catch (_) {}
  }

  void _showBookAddedToast() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added to Library'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettings>();
    final isDark = settings.darkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(_book?.title ?? 'Reading'),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_fields),
            onPressed: () => _showSettingsSheet(context),
            tooltip: 'Text Settings',
          ),
          if (_chapters.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.list),
              onPressed: () => _showChapterList(context),
              tooltip: 'Chapters',
            ),
        ],
      ),
      body: _buildBody(settings, isDark),
      bottomNavigationBar: _buildNavigationBar(),
    );
  }

  Widget _buildBody(ReaderSettings settings, bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error loading book',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadBook,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_chapters.isEmpty || _currentChapterIndex >= _chapters.length) {
      return const Center(child: Text('No content found'));
    }

    final chapter = _chapters[_currentChapterIndex];
    final content = chapter.htmlContent ?? '<p>No content available</p>';

    final backgroundColor = isDark ? Colors.grey[900] : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      color: backgroundColor,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Html(
          data: content,
          style: {
            'body': Style(
              fontSize: FontSize(settings.fontSize),
              lineHeight: LineHeight(settings.lineHeight),
              color: textColor,
              backgroundColor: backgroundColor,
              fontFamily: settings.fontFamily,
              margin: Margins.zero,
              padding: HtmlPaddings.zero,
            ),
            'p': Style(
              margin: Margins.only(bottom: 16),
              fontSize: FontSize(settings.fontSize),
              lineHeight: LineHeight(settings.lineHeight),
            ),
            'h1': Style(
              fontSize: FontSize(settings.fontSize * 1.8),
              fontWeight: FontWeight.bold,
              margin: Margins.only(top: 24, bottom: 16),
            ),
            'h2': Style(
              fontSize: FontSize(settings.fontSize * 1.5),
              fontWeight: FontWeight.bold,
              margin: Margins.only(top: 20, bottom: 12),
            ),
            'h3': Style(
              fontSize: FontSize(settings.fontSize * 1.3),
              fontWeight: FontWeight.bold,
              margin: Margins.only(top: 16, bottom: 10),
            ),
            'div': Style(
              fontSize: FontSize(settings.fontSize),
              lineHeight: LineHeight(settings.lineHeight),
            ),
            'span': Style(
              fontSize: FontSize(settings.fontSize),
            ),
          },
        ),
      ),
    );
  }

  Widget? _buildNavigationBar() {
    if (_chapters.isEmpty) return null;

    final canGoBack = _currentChapterIndex > 0;
    final canGoForward = _currentChapterIndex < _chapters.length - 1;

    return Container(
      color: Colors.grey[100],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: canGoBack ? _previousChapter : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous'),
              ),
              Text(
                '${_currentChapterIndex + 1} / ${_chapters.length}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              TextButton.icon(
                onPressed: canGoForward ? _nextChapter : null,
                icon: const Text('Next'),
                label: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    final settings = context.read<ReaderSettings>();

    showModalBottomSheet(
      context: context,
      builder: (context) => Consumer<ReaderSettings>(
        builder: (context, settings, _) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Reading Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('Font Size:'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: settings.decreaseFontSize,
                  ),
                  Text('${settings.fontSize.toInt()}'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: settings.increaseFontSize,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Line Height:'),
                  const Spacer(),
                  SizedBox(
                    width: 200,
                    child: Slider(
                      value: settings.lineHeight,
                      min: 1.2,
                      max: 2.0,
                      divisions: 8,
                      label: settings.lineHeight.toStringAsFixed(1),
                      onChanged: settings.setLineHeight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Dark Mode'),
                value: settings.darkMode,
                onChanged: (_) => settings.toggleDarkMode(),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              const Text('Font Family:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Serif'),
                    selected: settings.fontFamily == 'Serif',
                    onSelected: (_) => settings.setFontFamily('Serif'),
                  ),
                  ChoiceChip(
                    label: const Text('Sans'),
                    selected: settings.fontFamily == 'Sans',
                    onSelected: (_) => settings.setFontFamily('Sans'),
                  ),
                  ChoiceChip(
                    label: const Text('Mono'),
                    selected: settings.fontFamily == 'Mono',
                    onSelected: (_) => settings.setFontFamily('Mono'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChapterList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Chapters',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final chapter = _chapters[index];
                  final isSelected = index == _currentChapterIndex;
                  return ListTile(
                    title: Text(
                      chapter.title ?? 'Chapter ${index + 1}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: isSelected,
                    onTap: () {
                      _goToChapter(index);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}