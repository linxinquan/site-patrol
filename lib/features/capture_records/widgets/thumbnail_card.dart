import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/theme/design_tokens.dart';

/// 验收记录列表项卡片：96×96 缩略图 + 部位 · 楼层 + 时刻 · 缺陷数。
///
/// Web 端 / 空记录：缩略图退化为带图标的占位块，列表节奏仍保持一致。
class CaptureThumbnailCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onTap;

  const CaptureThumbnailCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final anchor = entry['anchor']?.toString() ?? '未命名部位';
    final floor = entry['floor']?.toString() ?? '';
    final ts = entry['ts']?.toString() ?? '';
    final photo = entry['photo']?.toString();
    final defectCount = _pendingDefectCount(entry);
    final hasDefect = defectCount > 0;

    return Material(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(10),
                      ),
                      child: _Thumbnail(photo: photo),
                    ),
                    if (hasDefect)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTokens.danger,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(MingCuteIcons.alertLine,
                                  size: 10, color: AppTokens.onAccent),
                              const SizedBox(width: 2),
                              Text('$defectCount',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppTokens.onAccent,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      )
                    else
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTokens.success,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(MingCuteIcons.checkCircleLine,
                              size: 10, color: AppTokens.onAccent),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      anchor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [if (floor.isNotEmpty) floor, _shortTs(ts)]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10, color: AppTokens.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static int _pendingDefectCount(Map<String, dynamic> e) {
    final ds = e['defects'];
    if (ds is! List) return 0;
    var n = 0;
    for (final d in ds) {
      if (d is! Map) continue;
      if ((d['status']?.toString() ?? 'pending') != 'converted') n++;
    }
    return n;
  }

  static String _shortTs(String ts) {
    if (ts.length < 16) return ts;
    return ts.substring(5, 16).replaceFirst(' ', ' ');
  }
}

class _Thumbnail extends StatelessWidget {
  final String? photo;
  const _Thumbnail({this.photo});

  @override
  Widget build(BuildContext context) {
    if (photo == null || photo!.isEmpty) {
      return Container(
        color: AppTokens.surface2,
        alignment: Alignment.center,
        child: const Icon(MingCuteIcons.photoAlbumLine,
            size: 22, color: AppTokens.muted),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: LocalStorage.instance.readFile(photo!),
      builder: (_, snap) {
        final bytes = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            color: AppTokens.surface2,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          );
        }
        if (bytes == null || bytes.isEmpty) {
          return Container(
            color: AppTokens.surface2,
            alignment: Alignment.center,
            child: const Icon(MingCuteIcons.photoAlbumLine,
                size: 22, color: AppTokens.muted),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}