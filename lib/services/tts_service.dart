import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:piper_tts_plugin/piper_tts_plugin.dart';
import 'package:piper_tts_plugin/enums/piper_voice_pack.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/piper_voice.dart';

enum TtsState { idle, loading, ready, playing, paused, error }

class TtsService extends ChangeNotifier {
  final PiperTtsPlugin _tts = PiperTtsPlugin();
  final AudioPlayer _player = AudioPlayer();
  
  TtsState _state = TtsState.idle;
  String? _currentText;
  double _speechRate = 1.0;
  double _pitch = 1.0;
  
  // Legacy support for PiperVoicePack
  PiperVoicePack _selectedVoicePack = PiperVoicePack.norman;
  // New support for dynamic PiperVoice
  PiperVoice? _selectedCustomVoice;
  List<PiperVoice> _availableVoices = [];

  String? _errorMessage;
  String? _audioPath;

  List<String> _chunks = [];
  int _chunkIndex = 0;

  TtsState get state => _state;
  double get speechRate => _speechRate;
  double get pitch => _pitch;
  PiperVoicePack get selectedVoice => _selectedVoicePack;
  PiperVoice? get selectedCustomVoice => _selectedCustomVoice;
  List<PiperVoice> get availableVoices => _availableVoices;
  
  bool get isPlaying => _state == TtsState.playing;
  bool get isPaused => _state == TtsState.paused;
  String? get errorMessage => _errorMessage;
  AudioPlayer get player => _player;
  int get currentChunkIndex => _chunkIndex;
  int get totalChunks => _chunks.length;
  String? get currentChunkText => _chunks.isNotEmpty && _chunkIndex < _chunks.length ? _chunks[_chunkIndex] : null;

  TtsService() {
    _loadSettings();
    _initPlayer();
    fetchVoices();
  }

