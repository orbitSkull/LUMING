import 'dart:io';
import 'package:flutter/material.dart';
import 'package:epub_pro/epub_pro.dart';
import 'package:flutter_html/flutter_html.dart';

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

  @override
  void initState() {
    super.initState();
    _loadBook();
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_book?.title ?? 'Reading'),
        actions: [
          if (_chapters.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.list),
              onPressed: () => _showChapterList(context),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
            ],
          ),
        ),
      );
    }

    if (_chapters.isEmpty || _currentChapterIndex >= _chapters.length) {
      return const Center(child: Text('No content found'));
    }

    final chapter = _chapters[_currentChapterIndex];
    final content = chapter.htmlContent;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Html(
        data: content,
        style: {
          'body': Style(
            fontSize: FontSize(16),
            lineHeight: const LineHeight(1.6),
          ),
          'p': Style(
            margin: Margins.only(bottom: 12),
          ),
        },
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