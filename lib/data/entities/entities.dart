import 'package:objectbox/objectbox.dart';

@Entity()
class TopicEntity {
  @Id()
  int id = 0;
  @Unique()
  late String uuid;
  late String name;
  String description = '';
  String category = 'Personal';
  int iconIndex = 0;
  late DateTime createdAt;
  String nfcId = '';
}

@Entity()
class DocumentEntity {
  @Id()
  int id = 0;
  @Unique()
  late String uuid;
  final topic = ToOne<TopicEntity>();
  late String name;
  late String type;
  int sizeBytes = 0;
  late String path;
  int pageCount = 0;
  int chunkCount = 0;
  String status = 'ready';
  late DateTime createdAt;
  String contentSha256 = '';
}

@Entity()
class ChunkEntity {
  @Id()
  int id = 0;
  final document = ToOne<DocumentEntity>();
  final topic = ToOne<TopicEntity>();
  late String text;
  int pageNumber = 1;
  int chunkIndex = 0;
  String embeddingModelId = '';
  @HnswIndex(dimensions: 384, distanceType: VectorDistanceType.cosine)
  @Property(type: PropertyType.floatVector)
  List<double>? vector;
}

@Entity()
class ChatMessageEntity {
  @Id()
  int id = 0;
  final topic = ToOne<TopicEntity>();
  late String text;
  bool isUser = false;
  String sourcesJson = '[]';
  late DateTime createdAt;
}

@Entity()
class ModelEntity {
  @Id()
  int id = 0;
  @Unique()
  late String uuid;
  late String name;
  late String kind;
  String repoId = '';
  String filename = '';
  String localPath = '';
  int sizeBytes = 0;
  String status = 'available';
  bool isActive = false;
  String sha256 = '';
  int dimensions = 0;
  String license = '';
}

@Entity()
class SettingEntity {
  @Id()
  int id = 0;
  @Unique()
  late String key;
  late String value;
}
