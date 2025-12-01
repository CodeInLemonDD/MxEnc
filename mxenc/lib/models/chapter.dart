class Chapter {
  final String id; // 章节ID
  final String title; // 章节标题
  final int wordCount; // 字数
  final bool isLocked; // 是否锁定
  final DateTime? updateTime; // 更新时间

  Chapter({
    required this.id,
    required this.title,
    this.wordCount = 0,
    this.isLocked = false,
    this.updateTime,
  });

  // 从JSON创建Chapter实例
  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      wordCount: json['wordCount'] ?? 0,
      isLocked: json['isLocked'] ?? false,
      updateTime: json['updateTime'] != null ? DateTime.parse(json['updateTime']) : null,
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'wordCount': wordCount,
      'isLocked': isLocked,
      'updateTime': updateTime?.toIso8601String(),
    };
  }
}