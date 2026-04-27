import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:epub_pro/epub_pro.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import '../providers/reader_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../services/storage_service.dart';
import '../services/writer_service.dart';
import '../models/book_entry.dart';
import '../models/bookmark_type.dart';
import '../models/piper_voice.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:archive/archive.dart';
class ReaderScreen extends StatefulWidget {
  final String filePath;
  final int startChapter;
  final bool isTts;
  final int startChunk;

  const ReaderScreen({
    super.key,
    required this.filePath,
    this.startChapter = 0,
    this.isTts = false,
    this.startChunk = 0,
  });

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
  
  // Use GlobalKey for the Html widget to find children if needed
  final GlobalKey _htmlKey = GlobalKey();
  final GlobalKey _highlightKey = GlobalKey();
  
  int _lastChunkIndex = -1;

  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.startChapter;
    _loadBook();
    // Setup TTS auto-next chapter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tts = Provider.of<TtsService>(context, listen: false);
      tts.onChapterFinished = () {
        if (_currentChapterIndex < _chapters.length - 1) {
          _nextChapter();
          // After changing chapter, start speaking the new chapter
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) {
              final newContent = _stripHtml(_chapters[_currentChapterIndex].htmlContent ?? '');
              Provider.of<TtsService>(context, listen: false).speak(newContent);
              _saveLastTtsPosition(0); // Reset chunk to 0 for new chapter
            }
          });
        }
      };
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Add listener to TtsService for auto-scrolling
    final tts = Provider.of<TtsService>(context);
    if (tts.isPlaying && tts.currentChunkIndex != _lastChunkIndex) {
      _lastChunkIndex = tts.currentChunkIndex;
      _scrollToHighlight();
      _saveLastTtsPosition(_lastChunkIndex);
    }
  }

  Future<void> _saveLastTtsPosition(int chunkIndex) async {
    try {
      final storage = StorageService();
      final settingsFile = File(storage.settingsFile);
      Map<String, dynamic> settings = {};
      if (settingsFile.existsSync()) {
        settings = jsonDecode(settingsFile.readAsStringSync());
      }
      settings['tts_chunk_${widget.filePath}'] = chunkIndex;
      await settingsFile.writeAsString(jsonEncode(settings));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('tts_chunk_${widget.filePath}', chunkIndex);
    } catch (_) {}
  }

  void _scrollToHighlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_highlightKey.currentContext != null) {
        Scrollable.ensureVisible(
          _highlightKey.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.3, // Scroll so it's in the top 30% of the screen
        );
      }
    });
  }

  @override
  void dispose() {
    _saveLastRead();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _saveLastRead() async {
    try {
      final storage = StorageService();
      final bookFile = File(storage.getBookEntryFile(_book?.title ?? 'Unknown'));
      
      final tts = Provider.of<TtsService>(context, listen: false);
      final wasTts = tts.state == TtsState.playing || tts.state == TtsState.paused || _lastChunkIndex > 0;

      BookEntry entry;
      if (bookFile.existsSync()) {
        final content = await bookFile.readAsString();
        entry = BookEntry.fromJson(jsonDecode(content));
        entry = entry.copyWith(
          lastChapter: _currentChapterIndex,
          totalChapters: _chapters.length,
          lastWasTts: wasTts,
          ttsLastChunk: wasTts ? _lastChunkIndex : entry.ttsLastChunk,
          ttsTotalChunks: tts.totalChunks,
        );
      } else {
        entry = BookEntry(
          filePath: widget.filePath,
          title: _book?.title ?? 'Unknown',
          bookmarks: [BookmarkType.all],
          addedAt: DateTime.now(),
          lastChapter: _currentChapterIndex,
          totalChapters: _chapters.length,
          lastWasTts: wasTts,
          ttsLastChunk: wasTts ? _lastChunkIndex : 0,
          ttsTotalChunks: tts.totalChunks,
        );
      }
      await bookFile.writeAsString(jsonEncode(entry.toJson()));

      // Save continue.json
      final continueFile = File(storage.continueFile);
      await continueFile.writeAsString(jsonEncode({
        'lastOpenedPath': widget.filePath,
        'title': _book?.title ?? 'Unknown',
        'chapterIndex': _currentChapterIndex,
        'isTts': wasTts,
        'chunkIndex': _lastChunkIndex,
      }));
    } catch (_) {}
  }

  Future<void> _loadBook() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final file = File(widget.filePath);
      final bytes = await file.readAsBytes();

      final ext = widget.filePath.split('.').last.toLowerCase();
      if (!['epub', 'mobi', 'azw3', 'fb2'].contains(ext)) {
        throw const FormatException('Unsupported file format');
      }

      final book = await EpubReader.readBook(bytes);

      String? coverPath;

      // Try to get the standard cover image from metadata
      if (book.coverImage != null && book.coverImage!.isNotEmpty) {
        try {
          debugPrint('Found cover from metadata, size: ${book.coverImage!.length}');
          coverPath = await _saveCoverImage(book.coverImage!, 'cover_metadata.jpg');
        } catch (e) {
          debugPrint('Error saving metadata cover: $e');
        }
      }

      // If no cover from metadata, extract from epub as zip and find any image
      if (coverPath == null) {
        try {
          debugPrint('Looking for cover in epub as zip...');
          final epubFile = File(widget.filePath);
          final bytes = await epubFile.readAsBytes();
          
          // Use archive package to read the epub
          final archive = ZipDecoder().decodeBytes(bytes);
          
          // Find all image files
          final validExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
          final imageFiles = archive.files.where((f) => 
            f.isFile && validExts.any((e) => f.name.toLowerCase().endsWith(e))
          ).toList();
          
          debugPrint('Found ${imageFiles.length} images in epub');
          
          // Sort by file size (largest first - likely cover)
          imageFiles.sort((a, b) => b.size.compareTo(a.size));
          
          for (final imgFile in imageFiles) {
            final name = imgFile.name.toLowerCase();
            debugPrint('Found image in epub: ${imgFile.name}, size: ${imgFile.size}');
            
            // Skip images in META-INF (usually UI elements)
            if (name.contains('meta-inf/')) continue;
            
            final content = imgFile.content;
            if (content != null && content.isNotEmpty) {
              final ext = name.split('.').last;
              coverPath = await _saveCoverImage(content, 'cover.$ext');
              debugPrint('Saved cover: $coverPath');
              break;
            }
          }
        } catch (e) {
          debugPrint('Error extracting cover from zip: $e');
        }
      }
      
      debugPrint('Cover path result: $coverPath');

      final chapters = _extractChapters(book);

      final isFirstTime = await _addToLibrary(widget.filePath, book.title ?? 'Untitled', coverPath: coverPath, totalChapters: chapters.length);

      if (mounted && isFirstTime) {
        _showBookAddedToast();
      }

      setState(() {
        _book = book;
        _chapters = chapters;
        _isLoading = false;
      });

      if (widget.isTts) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final tts = Provider.of<TtsService>(context, listen: false);
          _speakCurrentChapter(tts, startChunk: widget.startChunk);
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<String> _saveCoverImage(dynamic bytes, String originalName) async {
    final storage = StorageService();
    final libraryDir = Directory(storage.libraryPath);
    if (!libraryDir.existsSync()) libraryDir.createSync(recursive: true);
    
    final coversDir = Directory('${storage.libraryPath}/covers');
    if (!coversDir.existsSync()) coversDir.createSync(recursive: true);

    String sanitizedName;
    if (bytes is Uint8List) {
      sanitizedName = originalName.split('/').last;
    } else {
      sanitizedName = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9\.]'), '_');
    }
    final fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';
    final file = File('${coversDir.path}/$fileName');
    await file.writeAsBytes(bytes is Uint8List ? bytes : bytes as List<int>);
    return file.path;
  }

  List<EpubChapter> _extractChapters(EpubBook book) {
    final chapters = <EpubChapter>[];

    for (final chapter in book.chapters) {
      chapters.add(chapter);
      if (chapter.subChapters.isNotEmpty) {
        chapters.addAll(_extractSubChapters(chapter.subChapters));
      }
    }

    // Filter out empty chapters that might just be containers
    return chapters.where((c) => (c.htmlContent ?? '').trim().isNotEmpty).toList();
  }

  List<EpubChapter> _extractSubChapters(List<EpubChapter> subChapters) {
    final chapters = <EpubChapter>[];
    for (final chapter in subChapters) {
      chapters.add(chapter);
      if (chapter.subChapters.isNotEmpty) {
        chapters.addAll(_extractSubChapters(chapter.subChapters));
      }
    }
    return chapters;
  }

  void _goToChapter(int index) {
    if (index >= 0 && index < _chapters.length) {
      if (_currentChapterIndex != index) {
        _lastChunkIndex = -1; // Reset chunk index for new chapter
      }
      setState(() {
        _currentChapterIndex = index;
      });
      _scrollController.jumpTo(0);
    }
  }

  void _nextChapter() async {
    if (_currentChapterIndex < _chapters.length - 1) {
      _goToChapter(_currentChapterIndex + 1);
      
      try {
        final storage = StorageService();
        final now = DateTime.now();
        
        // Update Overall Stats
        final statsFile = File(storage.overallStatsFile);
        Map<String, dynamic> stats = {};
        if (statsFile.existsSync()) {
          stats = jsonDecode(statsFile.readAsStringSync());
        }
        
        int cr = stats['chaptersRead'] ?? 0;
        stats['chaptersRead'] = cr + 1;
        await statsFile.writeAsString(jsonEncode(stats));

        // Update Daily Stats
        final dailyFile = File(storage.getDailyStatsFile(now));
        Map<String, dynamic> dailyStats = {};
        if (dailyFile.existsSync()) {
          dailyStats = jsonDecode(dailyFile.readAsStringSync());
        }
        dailyStats['chaptersRead'] = (dailyStats['chaptersRead'] ?? 0) + 1;
        await dailyFile.writeAsString(jsonEncode(dailyStats));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('chaptersRead', stats['chaptersRead']);
      } catch (_) {}
    } else if (_currentChapterIndex == _chapters.length - 1) {
      try {
        final storage = StorageService();
        final statsFile = File(storage.overallStatsFile);
        Map<String, dynamic> stats = {};
        if (statsFile.existsSync()) {
          stats = jsonDecode(statsFile.readAsStringSync());
        }
        
        List<String> completed = List<String>.from(stats['completedBooksPaths'] ?? []);
        if (!completed.contains(widget.filePath)) {
          completed.add(widget.filePath);
          stats['completedBooksPaths'] = completed;
          
          int bc = stats['booksCompleted'] ?? 0;
          stats['booksCompleted'] = bc + 1;
          
          await statsFile.writeAsString(jsonEncode(stats));

          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('completedBooksPaths', completed);
          await prefs.setInt('booksCompleted', stats['booksCompleted']);
        }
      } catch (_) {}
    }
  }

  void _previousChapter() {
    if (_currentChapterIndex > 0) {
      _goToChapter(_currentChapterIndex - 1);
    }
  }

  Future<bool> _addToLibrary(String filePath, String title, {String? coverPath, int totalChapters = 0}) async {
    try {
      final storage = StorageService();
      final bookFile = File(storage.getBookEntryFile(title));
      
      if (!bookFile.existsSync()) {
        final entry = BookEntry(
          filePath: filePath,
          title: title,
          coverPath: coverPath,
          bookmarks: [BookmarkType.all],
          addedAt: DateTime.now(),
          lastChapter: 0,
          totalChapters: totalChapters,
        );
        await bookFile.writeAsString(jsonEncode(entry.toJson()));
        
        // Update stats
        final statsFile = File(storage.overallStatsFile);
        Map<String, dynamic> stats = {};
        if (statsFile.existsSync()) {
          stats = jsonDecode(await statsFile.readAsString());
        }
        stats['totalBooks'] = (stats['totalBooks'] ?? 0) + 1;
        await statsFile.writeAsString(jsonEncode(stats));
        
        return true;
      } else {
        final content = await bookFile.readAsString();
        var entry = BookEntry.fromJson(jsonDecode(content));
        bool updated = false;
        
        if (coverPath != null && (entry.coverPath == null || !File(entry.coverPath!).existsSync())) {
          entry = entry.copyWith(coverPath: coverPath);
          updated = true;
        }
        if (totalChapters > 0 && entry.totalChapters == 0) {
          entry = entry.copyWith(totalChapters: totalChapters);
          updated = true;
        }
        
        if (updated) {
          await bookFile.writeAsString(jsonEncode(entry.toJson()));
        }
      }
      return false;
    } catch (_) {
      return false;
    }
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveLastRead();
        if (context.mounted) {
          Navigator.pop(context, result);
        }
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7),
        appBar: _showUI 
          ? AppBar(
              title: Text(
                _book?.title ?? 'Reading', 
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(color: Colors.transparent),
                ),
              ),
              backgroundColor: isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.6),
              elevation: 0,
              iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
              actions: [
                IconButton(
                  icon: const Icon(Icons.text_fields_rounded),
                  onPressed: () => _showSettingsSheet(context),
                  tooltip: 'Text Settings',
                ),
                if (_chapters.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.format_list_bulleted_rounded),
                    onPressed: () => _showChapterList(context),
                    tooltip: 'Chapters',
                  ),
              ],
            )
          : null,
      body: _buildBody(settings, isDark),
      bottomNavigationBar: _showUI ? _buildNavigationBar() : null,
    ));
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

    return Consumer<TtsService>(
      builder: (context, tts, _) {
        final currentText = tts.currentChunkText;
        
        String displayContent = content;
        if (tts.isPlaying && currentText != null) {
          try {
            final highlightColor = isDark ? 'rgba(255, 255, 0, 0.3)' : 'rgba(255, 255, 0, 0.5)';
            final words = currentText.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty).toList();
            if (words.isNotEmpty) {
              final escapedWords = words.map((w) => RegExp.escape(w));
              // Allow any combination of whitespace or HTML tags between words
              final regexPattern = escapedWords.join(r'(?:\s*<[^>]+>\s*|\s+)');
              final regex = RegExp(regexPattern, multiLine: true, caseSensitive: false);
              
              if (regex.hasMatch(displayContent)) {
                 displayContent = displayContent.replaceFirstMapped(
                  regex, 
                  (match) => '<readinghighlight style="background-color: $highlightColor; border-radius: 4px;">${match.group(0)}</readinghighlight>'
                );
              } else {
                debugPrint('TTS Highlighting: Could not find match in HTML for chunk: ${currentText.substring(0, currentText.length > 20 ? 20 : currentText.length)}...');
              }
            }
          } catch (e) {
            debugPrint('TTS Highlighting Error: $e');
          }
        }

        return Stack(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _showUI = !_showUI;
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: backgroundColor,
                height: double.infinity,
                width: double.infinity,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    16, 
                    _showUI ? kToolbarHeight + 40 : 40, 
                    16, 
                    _showUI ? 100 : 40
                  ),
                  child: Html(
                    key: _htmlKey,
                    data: displayContent,
                    extensions: [
                      TagExtension(
                        tagsToExtend: {"readinghighlight"},
                        builder: (extensionContext) {
                          return Text.rich(
                            TextSpan(
                              text: extensionContext.element?.text ?? "",
                              style: extensionContext.styledElement?.style.generateTextStyle(),
                            ),
                            key: _highlightKey,
                          );
                        },
                      ),
                    ],
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
                        color: textColor,
                      ),
                      'h1': Style(
                        fontSize: FontSize(settings.fontSize * 1.8),
                        fontWeight: FontWeight.bold,
                        margin: Margins.only(top: 24, bottom: 16),
                        color: textColor,
                      ),
                      'h2': Style(
                        fontSize: FontSize(settings.fontSize * 1.5),
                        fontWeight: FontWeight.bold,
                        margin: Margins.only(top: 20, bottom: 12),
                        color: textColor,
                      ),
                      'h3': Style(
                        fontSize: FontSize(settings.fontSize * 1.3),
                        fontWeight: FontWeight.bold,
                        margin: Margins.only(top: 16, bottom: 10),
                        color: textColor,
                      ),
                      'div': Style(
                        fontSize: FontSize(settings.fontSize),
                        lineHeight: LineHeight(settings.lineHeight),
                        color: textColor,
                      ),
                      'span': Style(
                        fontSize: FontSize(settings.fontSize),
                        color: textColor,
                      ),
                      'li': Style(
                        fontSize: FontSize(settings.fontSize),
                        color: textColor,
                      ),
                    },
                  ),
                ),
              ),
            ),
            if (tts.isPlaying || tts.state == TtsState.loading)
              Positioned(
                top: _showUI ? kToolbarHeight + 10 : 30,
                left: 8,
                right: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.volume_up, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Playing: Chunk ${tts.currentChunkIndex + 1}/${tts.totalChunks}',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget? _buildNavigationBar() {
    if (_chapters.isEmpty) return null;

    final canGoBack = _currentChapterIndex > 0;
    final canGoForward = _currentChapterIndex < _chapters.length - 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tts = Provider.of<TtsService>(context);

    // If TTS is active (playing, loading or paused), show TTS specific footer
    if (tts.state == TtsState.playing || tts.state == TtsState.loading || tts.state == TtsState.paused) {
      return _buildTtsFooter(isDark);
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          color: isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.6),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: canGoBack ? _previousChapter : null,
                    icon: Icon(Icons.chevron_left, color: canGoBack ? (isDark ? Colors.white : Colors.black87) : Colors.grey),
                    label: Text('Previous', style: TextStyle(color: canGoBack ? (isDark ? Colors.white : Colors.black87) : Colors.grey)),
                  ),
                  Text(
                    '${_currentChapterIndex + 1} / ${_chapters.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTtsButton(),
                      TextButton.icon(
                        onPressed: canGoForward ? _nextChapter : null,
                        icon: Text('Next', style: TextStyle(color: canGoForward ? (isDark ? Colors.white : Colors.black87) : Colors.grey)),
                        label: Icon(Icons.chevron_right, color: canGoForward ? (isDark ? Colors.white : Colors.black87) : Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTtsFooter(bool isDark) {
    final tts = Provider.of<TtsService>(context, listen: false);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF6C63FF).withOpacity(0.15) : const Color(0xFF6C63FF).withOpacity(0.1),
            border: Border(top: BorderSide(color: const Color(0xFF6C63FF).withOpacity(0.2))),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.first_page_rounded),
                      onPressed: () => tts.previousParagraph(),
                      color: isDark ? Colors.white70 : Colors.black87,
                      tooltip: 'Prev Paragraph',
                    ),
                    IconButton(
                      icon: const Icon(Icons.navigate_before_rounded),
                      onPressed: () => tts.previousSentence(),
                      color: isDark ? Colors.white70 : Colors.black87,
                      tooltip: 'Prev Sentence',
                    ),
                    FloatingActionButton.small(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      onPressed: () {
                        if (tts.state == TtsState.playing) {
                          tts.pause();
                        } else {
                          tts.resume();
                        }
                      },
                      child: Icon(tts.state == TtsState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    ),
                    IconButton(
                      icon: const Icon(Icons.navigate_next_rounded),
                      onPressed: () => tts.nextSentence(),
                      color: isDark ? Colors.white70 : Colors.black87,
                      tooltip: 'Next Sentence',
                    ),
                    IconButton(
                      icon: const Icon(Icons.last_page_rounded),
                      onPressed: () => tts.nextParagraph(),
                      color: isDark ? Colors.white70 : Colors.black87,
                      tooltip: 'Next Paragraph',
                    ),
                GestureDetector(
                  onLongPress: () => _showTtsQuickSettings(context, tts),
                  child: IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () => _showTtsQuickSettings(context, tts),
                    tooltip: 'TTS Settings',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                  onPressed: () => tts.stop(),
                  tooltip: 'Stop',
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);
}

  Widget _buildTtsButton() {
    return Consumer<TtsService>(
      builder: (context, tts, _) {
        return GestureDetector(
          onLongPress: () => _showTtsQuickSettings(context, tts),
          child: IconButton(
            icon: const Icon(Icons.volume_up),
            onPressed: () => _speakCurrentChapter(tts),
            tooltip: 'Start Reading',
          ),
        );
      },
    );
  }

  void _speakCurrentChapter(TtsService tts, {int? startChunk}) async {
    if (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length) {
      final chapter = _chapters[_currentChapterIndex];
      final content = chapter.htmlContent ?? '';
      final plainText = _stripHtml(content);
      if (plainText.isNotEmpty) {
        final storage = StorageService();
        final settingsFile = File(storage.settingsFile);
        Map<String, dynamic> settings = {};
        if (settingsFile.existsSync()) {
          try {
            settings = jsonDecode(settingsFile.readAsStringSync());
          } catch (_) {}
        }
        
        int actualStartChunk = 0;
        if (startChunk != null) {
          actualStartChunk = startChunk;
        } else if (_lastChunkIndex >= 0) {
          actualStartChunk = _lastChunkIndex;
        } else if (_currentChapterIndex == widget.startChapter) {
          actualStartChunk = widget.startChunk;
        }
        
        if (actualStartChunk <= 0 && _currentChapterIndex == widget.startChapter) {
           final prefs = await SharedPreferences.getInstance();
           actualStartChunk = settings['tts_chunk_${widget.filePath}'] ?? prefs.getInt('tts_chunk_${widget.filePath}') ?? 0;
        }

        setState(() {});
        tts.speak(plainText, startChunkIndex: actualStartChunk);
      }
    }
  }

  String _stripHtml(String html) {
    // Remove scripts and styles
    String content = html.replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', dotAll: true), '');
    // Replace <br>, <p>, <div> tags with newlines to preserve sentence boundaries
    content = content.replaceAll(RegExp(r'<(br|p|div|li|h[1-6])[^>]*>', caseSensitive: false), '\n');
    // Strip all other HTML tags
    content = content.replaceAll(RegExp(r'<[^>]*>'), ' ');
    // Decode HTML entities (basic ones)
    content = content
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // Standardize whitespace
    return content.replaceAll(RegExp(r' +'), ' ').replaceAll(RegExp(r'\n+'), '\n').trim();
  }



  void _showTtsQuickSettings(BuildContext context, TtsService tts) async {
    final storage = StorageService();
    final settingsFile = File(storage.settingsFile);
    Map<String, dynamic> settings = {};
    if (settingsFile.existsSync()) {
      try {
        settings = jsonDecode(settingsFile.readAsStringSync());
      } catch (_) {}
    }
    
    final prefs = await SharedPreferences.getInstance();
    final List<PiperVoice> downloadedVoices = [];
    
    for (var voice in tts.availableVoices) {
      final modelPath = settings[voice.modelPrefKey] ?? prefs.getString(voice.modelPrefKey);
      if (modelPath != null && File(modelPath).existsSync()) {
        downloadedVoices.add(voice);
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TTS Quick Settings', style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Speech Rate', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: tts.speechRate,
                min: 0.1,
                max: 4.0,
                divisions: 39,
                label: '${tts.speechRate.toStringAsFixed(2)}x',
                onChanged: (val) {
                  tts.setSpeechRate(val);
                  setModalState(() {});
                },
              ),
              const Text('Pitch', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: tts.pitch,
                min: 0.1,
                max: 4.0,
                divisions: 39,
                label: tts.pitch.toStringAsFixed(2),
                onChanged: (val) {
                  tts.setPitch(val);
                  setModalState(() {});
                },
              ),
              const SizedBox(height: 16),
              const Text('Downloaded Voices', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (downloadedVoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('No other voices downloaded', style: TextStyle(color: Colors.grey, fontSize: 12)),
                )
              else
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: downloadedVoices.length,
                    itemBuilder: (context, index) {
                      final voice = downloadedVoices[index];
                      final isSelected = tts.selectedCustomVoice?.key == voice.key;
                      return ListTile(
                        title: Text(voice.name),
                        subtitle: Text(voice.key, style: const TextStyle(fontSize: 10)),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                        dense: true,
                        onTap: () {
                          tts.setCustomVoice(voice);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    // Settings are available via context.read<ReaderSettings>() in the builder

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