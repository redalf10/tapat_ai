import 'package:tapat_ai/domain/models/doc_model.dart';
import 'package:tapat_ai/domain/models/topic_model.dart';

class MockData {
  static List<Topic> topics() => [
        Topic(id: '1', name: 'Computer Networking', category: 'Education', iconIndex: 0,
            description: 'Networking training materials, protocols and troubleshooting.',
            created: DateTime(2025, 1, 12), docs: const [
          Doc('d1', 'Networking Basics.pdf', DocType.pdf, 68, 4.2),
          Doc('d2', 'TCP_IP_Guide.pdf', DocType.pdf, 44, 3.1),
          Doc('d3', 'Troubleshooting.txt', DocType.txt, 30, 0.2),
        ]),
        Topic(id: '2', name: 'Machine Maintenance', category: 'Work', iconIndex: 2,
            created: DateTime(2025, 2, 3), docs: const [
          Doc('d4', 'Service_Manual.pdf', DocType.pdf, 70, 6.0),
          Doc('d5', 'Checklist.docx', DocType.docx, 28, 0.4),
        ]),
        Topic(id: '3', name: 'Biology Notes', category: 'Education', iconIndex: 3,
            created: DateTime(2025, 2, 20),
            docs: const [Doc('d6', 'Cell_Biology.pdf', DocType.pdf, 64, 5.0)]),
        Topic(id: '4', name: 'Flutter Development', category: 'Work', iconIndex: 4,
            created: DateTime(2025, 3, 1), docs: const [
          Doc('d7', 'Widgets.pdf', DocType.pdf, 80, 4.0),
          Doc('d8', 'State.pdf', DocType.pdf, 60, 2.0),
          Doc('d9', 'Notes.txt', DocType.txt, 21, 0.1),
          Doc('d10', 'Testing.docx', DocType.docx, 40, 1.0),
        ]),
        Topic(id: '5', name: 'History of Philippines', category: 'Education', iconIndex: 5,
            created: DateTime(2025, 3, 9), docs: const [
          Doc('d11', 'Timeline.pdf', DocType.pdf, 50, 3.0),
          Doc('d12', 'Heroes.txt', DocType.txt, 37, 0.3),
        ]),
        Topic(id: '6', name: 'Mathematics', category: 'Personal', iconIndex: 1,
            created: DateTime(2025, 3, 15),
            docs: const [Doc('d13', 'Algebra.pdf', DocType.pdf, 55, 2.5)]),
      ];
}