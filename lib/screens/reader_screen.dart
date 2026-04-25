import 'dart:io';
import 'package:flutter/material.dart';
import 'package:epub_pro/epub_pro.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import '../providers/reader_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/tts_service.dart';
import '../models/piper_voice.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

class ReaderScreen extends StatefulWidget {
  final String filePath;
  final int startChapter;

  const ReaderScreen({
    super.key,
    required this.filePath,
    this.startChapter = 0,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  EpubBook? _book;
  List<EpubChapter> _chapters = [];
  int _currentChapterIndex = 0;
  bool _isLoading = true;
  bool _isSpeaking = false;
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
    }
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastOpenedPath', widget.filePath);
      await prefs.setInt('lastChapterIndex', _currentChapterIndex);
      await prefs.setInt('chapter_${widget.filePath}', _currentChapterIndex);
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

    // Filter out empty chapters that might just be containers
    return chapters.where((c) => (c.htmlContent ?? '').trim().isNotEmpty).toList();
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
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: _showUI 
        ? AppBar(
            title: Text(_book?.title ?? 'Reading'),
            backgroundColor: isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.7),
            elevation: 0,
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
          )
        : null,
      body: _buildBody(settings, isDark),
      bottomNavigationBar: _showUI ? _buildNavigationBar() : null,
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

    return Consumer<TtsService>(
      builder: (context, tts, _) {
        final currentText = tts.currentChunkText;
        
        String displayContent = content;
        if (tts.isPlaying && currentText != null) {
          try {
            final highlightColor = isDark ? 'rgba(255, 255, 0, 0.3)' : 'rgba(255, 255, 0, 0.5)';
            // We use a more flexible regex that ignores differences in whitespace and newlines
            // but still targets the exact chunk text.
            final escapedText = RegExp.escape(currentText)
                .replaceAll(r'\ ', r'\s+'); // Allow any whitespace/newline variation
            
            final regex = RegExp(escapedText, multiLine: true);
            
            if (regex.hasMatch(displayContent)) {
               displayContent = displayContent.replaceFirstMapped(
                regex, 
                (match) => '<readinghighlight id="current-reading-chunk" style="background-color: $highlightColor; border-radius: 4px; padding: 2px 0;">${match.group(0)}</readinghighlight>'
              );
            } else {
              // Fallback: If exact match fails due to HTML tags inside a sentence, 
              // we try to find it by splitting into words, but for now we'll log it.
              debugPrint('TTS Highlighting: Could not find match for chunk: ${currentText.substring(0, 15)}...');
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

    return Container(
      color: isDark ? Colors.grey[900] : Colors.grey[100],
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTtsButton(),
                  TextButton.icon(
                    onPressed: canGoForward ? _nextChapter : null,
                    icon: const Text('Next'),
                    label: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTtsFooter(bool isDark) {
    final tts = Provider.of<TtsService>(context, listen: false);
    return Container(
      color: isDark ? Colors.blueGrey[900] : Colors.blue[50],
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.first_page),
                  onPressed: () => tts.previousParagraph(),
                  tooltip: 'Prev Paragraph',
                ),
                IconButton(
                  icon: const Icon(Icons.navigate_before),
                  onPressed: () => tts.previousSentence(),
                  tooltip: 'Prev Sentence',
                ),
                FloatingActionButton.small(
                  onPressed: () {
                    if (tts.state == TtsState.playing) {
                      tts.pause();
                    } else {
                      tts.resume();
                    }
                  },
                  child: Icon(tts.state == TtsState.playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  icon: const Icon(Icons.navigate_next),
                  onPressed: () => tts.nextSentence(),
                  tooltip: 'Next Sentence',
                ),
                IconButton(
                  icon: const Icon(Icons.last_page),
                  onPressed: () => tts.nextParagraph(),
                  tooltip: 'Next Paragraph',
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

  void _speakCurrentChapter(TtsService tts) {
    if (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length) {
      final chapter = _chapters[_currentChapterIndex];
      final content = chapter.htmlContent ?? '';
      final plainText = _stripHtml(content);
      if (plainText.isNotEmpty) {
        setState(() => _isSpeaking = true);
        tts.player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            if (mounted) setState(() => _isSpeaking = false);
          }
        });
        tts.speak(plainText);
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

  void _showTtsPlaybackControls(BuildContext context, TtsService tts) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Consumer<TtsService>(
        builder: (context, tts, _) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Playback Controls',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Chunk ${tts.currentChunkIndex + 1} of ${tts.totalChunks}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.first_page),
                    onPressed: () => tts.previousParagraph(),
                    tooltip: 'Previous Paragraph',
                  ),
                  IconButton(
                    icon: const Icon(Icons.navigate_before),
                    onPressed: () => tts.previousSentence(),
                    tooltip: 'Previous Sentence',
                  ),
                  FloatingActionButton(
                    onPressed: () {
                      if (tts.state == TtsState.playing) {
                        tts.pause();
                      } else {
                        tts.resume();
                      }
                    },
                    child: Icon(tts.state == TtsState.playing ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    icon: const Icon(Icons.navigate_next),
                    onPressed: () => tts.nextSentence(),
                    tooltip: 'Next Sentence',
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page),
                    onPressed: () => tts.nextParagraph(),
                    tooltip: 'Next Paragraph',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      tts.stop();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop TTS'),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showTtsQuickSettings(context, tts);
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTtsQuickSettings(BuildContext context, TtsService tts) async {
    final prefs = await SharedPreferences.getInstance();
    final List<PiperVoice> downloadedVoices = [];
    
    for (var voice in tts.availableVoices) {
      final modelPath = prefs.getString(voice.modelPrefKey);
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