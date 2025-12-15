class NovelChapter {
  final String title;
  final String content;

  const NovelChapter({required this.title, required this.content});
}

class NovelData {
  final String title;
  final String author;
  final String description;
  final List<NovelChapter> chapters;
  final List<String> tags;
  final String? authorNickname;
  final String? authorSignature;
  final String? authorAvatarPath;
  final String? authorDeviceId;

  const NovelData({
    required this.title,
    required this.author,
    required this.description,
    required this.chapters,
    this.tags = const [],
    this.authorNickname,
    this.authorSignature,
    this.authorAvatarPath,
    this.authorDeviceId,
  });

  static List<String> _splitTags(dynamic v) {
    final List<String> out = [];
    if (v is String) {
      out.addAll(v.split(RegExp(r'[，,]')).map((e) => e.trim()).where((e) => e.isNotEmpty));
    } else if (v is List) {
      for (final el in v) {
        final s = (el ?? '').toString();
        out.addAll(s.split(RegExp(r'[，,]')).map((e) => e.trim()).where((e) => e.isNotEmpty));
      }
    }
    return out;
  }

  factory NovelData.fromJson(Map<String, dynamic> json) {
    final chaptersJson = (json['chapters'] as List<dynamic>? ?? []);
    final chapters = chaptersJson.map((e) {
      final m = e as Map<String, dynamic>;
      return NovelChapter(
        title: (m['title'] ?? '').toString(),
        content: (m['content'] ?? '').toString(),
      );
    }).toList();
    final tags = _splitTags(json['tags']);
    return NovelData(
      title: (json['title'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      chapters: chapters,
      tags: tags,
      authorNickname: (json['authorNickname'] ?? '').toString(),
      authorSignature: (json['authorSignature'] ?? '').toString(),
      authorAvatarPath: (json['authorAvatarPath'] ?? '').toString(),
      authorDeviceId: (json['authorDeviceId'] ?? '').toString(),
    );
  }
}
