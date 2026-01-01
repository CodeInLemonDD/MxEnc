// import 'package:mxenc/screens/bookshelf_screen.dart';

class SeriesVolume {
  final String id;
  final String title;
  final String filename; // 相对路径，如 "vol1.mxenc"
  final int size;
  final List<String> tags;

  const SeriesVolume({
    required this.id,
    required this.title,
    required this.filename,
    this.size = 0,
    this.tags = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filename': filename,
    'size': size,
    'tags': tags,
  };

  factory SeriesVolume.fromJson(Map<String, dynamic> json) {
    return SeriesVolume(
      id: json['id'] as String,
      title: json['title'] as String,
      filename: json['filename'] as String,
      size: (json['size'] as int?) ?? 0,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class SeriesMetadata {
  final String id;
  final String title;
  final String author;
  final String coverPath; // 相对路径，如 "cover.jpg"
  final List<SeriesVolume> volumes;
  // 存储分卷密码（可能已加密）
  // Key: volumeId, Value: password (potentially encrypted or obfuscated)
  final Map<String, String> passwords;

  const SeriesMetadata({
    required this.id,
    required this.title,
    required this.author,
    required this.coverPath,
    required this.volumes,
    required this.passwords,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'coverPath': coverPath,
    'volumes': volumes.map((e) => e.toJson()).toList(),
    'passwords': passwords,
  };

  factory SeriesMetadata.fromJson(Map<String, dynamic> json) {
    return SeriesMetadata(
      id: json['id'] as String,
      title: json['title'] as String,
      author: (json['author'] ?? '未知作者') as String,
      coverPath: (json['coverPath'] ?? '') as String,
      volumes: (json['volumes'] as List<dynamic>?)
          ?.map((e) => SeriesVolume.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
      passwords: (json['passwords'] as Map<String, dynamic>?)
          ?.cast<String, String>() ??
          {},
    );
  }

  SeriesMetadata copyWith({
    String? id,
    String? title,
    String? author,
    String? coverPath,
    List<SeriesVolume>? volumes,
    Map<String, String>? passwords,
  }) {
    return SeriesMetadata(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      volumes: volumes ?? this.volumes,
      passwords: passwords ?? this.passwords,
    );
  }
}
