import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'entities/entities.dart';
import 'repositories.dart';

class BackupService {
  BackupService(this.repositories);
  final Repositories repositories;

  Future<void> exportBackup() async {
    final temp = await getTemporaryDirectory();
    final work = Directory(p.join(temp.path, 'tapat-backup-${DateTime.now().millisecondsSinceEpoch}'))..createSync();
    final manifest = <String, Object?>{
      'format': 'tapat-ai-backup-v1',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'topics': <Map<String, Object?>>[],
      'documents': <Map<String, Object?>>[],
      'chunks': <Map<String, Object?>>[],
      'chats': <Map<String, Object?>>[],
    };
    final topicsData = manifest['topics']! as List<Map<String, Object?>>;
    final documentsData = manifest['documents']! as List<Map<String, Object?>>;
    final chunksData = manifest['chunks']! as List<Map<String, Object?>>;
    final chatsData = manifest['chats']! as List<Map<String, Object?>>;
    final docEntries = <(String, File)>[];
    for (final topic in repositories.topics.getAll()) {
      topicsData.add({'uuid': topic.uuid, 'name': topic.name, 'description': topic.description,
        'category': topic.category, 'iconIndex': topic.iconIndex, 'createdAt': topic.createdAt.toIso8601String(), 'nfcId': topic.nfcId});
      for (final doc in repositories.documents.forTopic(topic.id)) {
        final archivePath = 'documents/${doc.uuid}${p.extension(doc.name)}';
        documentsData.add({'uuid': doc.uuid, 'topicUuid': topic.uuid, 'name': doc.name, 'type': doc.type,
          'sizeBytes': doc.sizeBytes, 'archivePath': archivePath, 'pageCount': doc.pageCount,
          'chunkCount': doc.chunkCount, 'status': doc.status == 'processing' ? (doc.chunkCount > 0 ? 'ready' : 'saved') : doc.status,
          'createdAt': doc.createdAt.toIso8601String(), 'contentSha256': doc.contentSha256,
          'origin': doc.origin, 'aiAssisted': doc.aiAssisted, 'updatedAt': doc.updatedAt?.toIso8601String()});
        final file = File(doc.path);
        if (file.existsSync()) docEntries.add((archivePath, file));
        for (final chunk in repositories.chunks.forDocument(doc.id)) {
          chunksData.add({'documentUuid': doc.uuid, 'topicUuid': topic.uuid, 'text': chunk.text,
            'pageNumber': chunk.pageNumber, 'chunkIndex': chunk.chunkIndex,
            'embeddingModelId': chunk.embeddingModelId, 'vector': chunk.vector});
        }
      }
      for (final chat in repositories.chats.forTopic(topic.id)) {
        chatsData.add({'topicUuid': topic.uuid, 'text': chat.text, 'isUser': chat.isUser,
          'sourcesJson': chat.sourcesJson, 'visualJson': chat.visualJson, 'createdAt': chat.createdAt.toIso8601String()});
      }
    }
    final manifestFile = File(p.join(work.path, 'backup.json'))..writeAsStringSync(jsonEncode(manifest));
    final zipPath = p.join(temp.path, 'tapat-ai-backup.zip');
    final encoder = ZipFileEncoder()..create(zipPath);
    await encoder.addFile(manifestFile, 'backup.json');
    for (final (archivePath, file) in docEntries) { await encoder.addFile(file, archivePath); }
    await encoder.close();
    final targetPath = await FilePicker.saveFile(dialogTitle: 'Export Tapat AI backup', fileName: 'tapat-ai-backup.zip', type: FileType.custom, allowedExtensions: const ['zip']);
    if (targetPath == null) return;
    if (p.normalize(targetPath) != p.normalize(zipPath)) await File(zipPath).copy(targetPath);
    await work.delete(recursive: true);
    await File(zipPath).delete();
  }

