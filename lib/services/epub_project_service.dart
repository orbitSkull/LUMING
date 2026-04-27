import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/episode_project.dart';
import '../models/bookmark_type.dart';

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
    content: json['content'],
    order: json['order'],
  );
}

class EpubProjectService {
  static final EpubProjectService _instance = EpubProjectService._internal();
  factory EpubProjectService() => _instance;
  EpubProjectService._internal();

  String getJsonName(String id, String title) {
    final sanitized = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$sanitized-$id.json';
  }

  Future<String> createEmptyEpub(String title, String id, String folderPath) async {
    final sanitizedTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final epubPath = '$folderPath/$sanitizedTitle-$id.epub';
    
    // Ensure the folder exists
    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    
    final archive = Archive();
    
    // mimetype
    final mimetype = 'application/epub+zip';
    archive.addFile(ArchiveFile('mimetype', mimetype.length, Uint8List.fromList(mimetype.codeUnits)));
    
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
</body>
</html>''';
    archive.addFile(ArchiveFile('OEBPS/chapter1.xhtml', chapter1.length, Uint8List.fromList(chapter1.codeUnits)));
    
    // OEBPS/cover.jpg (placeholder - 1x1 transparent)
    final coverJpg = <int>[255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 255, 219, 0, 67, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 217, 0, 67, 0, 8, 6, 6, 7, 6, 5, 8, 7, 7, 7, 9, 9, 8, 10, 14, 17, 13, 14, 18, 17, 17, 19, 21, 21, 21, 13, 15, 19, 26, 30, 29, 31, 35, 35, 31, 34, 35, 40, 45, 40, 41, 41, 39, 48, 56, 53, 52, 52, 31, 34, 51, 60, 60, 60, 47, 52, 64, 59, 59, 52, 58, 69, 83, 68, 68, 72, 78, 76, 76, 81, 95, 90, 88, 89, 100, 104, 101, 100, 107, 115, 107, 110, 112, 113, 115, 117, 115, 118, 118, 118, 120, 122, 122, 124, 123, 125, 126, 126, 128, 128, 130, 131, 131, 133, 133, 133, 133, 135, 135, 135, 137, 137, 137, 139, 139, 139, 141, 141, 141, 141, 143, 143, 143, 143, 145, 145, 145, 145, 255, 192, 0, 17, 17, 1, 1, 1, 1, 1, 1, 255, 193, 0, 20, 16, 3, 1, 0, 2, 17, 3, 16, 2, 16, 1, 255, 196, 0, 28, 16, 0, 2, 0, 2, 2, 2, 3, 0, 0, 0, 21, 0, 2, 3, 0, 4, 5, 6, 7, 8, 9, 10, 11, 1, 0, 17, 18, 33, 49, 65, 81, 97, 113, 255, 196, 0, 99, 16, 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125, 1, 2, 3, 0, 4, 17, 5, 18, 33, 49, 65, 81, 6, 97, 7, 113, 8, 129, 9, 145, 10, 161, 11, 177, 12, 193, 13, 209, 14, 225, 15, 241, 16, 19, 17, 255, 218, 0, 12, 3, 1, 0, 2, 16, 3, 16, 0, 0, 1, 249, 248, 250, 247, 0, 32, 0, 0, 8, 254, 2, 254, 2, 3, 128, 250, 248, 8, 253, 5, 6, 9, 9, 5, 5, 250, 253, 3, 253, 3, 6, 10, 10, 6, 6, 254, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 253, 255, 217];
    archive.addFile(ArchiveFile('OEBPS/cover.jpg', coverJpg.length, Uint8List.fromList(coverJpg)));
    
    final encoded = ZipEncoder().encode(archive);
    
    final file = File(epubPath);
    await file.writeAsBytes(encoded);
    
    // Create the project JSON file in the same folder
    final projectJson = {
      'id': id,
      'title': title,
      'epubPath': epubPath,
      'coverPath': null,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'bookmarks': [BookmarkType.all.name],
    };
    
    final jsonPath = '$folderPath/${getJsonName(id, title)}';
    await File(jsonPath).writeAsString(jsonEncode(projectJson));
    
    return epubPath;
  }

  Future<EpisodeProject?> importEpub(String epubPath, String folderPath) async {
    final file = File(epubPath);
    if (!file.existsSync()) return null;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      String title = 'Imported';
      String? coverPath;
      final List<ChapterData> chapters = [];
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      
      // 1. Find the OPF file path from container.xml
      String? opfPath;
      try {
        final containerFile = archive.findFile('META-INF/container.xml');
        if (containerFile != null) {
          final containerContent = utf8.decode(containerFile.content);
          final match = RegExp(r'full-path\s*=\s*["' "'" r']([^"' "'" r']+)["' "'" r']').firstMatch(containerContent);
          opfPath = match?.group(1);
        }
      } catch (_) {}
      
      // Fallback: search for any .opf file
      opfPath ??= archive.files.where((f) => f.name.endsWith('.opf')).firstOrNull?.name;
      
      if (opfPath != null) {
        final opfFile = archive.findFile(opfPath);
        if (opfFile != null) {
          final opfContent = utf8.decode(opfFile.content);
          final opfDir = p.dirname(opfPath);
          
          // Get Title
          final titleMatch = RegExp(r'<dc:title[^>]*>([^<]+)</dc:title>', caseSensitive: false).firstMatch(opfContent);
          if (titleMatch != null) {
            title = titleMatch.group(1) ?? 'Imported';
          }
          
          // Get Cover Image
          String? coverId;
          final coverMetaMatch = RegExp(r'<meta[^>]+name\s*=\s*["' "'" r']cover["' "'" r'][^>]+content\s*=\s*["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false).firstMatch(opfContent);
          coverId = coverMetaMatch?.group(1);
          
          String? coverHref;
          if (coverId != null) {
            final itemMatch = RegExp('<item[^>]+id\\s*=\\s*["\' ]$coverId["\' ][^>]+href\\s*=\\s*["\' ]([^"\' ]+)["\' ]', caseSensitive: false).firstMatch(opfContent);
            coverHref = itemMatch?.group(1);
          }
          
          // Fallback: look for items with "cover" in ID or href
          if (coverHref == null) {
            final coverItemMatch = RegExp(r'<item[^>]+(?:id|href)\s*=\s*["' "'" r'][^"' "'" r']*cover[^"' "'" r']*["' "'" r'][^>]+href\s*=\s*["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false).firstMatch(opfContent);
            coverHref = coverItemMatch?.group(1);
          }
          
          if (coverHref != null) {
            final fullCoverPath = p.normalize(opfDir == '.' ? coverHref : '$opfDir/$coverHref').replaceAll('\\', '/');
            final coverFile = archive.findFile(fullCoverPath);
            if (coverFile != null) {
              final projectDir = Directory(folderPath);
              if (!projectDir.existsSync()) projectDir.createSync(recursive: true);
              
              final ext = p.extension(fullCoverPath).isEmpty ? '.jpg' : p.extension(fullCoverPath);
              final coverFilePath = '${projectDir.path}/cover$ext';
              await File(coverFilePath).writeAsBytes(coverFile.content);
              coverPath = coverFilePath;
            }
          }
          
          // Get Chapters from Spine
          final manifestItems = <String, String>{}; // id -> href
          final itemRegex = RegExp(r'<item\s+([^>]+)/?>', caseSensitive: false);
          final idRegex = RegExp(r'id\s*=\s*["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false);
          final hrefRegex = RegExp(r'href\s*=\s*["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false);
          
          for (final m in itemRegex.allMatches(opfContent)) {
            final attrs = m.group(1)!;
            final itemId = idRegex.firstMatch(attrs)?.group(1);
            final itemHref = hrefRegex.firstMatch(attrs)?.group(1);
            if (itemId != null && itemHref != null) {
              manifestItems[itemId] = itemHref;
            }
          }
          
          final spineMatches = RegExp(r'<itemref[^>]+idref\s*=\s*["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false).allMatches(opfContent);
          int order = 1;
          for (final m in spineMatches) {
            final idref = m.group(1);
            final href = manifestItems[idref];
            if (href != null) {
              final fullHref = p.normalize(opfDir == '.' ? href : '$opfDir/$href').replaceAll('\\', '/');
              final chapterFile = archive.findFile(fullHref);
              if (chapterFile != null) {
                final htmlContent = utf8.decode(chapterFile.content);
                
                final chTitleMatch = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(htmlContent);
                final chTitle = chTitleMatch?.group(1) ?? 'Chapter $order';
                
                final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*)</body>', dotAll: true, caseSensitive: false).firstMatch(htmlContent);
                var body = bodyMatch?.group(1) ?? htmlContent;
                
                // Basic cleanup of body content
                body = body.trim();
                
                chapters.add(ChapterData(
                  id: order.toString(),
                  title: chTitle,
                  content: body,
                  order: order,
                ));
                order++;
              }
            }
          }
        }
      }

      // If no chapters found via OPF, fallback to old method
      if (chapters.isEmpty) {
        for (final af in archive.files) {
          if (af.name.endsWith('.xhtml') || af.name.endsWith('.html')) {
             if (af.name.contains('toc') || af.name.contains('cover')) {
               continue;
             }
             final htmlContent = utf8.decode(af.content);
             final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*)</body>', dotAll: true, caseSensitive: false).firstMatch(htmlContent);
             final body = bodyMatch?.group(1) ?? htmlContent;
             chapters.add(ChapterData(
               id: chapters.length.toString(),
               title: 'Chapter ${chapters.length + 1}',
               content: body,
               order: chapters.length + 1,
             ));
          }
        }
      }
      
      final newTitle = '$title (Copy)';
      final newEpubPath = await createEmptyEpub(newTitle, id, folderPath);
      
      await updateEpub(newEpubPath, chapters);
      
      // Update the JSON file created by createEmptyEpub with cover info
      final projectJson = {
        'id': id,
        'title': newTitle,
        'epubPath': newEpubPath,
        'coverPath': coverPath,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'bookmarks': [BookmarkType.all.name],
      };
      
      final jsonPath = '$folderPath/${getJsonName(id, newTitle)}';
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
    
    // Update the JSON file created by createEmptyEpub with source's cover
    final projectJson = {
      'id': newId,
      'title': newTitle,
      'epubPath': newEpubPath,
      'coverPath': source.coverPath,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'bookmarks': [BookmarkType.all.name],
    };
    
    final jsonPath = '$folderPath/${getJsonName(newId, newTitle)}';
    await File(jsonPath).writeAsString(jsonEncode(projectJson));
    
    return EpisodeProject.fromJson(projectJson);
  }

  Future<List<ChapterData>> getChapters(String epubPath) async {
    final file = File(epubPath);
    if (!file.existsSync()) return [];

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      String? opfPath;
      try {
        final containerFile = archive.findFile('META-INF/container.xml');
        if (containerFile != null) {
          final containerContent = utf8.decode(containerFile.content);
          final match = RegExp(r'full-path\s*=\s*["' "'" r']([^"' "'" r']+)["' "'" r']').firstMatch(containerContent);
          opfPath = match?.group(1);
        }
      } catch (_) {}
      
      opfPath ??= archive.files.where((f) => f.name.endsWith('.opf')).firstOrNull?.name;
      
      if (opfPath != null) {
        final opfFile = archive.findFile(opfPath);
        if (opfFile != null) {
          final opfContent = utf8.decode(opfFile.content);
          final opfDir = p.dirname(opfPath);
          
          final manifestItems = <String, String>{};
          final itemRegex = RegExp(r'<item\s+([^>]+)/?>', caseSensitive: false);
          final idRegex = RegExp(r'id\s*=\s*["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false);
          final hrefRegex = RegExp(r'href\s*=\s*["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false);
          
          for (final m in itemRegex.allMatches(opfContent)) {
            final attrs = m.group(1)!;
            final itemId = idRegex.firstMatch(attrs)?.group(1);
            final itemHref = hrefRegex.firstMatch(attrs)?.group(1);
            if (itemId != null && itemHref != null) {
              manifestItems[itemId] = itemHref;
            }
          }
          
          final spineMatches = RegExp(r'<itemref[^>]+idref\s*=\s*["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false).allMatches(opfContent);
          final chapters = <ChapterData>[];
          int order = 1;
          for (final m in spineMatches) {
            final idref = m.group(1);
            final href = manifestItems[idref];
            if (href != null) {
              final fullHref = p.normalize(opfDir == '.' ? href : '$opfDir/$href').replaceAll('\\', '/');
              final chapterFile = archive.findFile(fullHref);
              if (chapterFile != null) {
                final htmlContent = utf8.decode(chapterFile.content);
                final chTitleMatch = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(htmlContent);
                final chTitle = chTitleMatch?.group(1) ?? 'Chapter $order';
                final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*)</body>', dotAll: true, caseSensitive: false).firstMatch(htmlContent);
                final body = bodyMatch?.group(1) ?? htmlContent;
                
                chapters.add(ChapterData(id: order.toString(), title: chTitle, content: body, order: order));
                order++;
              }
            }
          }
          if (chapters.isNotEmpty) return chapters;
        }
      }

      // Fallback
      final List<ChapterData> chapters = [];
      for (final af in archive.files) {
        if (af.name.contains('chapter') && (af.name.endsWith('.xhtml') || af.name.endsWith('.html'))) {
          final htmlContent = utf8.decode(af.content);
          final titleMatch = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(htmlContent);
          final title = titleMatch?.group(1) ?? 'Untitled';
          final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*)</body>', dotAll: true, caseSensitive: false).firstMatch(htmlContent);
          final body = bodyMatch?.group(1) ?? htmlContent;
          final orderMatch = RegExp(r'chapter(\d+)').firstMatch(af.name);
          final order = int.tryParse(orderMatch?.group(1) ?? '0') ?? chapters.length + 1;
          
          chapters.add(ChapterData(id: order.toString(), title: title, content: body, order: order));
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

  Future<void> updateEpub(String epubPath, List<ChapterData> chapters, {String? title}) async {
    final file = File(epubPath);
    if (!file.existsSync()) return;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      final newArchive = Archive();
      
      String currentTitle = title ?? 'EPUB';
      if (title == null) {
        for (final af in archive.files) {
          if (af.name.endsWith('content.opf')) {
            final opfContent = utf8.decode(af.content);
            final match = RegExp(r'<dc:title[^>]*>([^<]+)</dc:title>', caseSensitive: false).firstMatch(opfContent);
            if (match != null) currentTitle = match.group(1)!;
            break;
          }
        }
      }

      for (final af in archive.files) {
        if (af.name == 'mimetype') {
          newArchive.addFile(af);
          break;
        }
      }
      
      for (final af in archive.files) {
        if (af.name.startsWith('META-INF/')) {
          newArchive.addFile(af);
        }
      }
      
      final manifestItems = <String>[];
      final spineItems = <String>[];
      
      manifestItems.add('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>');
      
      String coverHref = 'cover.jpg';
      String coverMediaType = 'image/jpeg';
      
      for (final af in archive.files) {
        if (af.name.startsWith('OEBPS/cover.')) {
          coverHref = af.name.replaceFirst('OEBPS/', '');
          if (coverHref.endsWith('.png')) {
            coverMediaType = 'image/png';
          } else if (coverHref.endsWith('.gif')) {
            coverMediaType = 'image/gif';
          }
          break;
        }
      }
      manifestItems.add('<item id="cover-image" href="$coverHref" media-type="$coverMediaType"/>');
      
      for (int i = 0; i < chapters.length; i++) {
        final fileName = 'chapter${i + 1}.xhtml';
        manifestItems.add('<item id="chapter${i + 1}" href="$fileName" media-type="application/xhtml+xml"/>');
        spineItems.add('<itemref idref="chapter${i + 1}"/>');
      }
      
      final navPoints = StringBuffer();
      for (int i = 0; i < chapters.length; i++) {
        navPoints.write('<navPoint id="navPoint-${i + 1}" playOrder="${i + 1}">');
        navPoints.write('<navLabel><text>${chapters[i].title.replaceAll('&', '&amp;')}</text></navLabel>');
        navPoints.write('<content src="chapter${i + 1}.xhtml"/>');
        navPoints.write('</navPoint>');
      }

      final tocNcx = '<?xml version="1.0" encoding="UTF-8"?>'
          '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">'
          '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
          '<head>'
          '<meta name="dtb:uid" content="urn:uuid:${DateTime.now().millisecondsSinceEpoch}"/>'
          '<meta name="dtb:depth" content="1"/>'
          '<meta name="dtb:totalPageCount" content="0"/>'
          '<meta name="dtb:maxPageNumber" content="0"/>'
          '</head>'
          '<docTitle><text>$currentTitle</text></docTitle>'
          '<navMap>$navPoints</navMap>'
          '</ncx>';
      newArchive.addFile(ArchiveFile('OEBPS/toc.ncx', tocNcx.length, Uint8List.fromList(tocNcx.codeUnits)));

      final contentOpf = '<?xml version="1.0" encoding="UTF-8"?>'
          '<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">'
          '<dc:title>$currentTitle</dc:title>'
          '<dc:language>en</dc:language>'
          '<dc:identifier id="bookid" opf:scheme="UUID">urn:uuid:${DateTime.now().millisecondsSinceEpoch}</dc:identifier>'
          '<meta name="cover" content="cover-image"/>'
          '</metadata>'
          '<manifest>${manifestItems.join("\n")}</manifest>'
          '<spine toc="ncx">${spineItems.join("\n")}</spine>'
          '</package>';
      newArchive.addFile(ArchiveFile('OEBPS/content.opf', contentOpf.length, Uint8List.fromList(contentOpf.codeUnits)));

      for (int i = 0; i < chapters.length; i++) {
        final content = chapters[i].content;
        final xhtml = '<?xml version="1.0" encoding="UTF-8"?>'
            '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">'
            '<html xmlns="http://www.w3.org/1999/xhtml">'
            '<head><title>${chapters[i].title}</title></head>'
            '<body>$content</body>'
            '</html>';
        newArchive.addFile(ArchiveFile('OEBPS/chapter${i + 1}.xhtml', xhtml.length, Uint8List.fromList(xhtml.codeUnits)));
      }

      for (final af in archive.files) {
        if (af.name.startsWith('OEBPS/') && 
            !af.name.endsWith('.opf') && 
            !af.name.endsWith('.ncx') && 
            !af.name.contains('chapter')) {
          newArchive.addFile(af);
        }
      }

      final encoded = ZipEncoder().encode(newArchive);
      await file.writeAsBytes(encoded);
    } catch (e) {
      debugPrint('Error updating epub: $e');
    }
  }

  Future<void> setCover(String epubPath, Uint8List imageBytes, String ext) async {
    final file = File(epubPath);
    if (!file.existsSync()) return;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();
      
      final coverName = 'cover.$ext';
      
      for (final af in archive.files) {
        if (af.name == 'mimetype') newArchive.addFile(af);
      }
      
      for (final af in archive.files) {
        if (af.name.startsWith('META-INF/')) newArchive.addFile(af);
      }

      newArchive.addFile(ArchiveFile('OEBPS/$coverName', imageBytes.length, imageBytes));

      for (final af in archive.files) {
        if (af.name.startsWith('OEBPS/') && !af.name.contains('cover.')) {
          if (af.name.endsWith('content.opf')) {
            var opfContent = utf8.decode(af.content);
            final mediaType = (ext == 'png') ? 'image/png' : 'image/jpeg';
            
          if (opfContent.contains('id="cover-image"')) {
            opfContent = opfContent.replaceAll(
              RegExp(r'<item id="cover-image" href="[^"]+" media-type="[^"]+"/>'),
              '<item id="cover-image" href="$coverName" media-type="$mediaType"/>',
            );
          } else {
            opfContent = opfContent.replaceFirst(
              '<manifest>',
              '<manifest>\n    <item id="cover-image" href="$coverName" media-type="$mediaType"/>',
            );
          }
            newArchive.addFile(ArchiveFile(af.name, opfContent.length, Uint8List.fromList(opfContent.codeUnits)));
          } else {
            newArchive.addFile(af);
          }
        }
      }

      final encoded = ZipEncoder().encode(newArchive);
      await file.writeAsBytes(encoded);
    } catch (e) {
      debugPrint('Error setting cover: $e');
    }
  }

  Future<String?> pickCoverImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      return result?.files.single.path;
    } catch (e) {
      debugPrint('Error picking cover image: $e');
      return null;
    }
  }

  Future<void> removeCover(String epubPath) async {
    final file = File(epubPath);
    if (!file.existsSync()) return;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();

      for (final af in archive.files) {
        if (!af.name.contains('cover.')) {
          newArchive.addFile(af);
        }
      }

      final encoded = ZipEncoder().encode(newArchive);
      await file.writeAsBytes(encoded);
    } catch (e) {
      debugPrint('Error removing cover: $e');
    }
  }
}
