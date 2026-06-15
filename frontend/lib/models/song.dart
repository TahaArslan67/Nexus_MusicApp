import 'package:hive/hive.dart';

/// Song model — Hive ile yerel depolama için serialize edilebilir
/// Backend yok! Tüm veri cihazda Hive ile saklanır.
class Song {
  final int id;
  final String youtubeId;
  final String title;
  final String artist;
  final int durationSeconds;
  final String thumbnailUrl;
  final String audioUrl;
  final bool isCached;

  const Song({
    this.id = 0,
    required this.youtubeId,
    required this.title,
    required this.artist,
    this.durationSeconds = 0,
    this.thumbnailUrl = '',
    this.audioUrl = '',
    this.isCached = false,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as int? ?? 0,
      youtubeId: json['youtube_id'] as String? ?? json['youtubeId'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      durationSeconds: json['duration_seconds'] as int? ?? json['durationSeconds'] as int? ?? 0,
      thumbnailUrl: json['thumbnail_url'] as String? ?? json['thumbnailUrl'] as String? ?? '',
      audioUrl: json['audio_url'] as String? ?? json['audioUrl'] as String? ?? '',
      isCached: json['is_cached'] as bool? ?? json['isCached'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'youtube_id': youtubeId,
    'title': title,
    'artist': artist,
    'duration_seconds': durationSeconds,
    'thumbnail_url': thumbnailUrl,
    'audio_url': audioUrl,
    'is_cached': isCached,
  };

  String get formattedDuration {
    final mins = durationSeconds ~/ 60;
    final secs = durationSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => 'Song(youtubeId: $youtubeId, title: $title, artist: $artist)';
}

/// Hive TypeAdapter — Song'u Hive kutusunda saklamak için
class SongAdapter extends TypeAdapter<Song> {
  @override
  final int typeId = 0;

  @override
  Song read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      final key = reader.readByte();
      final value = reader.read();
      fields[key] = value;
    }
    return Song(
      id: fields[0] as int? ?? 0,
      youtubeId: fields[1] as String? ?? '',
      title: fields[2] as String? ?? '',
      artist: fields[3] as String? ?? '',
      durationSeconds: fields[4] as int? ?? 0,
      thumbnailUrl: fields[5] as String? ?? '',
      audioUrl: fields[6] as String? ?? '',
      isCached: fields[7] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Song obj) {
    writer.writeByte(8); // 8 fields
    writer.writeByte(0); writer.write(obj.id);
    writer.writeByte(1); writer.write(obj.youtubeId);
    writer.writeByte(2); writer.write(obj.title);
    writer.writeByte(3); writer.write(obj.artist);
    writer.writeByte(4); writer.write(obj.durationSeconds);
    writer.writeByte(5); writer.write(obj.thumbnailUrl);
    writer.writeByte(6); writer.write(obj.audioUrl);
    writer.writeByte(7); writer.write(obj.isCached);
  }
}