  Future<void> importBackup() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['zip'], allowMultiple: false, withData: false);
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    final manifestFile = archive.findFile('backup.json');
    if (manifestFile == null) throw const FormatException('This is not a Tapat AI backup archive.');
    final manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>;
    if (manifest['format'] != 'tapat-ai-backup-v1') throw const FormatException('This backup format is not supported.');
    final archivedDocs = (manifest['documents'] as List).cast<Map<String, dynamic>>();
    for (final value in archivedDocs) {
      if (archive.findFile(value['archivePath'] as String) == null) {
        throw FormatException('A document is missing from the backup: ${value['name']}');
      }
    }
    for (final topic in repositories.topics.getAll()) { repositories.topics.deleteCascade(topic.uuid, repositories); }
    final topicByUuid = <String, TopicEntity>{};
    for (final value in (manifest['topics'] as List).cast<Map<String, dynamic>>()) {
      final topic = TopicEntity()
        ..uuid = value['uuid'] as String
        ..name = value['name'] as String
        ..description = value['description'] as String
        ..category = value['category'] as String
        ..iconIndex = value['iconIndex'] as int
        ..createdAt = DateTime.parse(value['createdAt'] as String)
        ..nfcId = value['nfcId'] as String;
      repositories.topics.put(topic);
      topicByUuid[topic.uuid] = topic;
    }
    final documentsByUuid = <String, DocumentEntity>{};
    final documentDir = await LocalFiles.documentsDirectory();
    for (final value in archivedDocs) {
      final archived = archive.findFile(value['archivePath'] as String);
      final target = File(p.join(documentDir.path, '${const Uuid().v4()}${p.extension(value['archivePath'] as String)}'));
      await target.writeAsBytes(archived!.content as List<int>, flush: true);
      final doc = DocumentEntity()
        ..uuid = value['uuid'] as String
        ..name = value['name'] as String
        ..type = value['type'] as String
        ..sizeBytes = value['sizeBytes'] as int
        ..path = target.path
        ..pageCount = value['pageCount'] as int
        ..chunkCount = value['chunkCount'] as int
        ..status = value['status'] as String? ?? ((value['chunkCount'] as int) > 0 ? 'ready' : 'saved')
        ..createdAt = DateTime.parse(value['createdAt'] as String)
        ..contentSha256 = value['contentSha256'] as String
        ..origin = value['origin'] as String? ?? 'uploaded'
        ..aiAssisted = value['aiAssisted'] as bool? ?? false
        ..updatedAt = DateTime.tryParse(value['updatedAt'] as String? ?? '');
      doc.topic.target = topicByUuid[value['topicUuid'] as String];
      repositories.documents.put(doc);
      documentsByUuid[doc.uuid] = doc;
    }
    final chunks = <ChunkEntity>[];
    for (final value in (manifest['chunks'] as List).cast<Map<String, dynamic>>()) {
      final chunk = ChunkEntity()
        ..text = value['text'] as String
        ..pageNumber = value['pageNumber'] as int
        ..chunkIndex = value['chunkIndex'] as int
        ..embeddingModelId = value['embeddingModelId'] as String
        ..vector = (value['vector'] as List?)?.map((v) => (v as num).toDouble()).toList();
      chunk.document.target = documentsByUuid[value['documentUuid'] as String];
      chunk.topic.target = topicByUuid[value['topicUuid'] as String];
      chunks.add(chunk);
    }
    repositories.chunks.putMany(chunks);
    for (final value in (manifest['chats'] as List).cast<Map<String, dynamic>>()) {
      final chat = ChatMessageEntity()
        ..text = value['text'] as String
        ..isUser = value['isUser'] as bool
        ..sourcesJson = value['sourcesJson'] as String
        ..visualJson = value['visualJson'] as String? ?? ''
        ..createdAt = DateTime.parse(value['createdAt'] as String);
      chat.topic.target = topicByUuid[value['topicUuid'] as String];
      repositories.chats.add(chat);
    }
  }
}