  void _initPlayer() {
    _player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _onPlaybackCompleted();
      }
    });
  }

  Future<void> _onPlaybackCompleted() async {
    if (_chunkIndex < _chunks.length - 1) {
      _chunkIndex++;
      await _synthesizeAndPlayChunk(_chunkIndex);
    } else {
      _state = TtsState.ready;
      _chunks = [];
      _chunkIndex = 0;
      notifyListeners();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _speechRate = prefs.getDouble('defaultSpeechRate') ?? 1.0;
    _pitch = prefs.getDouble('defaultPitch') ?? 1.0;
    
    final customVoiceKey = prefs.getString('selectedCustomVoiceKey');
    if (customVoiceKey != null) {
      // We will need to find the voice in availableVoices once fetched
      // For now we just keep the key to find it later
    }

    final voiceIndex = prefs.getInt('selectedVoice') ?? PiperVoicePack.norman.index;
    _selectedVoicePack = PiperVoicePack.values[voiceIndex.clamp(0, PiperVoicePack.values.length - 1)];
  }

  bool _isFetchingVoices = false;
  bool get isFetchingVoices => _isFetchingVoices;

  Future<void> fetchVoices() async {
    if (_isFetchingVoices) return;
    _isFetchingVoices = true;
    notifyListeners();
    
    try {
      final response = await http.get(Uri.parse('https://huggingface.co/rhasspy/piper-voices/raw/main/voices.json'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<PiperVoice> voices = [];
        data.forEach((key, value) {
          voices.add(PiperVoice.fromJson(key, value));
        });
        // Sort voices by key
        voices.sort((a, b) => a.key.compareTo(b.key));
        _availableVoices = voices;
        
        final prefs = await SharedPreferences.getInstance();
        final customVoiceKey = prefs.getString('selectedCustomVoiceKey');
        if (customVoiceKey != null) {
          try {
            _selectedCustomVoice = _availableVoices.firstWhere(
              (v) => v.key == customVoiceKey,
            );
          } catch (_) {
            _selectedCustomVoice = _availableVoices.isNotEmpty ? _availableVoices.first : null;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching voices: $e');
    } finally {
      _isFetchingVoices = false;
      notifyListeners();
    }
  }

  Future<void> setCustomVoice(PiperVoice voice) async {
    _selectedCustomVoice = voice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedCustomVoiceKey', voice.key);
    _state = TtsState.idle;
    notifyListeners();
    await initialize();
  }

  void setSpeechRate(double rate) {
    _speechRate = rate.clamp(0.5, 2.0);
    _player.setSpeed(_speechRate);
    notifyListeners();
  }

  void setPitch(double pitch) {
    _pitch = pitch.clamp(0.5, 2.0);
    _player.setPitch(_pitch);
    notifyListeners();
  }

  Future<void> setVoice(PiperVoicePack voice) async {
    _selectedVoicePack = voice;
    _selectedCustomVoice = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedCustomVoiceKey');
    _state = TtsState.idle;
    notifyListeners();
    await initialize();
  }

  Future<void> initialize() async {
    if (_state == TtsState.loading || _state == TtsState.ready) return;
    
    _state = TtsState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_selectedCustomVoice != null) {
        final modelPath = prefs.getString(_selectedCustomVoice!.modelPrefKey);
        final configPath = prefs.getString(_selectedCustomVoice!.configPrefKey);
        
        if (modelPath != null && configPath != null && File(modelPath).existsSync() && File(configPath).existsSync()) {
          await _tts.loadViaPath(modelPath: modelPath, configPath: configPath);
          _state = TtsState.ready;
        } else {
          throw Exception('Voice model not downloaded');
        }
      } else {
        await _tts.loadViaVoicePack(_selectedVoicePack);
        _state = TtsState.ready;
      }
    } catch (e) {
      _errorMessage = 'Voice model not loaded. Go to Settings > TTS to download a voice model first.';
      _state = TtsState.error;
    }
    notifyListeners();
  }

  Future<void> downloadCustomVoice(PiperVoice voice, Function(double) onProgress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uuidGen = const Uuid();
      final uniqueId = uuidGen.v4().replaceAll("-", "_");

      final modelPath = await _downloadWithProgress(
        voice.modelUrl, 
        "${voice.key}_${uniqueId}_model.onnx",
        (p) => onProgress(p * 0.8)
      );

      final configPath = await _downloadWithProgress(
        voice.configUrl, 
        "${voice.key}_${uniqueId}_config.json",
        (p) => onProgress(0.8 + p * 0.2)
      );

      await prefs.setString(voice.modelPrefKey, modelPath);
      await prefs.setString(voice.configPrefKey, configPath);
      
      await _tts.loadViaPath(modelPath: modelPath, configPath: configPath);
      _state = TtsState.ready;
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> downloadVoice(PiperVoicePack pack, Function(double) onProgress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uuidGen = const Uuid();
      final uniqueId = uuidGen.v4().replaceAll("-", "_");

      final modelPath = await _downloadWithProgress(
        pack.modelUrl, 
        "${pack.name}_piper_voice_model_${uniqueId}_model.onnx",
        (p) => onProgress(p * 0.8) // Model is usually bigger, 80% of total
      );

      final jsonPath = await _downloadWithProgress(
        pack.jsonUrl, 
        "${pack.name}_piper_voice_model_${uniqueId}_config.json",
        (p) => onProgress(0.8 + p * 0.2) // Json is 20%
      );

      await prefs.setString(pack.modelPrefKey, modelPath);
      await prefs.setString(pack.jsonPrefKey, jsonPath);
      
      // Load it immediately after download
      await _tts.loadViaVoicePack(pack);
      _state = TtsState.ready;
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<String> _downloadWithProgress(String url, String fileName, Function(double) onProgress) async {
    final dir = await getApplicationSupportDirectory();
    final file = File("${dir.path.replaceAll("\\", "/")}/$fileName");

    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);

    final contentLength = response.contentLength ?? 0;
    int downloaded = 0;

    final bytes = <int>[];
    await for (var chunk in response.stream) {
      bytes.addAll(chunk);
      downloaded += chunk.length;
      if (contentLength > 0) {
        onProgress(downloaded / contentLength);
      }
    }

    await file.writeAsBytes(bytes);
    return file.path;
  }

  List<String> _splitIntoChunks(String text) {
    // Regex to split by sentences while keeping punctuation
    // We want to split at . ! or ? followed by space or end of string.
    final RegExp sentenceSplitter = RegExp(r'(?<=[.!?])\s+');
    final List<String> rawSentences = text.split(sentenceSplitter);
    
    final List<String> chunks = [];
    String currentChunk = "";
    
    for (var sentence in rawSentences) {
      sentence = sentence.trim();
      if (sentence.isEmpty) continue;

      // If a single sentence is already very long (> 500 chars), 
      // we must split it to avoid Piper crash, but try to do it at word boundaries.
      if (sentence.length > 500) {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk.trim());
          currentChunk = "";
        }
        
        // Split long sentence into smaller pieces
        List<String> words = sentence.split(' ');
        String temp = "";
        for (var word in words) {
          if (temp.length + word.length > 450) {
            chunks.add(temp.trim());
            temp = word;
          } else {
            temp = temp.isEmpty ? word : "$temp $word";
          }
        }
        if (temp.isNotEmpty) currentChunk = temp;
      } else if (currentChunk.isNotEmpty && currentChunk.length + sentence.length > 500) {
        chunks.add(currentChunk.trim());
        currentChunk = sentence;
      } else {
        currentChunk = currentChunk.isEmpty ? sentence : "$currentChunk $sentence";
      }
    }
    
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.trim());
    }
    
    return chunks;
  }

  Future<void> _synthesizeAndPlayChunk(int index) async {
    if (index >= _chunks.length) {
      _state = TtsState.ready;
      notifyListeners();
      return;
    }

    try {
      _chunkIndex = index;
      _state = TtsState.loading;
      notifyListeners();

      final text = _chunks[index];
      final tempDir = await getTemporaryDirectory();
      
      final outputPath = '${tempDir.path}/piper_part_${DateTime.now().millisecondsSinceEpoch}.wav';
      
      await _tts.synthesizeToFile(
        text: text,
        outputPath: outputPath,
      );
      
      _audioPath = outputPath;
      await _player.setFilePath(outputPath);
      _player.play(); // Start playback but state is set below after UI can react
      
      _state = TtsState.playing;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Synthesis error: $e';
      _state = TtsState.error;
      notifyListeners();
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    try {
      if (_state == TtsState.paused) {
        await _player.play();
        _state = TtsState.playing;
        notifyListeners();
        return;
      }

      _state = TtsState.loading;
      notifyListeners();

      await initialize();

      if (_state == TtsState.ready || _state == TtsState.error) {
        _currentText = text;
        _chunks = _splitIntoChunks(text);
        _chunkIndex = 0;
        
        if (_chunks.isNotEmpty) {
          // Listen for player state to trigger next chunk
          _player.playerStateStream.listen((state) {
            if (state.processingState == ProcessingState.completed && _state == TtsState.playing) {
              _synthesizeAndPlayChunk(_chunkIndex + 1);
            }
          }, cancelOnError: false);

          await _synthesizeAndPlayChunk(0);
        }
      }
    } catch (e) {
      _errorMessage = e.toString();
      _state = TtsState.error;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (_state == TtsState.playing) {
      await _player.pause();
      _state = TtsState.paused;
      notifyListeners();
    }
  }

  Future<void> resume() async {
    if (_state == TtsState.paused) {
      await _player.play();
      _state = TtsState.playing;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _chunks = [];
    _chunkIndex = 0;
    await _player.stop();
    _state = TtsState.ready;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}