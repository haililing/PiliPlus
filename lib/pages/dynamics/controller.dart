import 'dart:async';

import 'package:PiliPlus/http/dynamics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/common/common_data_controller.dart';
import 'package:PiliPlus/pages/dynamics_tab/controller.dart';
import 'package:PiliPlus/pages/dynamics/up_panel_cache.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart'
    show
        AppLifecycleState,
        TabController,
        WidgetsBinding,
        WidgetsBindingObserver;

class DynamicsController
    extends CommonDataController<FollowUpModel, FollowUpModel>
    with
        GetSingleTickerProviderStateMixin,
        AccountMixin,
        WidgetsBindingObserver {
  late final TabController tabController;

  final Set<int> tempBannedList = <int>{};

  String? _offset;
  late int _page = 1;
  late bool _isEnd = false;
  Set<UpItem>? _cacheUpList;
  final Map<int, int> _latestDynamicTimes = {};
  final Map<int, int> _timestampCheckedAt = {};
  final Map<int, UpItem> _upsByMid = {};
  List<UpItem> _visibleUps = const [];
  final Set<int> _pendingTimes = {};
  final Set<int> _inFlightTimes = {};
  CancelToken _sortCancel = CancelToken();
  bool _sorting = false;
  int _sortGeneration = 0;
  Future<void>? _queryFuture;
  final selectedUpMid = (-1).obs;
  int get currentMid => selectedUpMid.value;
  bool get upSwipeEnabled =>
      tabController.index == 0 && !tabController.indexIsChanging;

  List<UpItem> get visibleUpList => _visibleUps;

  bool _rebuildVisibleUps(FollowUpModel data) {
    _upsByMid.clear();
    for (final item in data.upList ?? const <UpItem>[]) {
      if (item.mid > 0 && item.mid != Accounts.main.mid) {
        _upsByMid.putIfAbsent(item.mid, () => item);
      }
    }
    final items = _upsByMid.values.toList()
      ..sort((a, b) {
        final byTime = (_latestDynamicTimes[b.mid] ?? 0).compareTo(
          _latestDynamicTimes[a.mid] ?? 0,
        );
        // Keep ties stable across refreshes, regardless of the server's order.
        return byTime != 0 ? byTime : a.mid.compareTo(b.mid);
      });
    final changed = !listEquals(
      _visibleUps.map((item) => item.mid).toList(),
      items.map((item) => item.mid).toList(),
    );
    _visibleUps = items;
    return changed;
  }

  void _restoreUpPanel() {
    final cache = UpPanelCache.read(Accounts.main.mid);
    if (cache == null) return;
    _latestDynamicTimes.addAll(cache.publicationTimes);
    _timestampCheckedAt.addAll(cache.checkedAt);
    _rebuildVisibleUps(cache.data);
    loadingState.value = Success(cache.data);
  }

  late bool showLiveUp = Pref.expandDynLivePanel;
  late final _showAllUp = Pref.dynamicsShowAllFollowedUp;

  final upPanelPosition = Pref.upPanelPosition;

  @override
  final AccountService accountService = Get.find<AccountService>();

  DynamicsTabController? get controller {
    try {
      final type = DynamicsTabType.visibleTabs[tabController.index];
      return Get.find<DynamicsTabController>(
        tag: type == .all && currentMid != -1
            ? DynamicsTabController.tagFor(.up, hostMid: currentMid)
            : type.name,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    tabController = TabController(
      vsync: this,
      length: DynamicsTabType.visibleTabs.length,
      initialIndex: DynamicsTabType.visibleTabs.indexOf(
        Pref.defaultDynamicType,
      ),
    );
    _restoreUpPanel();
    queryData();
  }

  void _selectUp(int mid) {
    _upsByMid[mid]?.hasUpdate = false;
    selectedUpMid.value = mid;
  }

  void onSelectUp(int mid) {
    final isCurrent = currentMid == mid;
    tabController.index = 0;
    _selectUp(mid);
    if (isCurrent) {
      if (mid == -1) {
        singleRefresh();
      }
      controller?.onReload();
    }
  }

  /// Updates avatar selection without navigating or reloading a paging feed.
  void onUpPageChanged(int mid) {
    _selectUp(mid);
  }

  Future<void> singleRefresh() {
    if (isLoading) return _queryFuture ?? Future.value();
    _resetSortJobs();
    if (_showAllUp) {
      _page = 1;
      _cacheUpList = null;
    }
    _offset = null;
    _isEnd = false;
    return super.onRefresh();
  }

  @override
  Future<void> onRefresh() {
    final controller = this.controller;
    if (controller != null) {
      return Future.wait([
        singleRefresh(),
        controller.onRefresh(),
      ]);
    }
    return singleRefresh();
  }

  @override
  void animateToTop() {
    controller?.animateToTop();
    scrollController.animToTop();
  }

  @override
  void toTopOrRefresh() {
    final ctr = controller;
    if (ctr?.scrollController.hasClients == true) {
      if (ctr!.scrollController.position.pixels == 0) {
        if (scrollController.hasClients &&
            scrollController.position.pixels != 0) {
          scrollController.animToTop();
        }
        EasyThrottle.throttle(
          'topOrRefresh',
          const Duration(milliseconds: 500),
          onRefresh,
        );
      } else {
        animateToTop();
      }
    } else {
      super.toTopOrRefresh();
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _resetSortJobs();
    tabController.dispose();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queueLatestTimes(_visibleUps);
    } else {
      _resetSortJobs();
      if (loadingState.value.isSuccess) unawaited(_saveUpPanel());
    }
  }

  @override
  Future<void> onChangeAccount(bool isLogin) async {
    _resetSortJobs();
    _latestDynamicTimes.clear();
    _timestampCheckedAt.clear();
    _upsByMid.clear();
    _visibleUps = const [];
    selectedUpMid.value = -1;
    loadingState.value = LoadingState.loading();
    _restoreUpPanel();
    await _queryFuture;
    if (!isClosed) await onReload();
  }

  @override
  Future<void> onReload() => singleRefresh();

  @override
  bool handleError(String? errMsg) => loadingState.value.isSuccess;

  @override
  Future<LoadingState<FollowUpModel>> customGetData() async {
    final accountMid = Accounts.main.mid;
    final LoadingState<FollowUpModel> response;
    if (_offset == null) {
      response = await DynamicsHttp.followUp();
    } else if (_showAllUp) {
      response = await DynamicsHttp.followings(
        vmid: Accounts.main.mid,
        pn: _page,
        orderType: 'attention',
        ps: 50,
      );
    } else {
      response = await DynamicsHttp.dynUpList(_offset);
    }
    return accountMid == Accounts.main.mid ? response : const Error('账号已切换');
  }

  void _resetSortJobs() {
    _sortGeneration++;
    _sortCancel.cancel();
    _sortCancel = CancelToken();
    _pendingTimes.clear();
    _inFlightTimes.clear();
    _sorting = false;
  }

  Future<void> _saveUpPanel() => UpPanelCache.write(
    Accounts.main.mid,
    _visibleUps,
    _latestDynamicTimes,
    _timestampCheckedAt,
  );

  /// Reuse timestamps from feeds already requested for display; no extra I/O.
  void observePublicationTimes(Map<int, int> times, {required bool firstPage}) {
    if (isClosed) return;
    var changed = false;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in times.entries) {
      if (entry.value > (_latestDynamicTimes[entry.key] ?? 0)) {
        _latestDynamicTimes[entry.key] = entry.value;
        changed = true;
      }
      if (firstPage) {
        _timestampCheckedAt[entry.key] = now;
        _pendingTimes.remove(entry.key);
      }
    }
    if (loadingState.value.dataOrNull case final data?) {
      if (changed && _rebuildVisibleUps(data)) loadingState.refresh();
      if (!_sorting && (changed || (firstPage && times.isNotEmpty))) {
        unawaited(_saveUpPanel());
      }
    }
  }

  void _queueLatestTimes(List<UpItem> items) {
    if (WidgetsBinding.instance.lifecycleState case final state?
        when state != AppLifecycleState.resumed) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in items) {
      final mid = item.mid;
      if (!_upsByMid.containsKey(mid) || _inFlightTimes.contains(mid)) continue;
      final checked = _timestampCheckedAt[mid] ?? 0;
      final age = now - checked;
      // Expiry is checked only on a real response, never by a timer.
      if (checked > 0 && age >= 0) {
        if (age < const Duration(seconds: 30).inMilliseconds) continue;
        if (_latestDynamicTimes.containsKey(mid) &&
            item.hasUpdate != true &&
            age < const Duration(minutes: 2).inMilliseconds) {
          continue;
        }
      }
      _pendingTimes.add(mid);
    }
    if (_sorting || _pendingTimes.isEmpty) return;
    _sorting = true;
    unawaited(
      _drainLatestTimes(_sortGeneration, Accounts.main.mid, _sortCancel),
    );
  }

  Future<void> _drainLatestTimes(
    int generation,
    int accountMid,
    CancelToken cancelToken,
  ) async {
    bool isCurrent() =>
        !isClosed &&
        generation == _sortGeneration &&
        accountMid == Accounts.main.mid;
    try {
      // Drain a finite, event-populated queue, two requests at a time.
      while (isCurrent() && _pendingTimes.isNotEmpty) {
        final mids = _pendingTimes.take(2).toList();
        _pendingTimes.removeAll(mids);
        _inFlightTimes.addAll(mids);
        final before = {for (final mid in mids) mid: _latestDynamicTimes[mid]};
        final results = await Future.wait(
          mids.map(
            (mid) => DynamicsHttp.latestDynamicPubTime(
              mid,
              cancelToken: cancelToken,
            ),
          ),
        );
        if (!isCurrent()) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < mids.length; i++) {
          final mid = mids[i];
          _inFlightTimes.remove(mid);
          _timestampCheckedAt[mid] = now;
          if (results[i] case Success<int>(:final response)) {
            // A displayed feed may have supplied newer data during this request.
            if (_latestDynamicTimes[mid] == before[mid] ||
                response > (_latestDynamicTimes[mid] ?? 0)) {
              _latestDynamicTimes[mid] = response;
            }
          }
        }
        if (loadingState.value.dataOrNull case final data?) {
          if (_rebuildVisibleUps(data)) loadingState.refresh();
        }
      }
    } finally {
      if (isCurrent()) {
        _sorting = false;
        await _saveUpPanel();
      }
    }
  }

  @override
  Future<void> queryData([bool isRefresh = true]) {
    if (isLoading) return _queryFuture ?? Future.value();
    if (!isRefresh && !loadingState.value.isSuccess) return Future.value();
    if (!isRefresh && _isEnd) return Future.value();
    final query = super.queryData(isRefresh);
    _queryFuture = query;
    return query.whenComplete(() => _queryFuture = null);
  }

  @override
  bool customHandleResponse(bool isRefresh, Success<FollowUpModel> response) {
    final res = response.response;

    if (_showAllUp) {
      if (res.upList?.isNotEmpty != true) {
        _isEnd = true;
      }
    } else {
      _offset = res.offset;
      if (res.hasMore != true || _offset.isNullOrEmpty) {
        _isEnd = true;
      }
    }

    if (isRefresh) {
      if (_showAllUp) {
        _offset = '';
        _cacheUpList = res.upList?.toSet();
      }
      _rebuildVisibleUps(res);
      loadingState.value = response;
    } else {
      if (_showAllUp) {
        _page++;
      }

      if (res.upList case final upList? when upList.isNotEmpty) {
        if (_showAllUp && _cacheUpList != null) {
          upList.removeWhere(_cacheUpList!.contains);
        }
        final data = loadingState.value.data..addAllUpList(upList);
        _rebuildVisibleUps(data);
        loadingState.refresh();
      }
    }

    unawaited(_saveUpPanel());
    _queueLatestTimes(res.upList ?? const []);
    return true;
  }
}
