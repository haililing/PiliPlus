import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/utils/parse_int.dart';
import 'package:PiliPlus/utils/storage.dart';

/// Account-local snapshots contain only the data needed to restore the UP row.
class UpPanelCache {
  const UpPanelCache(this.data, this.publicationTimes, this.checkedAt);

  final FollowUpModel data;
  final Map<int, int> publicationTimes;
  final Map<int, int> checkedAt;

  static String _key(int accountMid) => 'dynamics.up-panel.v1:$accountMid';

  static UpPanelCache? read(int accountMid) {
    if (accountMid <= 0) return null;
    try {
      final raw = GStorage.localCache.get(_key(accountMid));
      if (raw is! Map) return null;
      final items = (raw['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      Map<int, int> readTimes(Object? value) => value is Map
          ? {
              for (final entry in value.entries)
                if (safeToInt(entry.key) case final mid? when mid > 0)
                  if (safeToInt(entry.value) case final time? when time >= 0)
                    mid: time,
            }
          : {};
      return UpPanelCache(
        FollowUpModel.fromUpList({'items': items}),
        readTimes(raw['times']),
        readTimes(raw['checked']),
      );
    } catch (_) {
      // An old or damaged optional cache must not prevent network loading.
      return null;
    }
  }

  static Future<void> write(
    int accountMid,
    List<UpItem> items,
    Map<int, int> publicationTimes,
    Map<int, int> checkedAt,
  ) async {
    if (accountMid <= 0) return;
    // Keep startup I/O bounded even for accounts following many creators.
    final cached = items.take(500).toList();
    try {
      await GStorage.localCache.put(_key(accountMid), {
        'items': [
          for (final item in cached)
            {
              'mid': item.mid,
              'uname': item.uname,
              'face': item.face,
              'has_update': item.hasUpdate,
            },
        ],
        'times': {
          for (final item in cached) item.mid: ?publicationTimes[item.mid],
        },
        'checked': {
          for (final item in cached) item.mid: ?checkedAt[item.mid],
        },
      });
    } catch (_) {
      // Display and refresh remain available if the cache cannot be written.
    }
  }
}
