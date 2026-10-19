import 'dart:async';

import 'package:PiliPlus/http/dynamics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/common/common_data_controller.dart';
import 'package:PiliPlus/pages/dynamics_tab/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' show TabController;

class DynamicsController
    extends CommonDataController<FollowUpModel, FollowUpModel>
    with GetSingleTickerProviderStateMixin, AccountMixin {
  late final TabController tabController;

  final Set<int> tempBannedList = <int>{};

  String? _offset;
  late int _page = 1;
  late bool _isEnd = false;
  Set<UpItem>? _cacheUpList;
  final Map<int, int> _latestDynamicTimes = {};
  final Set<int> _timestampFetchedMids = {};
  int _sortGeneration = 0;
  Future<void>? _queryFuture;
  final selectedUpMid = (-1).obs;
  int get currentMid => selectedUpMid.value;
  bool get upSwipeEnabled =>
      tabController.index == 0 && !tabController.indexIsChanging;

  List<UpItem> get visibleUpList {
    final items =
        loadingState.value.dataOrNull?.upList
            ?.where((item) => item.mid > 0 && item.mid != Accounts.main.mid)
            .toSet()
            .toList() ??
        <UpItem>[];
    return items..sort((a, b) {
      final byTime = (_latestDynamicTimes[b.mid] ?? 0).compareTo(
        _latestDynamicTimes[a.mid] ?? 0,
      );
      // Keep ties stable across refreshes, regardless of the server's order.
      return byTime != 0 ? byTime : a.mid.compareTo(b.mid);
    });
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
    tabController = TabController(
      vsync: this,
      length: DynamicsTabType.visibleTabs.length,
      initialIndex: DynamicsTabType.visibleTabs.indexOf(
        Pref.defaultDynamicType,
      ),
    );
    queryData();
  }

  void _selectUp(int mid) {
    for (final item in visibleUpList) {
      if (item.mid == mid) {
        item.hasUpdate = false;
        break;
      }
    }
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
    _sortGeneration++;
    _timestampFetchedMids.clear();
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
    _sortGeneration++;
    tabController.dispose();
    super.onClose();
  }

  @override
  Future<void> onChangeAccount(bool isLogin) async {
    _sortGeneration++;
    _latestDynamicTimes.clear();
    _timestampFetchedMids.clear();
    await _queryFuture;
    if (!isClosed) await onReload();
  }

  @override
  Future<LoadingState<FollowUpModel>> customGetData() async {
    final generation = _sortGeneration;
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
    if (response is Success<FollowUpModel>) {
      await _loadLatestDynamicTimes(
        response.response.upList ?? const [],
        generation,
        accountMid,
      );
    }
    return response;
  }

  Future<void> _loadLatestDynamicTimes(
    List<UpItem> items,
    int generation,
    int accountMid,
  ) async {
    final mids = items
        .map((item) => item.mid)
        .where((mid) => mid > 0 && mid != accountMid)
        .toSet()
        .difference(_timestampFetchedMids)
        .toList();
    final times = <int, int>{};
    var next = 0;
    bool isCurrent() =>
        !isClosed &&
        generation == _sortGeneration &&
        accountMid == Accounts.main.mid;

    Future<void> load() async {
      while (next < mids.length && isCurrent()) {
        final mid = mids[next++];
        final result = await DynamicsHttp.latestDynamicPubTime(mid);
        if (result is Success<int>) times[mid] = result.response;
      }
    }

    // Bound concurrent requests and publish the new order once per page.
    await Future.wait(List.generate(mids.length.clamp(0, 3), (_) => load()));
    if (isCurrent()) {
      // Failed requests retain the last known publication time.
      _latestDynamicTimes.addAll(times);
      _timestampFetchedMids.addAll(times.keys);
    }
  }

  @override
  Future<void> queryData([bool isRefresh = true]) {
    if (isLoading) return _queryFuture ?? Future.value();
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
      loadingState.value = response;
    } else {
      if (_showAllUp) {
        _page++;
      }

      if (res.upList case final upList? when upList.isNotEmpty) {
        if (_showAllUp && _cacheUpList != null) {
          upList.removeWhere(_cacheUpList!.contains);
        }
        loadingState
          ..value.data.addAllUpList(upList)
          ..refresh();
      }
    }

    return true;
  }
}
