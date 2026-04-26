import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class EpisodeProject {
  final String id;
  final String title;
  final String? epubPath;
  final String? coverPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProjectBookmark> bookmarks;

  EpisodeProject({
    required this.id,
    required this.title,
    this.epubPath,
    this.coverPath,
    required this.createdAt,
    required this.updatedAt,
    this.bookmarks = const [ProjectBookmark.all],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'epubPath': epubPath,
    'coverPath': coverPath,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'bookmarks': bookmarks.map((b) => b.name).toList(),
  };

  factory EpisodeProject.fromJson(Map<String, dynamic> json) => EpisodeProject(
    id: json['id'],
    title: json['title'],
    epubPath: json['epubPath'],
    coverPath: json['coverPath'],
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
    bookmarks: (json['bookmarks'] as List?)?.map((b) => ProjectBookmark.values.firstWhere(
      (e) => e.name == b,
      orElse: () => ProjectBookmark.all,
    )).toList() ?? [ProjectBookmark.all],
  );
}

enum ProjectBookmark {
  all,
  recent,
  favourite,
}

class ChapterData {
  final String id;
  final String title;
  final String content;
  final int order;

  ChapterData({
    required this.id,
    required this.title,
    required this.content,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'order': order,
  };

  factory ChapterData.fromJson(Map<String, dynamic> json) => ChapterData(
    id: json['id'],
    title: json['title'],
    content: json['content'] ?? '',
    order: json['order'] ?? 0,
  );
}

class EpubProjectService {
  String _getEpubName(String title, String id) {
    final sanitized = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$sanitized-$id.epub';
  }

  String _getJsonName(String title, String id) {
    final sanitized = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$sanitized-$id.json';
  }

  Future<String> createEmptyEpub(String title, String id, String folderPath) async {
    final epubFileName = _getEpubName(title, id);
    final epubPath = '$folderPath/$epubFileName';
    
    final archive = Archive();
    
    // mimetype (must be first, uncompressed)
    archive.addFile(ArchiveFile('mimetype', 20, Uint8List.fromList('application/epub+zip'.codeUnits)));
    
    // META-INF/container.xml
    final containerXml = '<?xml version="1.0" encoding="UTF-8"?>\n<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n  <rootfiles>\n    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>\n  </rootfiles>\n</container>';
    archive.addFile(ArchiveFile('META-INF/container.xml', containerXml.length, Uint8List.fromList(containerXml.codeUnits)));
    
    // OEBPS/toc.ncx
    final tocNcx = '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">\n<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n  <head>\n    <meta name="dtb:uid" content="urn:uuid:${DateTime.now().millisecondsSinceEpoch}"/>\n    <meta name="dtb:depth" content="1"/>\n    <meta name="dtb:totalPageCount" content="0"/>\n    <meta name="dtb:maxPageNumber" content="0"/>\n  </head>\n  <docTitle>\n    <text>$title</text>\n  </docTitle>\n  <navMap>\n    <navPoint id="navPoint-1" playOrder="1">\n      <navLabel><text>Chapter 1</text></navLabel>\n      <content src="chapter1.xhtml"/>\n    </navPoint>\n  </navMap>\n</ncx>';
    archive.addFile(ArchiveFile('OEBPS/toc.ncx', tocNcx.length, Uint8List.fromList(tocNcx.codeUnits)));
    
    // OEBPS/content.opf
    final contentOpf = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>$title</dc:title>
    <dc:creator>Anonymous</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid" opf:scheme="UUID">urn:uuid:${DateTime.now().millisecondsSinceEpoch}</dc:identifier>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="cover-image" href="cover.jpg" media-type="image/jpeg"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="chapter1"/>
  </spine>
</package>''';
    archive.addFile(ArchiveFile('OEBPS/content.opf', contentOpf.length, Uint8List.fromList(contentOpf.codeUnits)));
    
    // OEBPS/chapter1.xhtml
    final chapter1 = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter 1</title></head>
<body>
<h1>Chapter 1</h1>
<p>Start writing your story here...</p>
</body>
</html>''';
    archive.addFile(ArchiveFile('OEBPS/chapter1.xhtml', chapter1.length, Uint8List.fromList(chapter1.codeUnits)));
    
    // OEBPS/cover.jpg (placeholder - 1x1 transparent)
    final coverJpg = <int>[255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 255, 219, 0, 67, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 217, 0, 67, 0, 8, 6, 6, 7, 6, 5, 8, 7, 7, 7, 9, 9, 8, 10, 14, 17, 13, 14, 18, 17, 17, 19, 21, 21, 21, 13, 15, 19, 26, 30, 29, 31, 35, 35, 31, 34, 35, 40, 45, 40, 41, 41, 39, 48, 56, 53, 52, 52, 31, 34, 51, 60, 60, 60, 47, 52, 64, 59, 59, 52, 58, 69, 83, 68, 68, 72, 78, 76, 76, 81, 95, 90, 88, 89, 100, 104, 101, 100, 107, 115, 107, 110, 112, 113, 115, 117, 115, 118, 118, 118, 120, 122, 122, 124, 123, 125, 126, 126, 128, 128, 130, 131, 131, 133, 133, 133, 133, 135, 135, 135, 137, 137, 137, 139, 139, 139, 141, 141, 141, 141, 143, 143, 143, 143, 145, 145, 145, 145, 255, 192, 0, 17, 17, 1, 1, 1, 1, 1, 1, 255, 193, 0, 20, 16, 3, 1, 0, 2, 17, 3, 16, 2, 16, 1, 255, 196, 0, 28, 16, 0, 2, 0, 2, 2, 2, 3, 0, 0, 0, 21, 0, 2, 3, 0, 4, 5, 6, 7, 8, 9, 10, 11, 1, 0, 17, 18, 33, 49, 65, 81, 97, 113, 255, 196, 0, 99, 16, 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125, 1, 2, 3, 0, 4, 17, 5, 18, 33, 49, 65, 81, 6, 97, 7, 113, 8, 129, 9, 145, 10, 161, 11, 177, 12, 193, 13, 209, 14, 225, 15, 241, 16, 19, 17, 255, 218, 0, 12, 3, 1, 0, 2, 16, 3, 16, 0, 0, 1, 249, 248, 250, 247, 0, 32, 0, 0, 8, 254, 2, 254, 2, 3, 128, 250, 248, 8, 253, 5, 6, 9, 9, 5, 5, 250, 253, 3, 253, 3, 6, 10, 10, 6, 6, 254, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 255, 217];
    archive.addFile(ArchiveFile('OEBPS/cover.jpg', coverJpg.length, Uint8List.fromList(coverJpg)));
    
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw Exception('Failed to create EPUB');
    }
    
    final file = File(epubPath);
    await file.writeAsBytes(encoded);
    
    return epubPath;
  }

  Future<EpisodeProject?> importEpub(String epubPath, String folderPath) async {
    final file = File(epubPath);
    if (!await file.existsSync()) return null;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      String title = 'Imported';
      String? coverPath;
      final List<ChapterData> chapters = [];
      
      for (final af in archive.files) {
        if (af.name == 'OEBPS/content.opf') {
          final opfContent = String.fromCharCodes(af.content);
          final titleMatch = RegExp(r'<dc:title>([^<]+)</dc:title>').firstMatch(opfContent);
          if (titleMatch != null) {
            title = titleMatch.group(1) ?? 'Imported';
          }
        }
        
        if (af.name.startsWith('OEBPS/chapter') && af.name.endsWith('.xhtml')) {
          final htmlContent = String.fromCharCodes(af.content);
          final titleMatch = RegExp(r'<title>([^<]+)</title>').firstMatch(htmlContent);
          final title = titleMatch?.group(1) ?? 'Untitled';
          
          final bodyMatch = RegExp(r'<body>([\s\S]*)</body>', dotAll: true).firstMatch(htmlContent);
          final body = bodyMatch?.group(1) ?? '';
          
          final orderMatch = RegExp(r'chapter(\d+)\.xhtml').firstMatch(af.name);
          final order = int.tryParse(orderMatch?.group(1) ?? '0') ?? 0;
          chapters.add(ChapterData(
            id: order.toString(),
            title: title,
            content: body,
            order: order,
          ));
        }
        
        if (af.name.toLowerCase().contains('cover') && (af.name.endsWith('.jpg') || af.name.endsWith('.jpeg') || af.name.endsWith('.png'))) {
          coverPath = af.name;
        }
      }
      
      chapters.sort((a, b) => a.order.compareTo(b.order));
      
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final newTitle = '$title (Copy)';
      final newEpubPath = await createEmptyEpub(newTitle, id, folderPath);
      
      await updateEpub(newEpubPath, chapters);
      
      final projectJson = {
        'id': id,
        'title': newTitle,
        'epubPath': newEpubPath,
        'coverPath': coverPath,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'bookmarks': ['all'],
      };
      
      final jsonFileName = _getJsonName(newTitle, id);
      final jsonPath = '$folderPath/$jsonFileName';
      await File(jsonPath).writeAsString(jsonEncode(projectJson));
      
      return EpisodeProject.fromJson(projectJson);
    } catch (e) {
      debugPrint('Error importing epub: $e');
      return null;
    }
  }

  Future<EpisodeProject?> cloneProject(EpisodeProject source, String newTitle, String folderPath) async {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newEpubPath = await createEmptyEpub(newTitle, newId, folderPath);
    
    final chapters = await getChapters(source.epubPath!);
    await updateEpub(newEpubPath, chapters);
    
    final projectJson = {
      'id': newId,
      'title': newTitle,
      'epubPath': newEpubPath,
      'coverPath': source.coverPath,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'bookmarks': ['all'],
    };
    
    final jsonFileName = _getJsonName(newTitle, newId);
    final jsonPath = '$folderPath/$jsonFileName';
    await File(jsonPath).writeAsString(jsonEncode(projectJson));
    
    return EpisodeProject.fromJson(projectJson);
  }

  Future<List<ChapterData>> getChapters(String epubPath) async {
    final file = File(epubPath);
    if (!await file.existsSync()) return [];

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      final List<ChapterData> chapters = [];
      
      for (final af in archive.files) {
        if (af.name.startsWith('OEBPS/chapter') && af.name.endsWith('.xhtml')) {
          final htmlContent = String.fromCharCodes(af.content);
          final titleMatch = RegExp(r'<title>([^<]+)</title>').firstMatch(htmlContent);
          final title = titleMatch?.group(1) ?? 'Untitled';
          
          final bodyMatch = RegExp(r'<body>([\s\S]*)</body>', dotAll: true).firstMatch(htmlContent);
          final body = bodyMatch?.group(1) ?? '';
          
          final orderMatch = RegExp(r'chapter(\d+)\.xhtml').firstMatch(af.name);
          final order = int.tryParse(orderMatch?.group(1) ?? '0') ?? chapters.length + 1;
          
          chapters.add(ChapterData(
            id: order.toString(),
            title: title,
            content: body,
            order: order,
          ));
        }
      }
      
      chapters.sort((a, b) => a.order.compareTo(b.order));
      return chapters;
    } catch (e) {
      debugPrint('Error loading chapters: $e');
      return [];
    }
  }

  Future<void> saveChapters(String epubPath, List<ChapterData> chapters) async {
    await updateEpub(epubPath, chapters);
  }

  Future<void> updateEpub(String epubPath, List<ChapterData> chapters) async {
    final file = File(epubPath);
    if (!await file.existsSync()) return;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      final newArchive = Archive();
      
      // Add mimetype first
      for (final af in archive.files) {
        if (af.name == 'mimetype') {
          newArchive.addFile(af);
          break;
        }
      }
      
      // Add META-INF
      for (final af in archive.files) {
        if (af.name.startsWith('META-INF/')) {
          newArchive.addFile(af);
        }
      }
      
      // Build manifest items
      final manifestItems = <String>[];
      final spineItems = <String>[];
      
      manifestItems.add('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>');
      manifestItems.add('<item id="cover-image" href="cover.jpg" media-type="image/jpeg"/>');
      
      for (int i = 0; i < chapters.length; i++) {
        final ch = chapters[i];
        final fileName = 'chapter${i + 1}.xhtml';
        manifestItems.add('<item id="chapter${i + 1}" href="$fileName" media-type="application/xhtml+xml"/>');
        spineItems.add('<itemref idref="chapter${i + 1}"/>');
      }
      
      // Build toc.ncx
      final navPoints = StringBuffer();
      for (int i = 0; i < chapters.length; i++) {
        navPoints.write('''<navPoint id="navPoint-${i + 1}" playOrder="${i + 1}">
      <navLabel><text>${chapters[i].title}</text></navLabel>
      <content src="chapter${i + 1}.xhtml"/>
    </navPoint>\n''');
      }
      
      final tocNcx = '''<?xml version="1.0" encoding="UTF-8"?php?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:uuid:${DateTime.now().millisecondsSinceEpoch}"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>EPUB</text>
  </docTitle>
  <navMap>
${navPoints.toString()}  </navMap>
</ncx>''';
      newArchive.addFile(ArchiveFile('OEBPS/toc.ncx', tocNcx.length, Uint8List.fromList(tocNcx.codeUnits)));
      
      // Build content.opf
      final contentOpf = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>EPUB</dc:title>
    <dc:creator>Anonymous</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid" opf:scheme="UUID">urn:uuid:${DateTime.now().millisecondsSinceEpoch}</dc:identifier>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    ${manifestItems.join('\n    ')}
  </manifest>
  <spine toc="ncx">
    ${spineItems.join('\n    ')}
  </spine>
</package>''';
      newArchive.addFile(ArchiveFile('OEBPS/content.opf', contentOpf.length, Uint8List.fromList(contentOpf.codeUnits)));
      
      // Add cover
      for (final af in archive.files) {
        if (af.name == 'OEBPS/cover.jpg') {
          newArchive.addFile(af);
          break;
        }
      }
      
      // Add chapters
      for (int i = 0; i < chapters.length; i++) {
        final ch = chapters[i];
        final chapterHtml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>${ch.title}</title></head>
<body>
<h1>${ch.title}</h1>
${ch.content}
</body>
</html>''';
        newArchive.addFile(ArchiveFile('OEBPS/chapter${i + 1}.xhtml', chapterHtml.length, Uint8List.fromList(chapterHtml.codeUnits)));
      }
      
      final encoded = ZipEncoder().encode(newArchive);
      if (encoded != null) {
        await file.writeAsBytes(encoded);
      }
    } catch (e) {
      debugPrint('Error updating epub: $e');
    }
  }

  Future<String?> setCover(String epubPath, Uint8List imageBytes, String extension) async {
    final file = File(epubPath);
    if (!await file.existsSync()) return null;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      final newArchive = Archive();
      final coverName = 'OEBPS/cover.$extension';
      
      for (final af in archive.files) {
        if (!af.name.toLowerCase().contains('cover')) {
          newArchive.addFile(af);
        }
      }
      
      newArchive.addFile(ArchiveFile(coverName, imageBytes.length, imageBytes));
      
      final encoded = ZipEncoder().encode(newArchive);
      if (encoded != null) {
        await file.writeAsBytes(encoded);
        return coverName;
      }
    } catch (e) {
      debugPrint('Error setting cover: $e');
    }
    return null;
  }

  Future<void> removeCover(String epubPath) async {
    final file = File(epubPath);
    if (!await file.existsSync()) return;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      final newArchive = Archive();
      
      for (final af in archive.files) {
        if (!af.name.toLowerCase().contains('cover')) {
          newArchive.addFile(af);
        }
      }
      
      final encoded = ZipEncoder().encode(newArchive);
      if (encoded != null) {
        await file.writeAsBytes(encoded);
      }
    } catch (e) {
      debugPrint('Error removing cover: $e');
    }
  }

  Future<String?> pickCoverImage() async {
    return null;
  }
}