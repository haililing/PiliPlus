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
  final showUpDynamics = false.obs;

  final Set<int> tempBannedList = <int>{};

  String? _offset;
  late int _page = 1;
  late bool _isEnd = false;
  Set<UpItem>? _cacheUpList;
  late int hostMid = -1;
  final selectedUpMid = (-1).obs;
  int get currentMid => selectedUpMid.value;
  int upSelectionRevision = 0;
  bool get upSwipeEnabled =>
      tabController.index == 0 && !tabController.indexIsChanging;

  List<UpItem> get visibleUpList =>
      loadingState.value.dataOrNull?.upList
          ?.where((item) => item.mid > 0 && item.mid != Accounts.main.mid)
          .toSet()
          .toList() ??
      const [];
  late bool showLiveUp = Pref.expandDynLivePanel;
  late final _showAllUp = Pref.dynamicsShowAllFollowedUp;

  final upPanelPosition = Pref.upPanelPosition;

  @override
  final AccountService accountService = Get.find<AccountService>();

  DynamicsTabController? get controller {
    try {
      final type = DynamicsTabType.visibleTabs[tabController.index];
      return Get.find<DynamicsTabController>(
        tag: type == .all && showUpDynamics.value
            ? DynamicsTabType.up.name
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

  void _jumpToTab(int mid) {
    showUpDynamics.value = mid != -1;
    tabController.index = 0;
  }

  void onSelectUp(int mid) {
    for (final item in visibleUpList) {
      if (item.mid == mid) {
        item.hasUpdate = false;
        break;
      }
    }
    upSelectionRevision++;
    if (currentMid == mid) {
      _jumpToTab(mid);
      if (mid == -1) {
        singleRefresh();
      }
      controller?.onReload();
      return;
    }

    if (mid != -1) {
      hostMid = mid;
      try {
        Get.find<DynamicsTabController>(
          tag: DynamicsTabType.up.name,
        ).onReload();
      } catch (_) {}
    }

    selectedUpMid.value = mid;
    _jumpToTab(mid);
  }

  Future<int?> prepareAdjacentUp(int direction) async {
    if (!upSwipeEnabled ||
        (direction != -1 && direction != 1) ||
        !loadingState.value.isSuccess) {
      return null;
    }
    final previousMid = currentMid;
    final selectionRevision = upSelectionRevision;
    var upList = visibleUpList;
    var index = upList.indexWhere((item) => item.mid == previousMid);

    if (direction == 1 && index + 1 >= upList.length && !_isEnd) {
      await onLoadMore();
      if (isClosed ||
          !upSwipeEnabled ||
          currentMid != previousMid ||
          selectionRevision != upSelectionRevision) {
        return null;
      }
      upList = visibleUpList;
      index = upList.indexWhere((item) => item.mid == previousMid);
    }

    final nextIndex = index + direction;
    if (direction == -1 && index == 0) {
      return -1;
    } else if (nextIndex >= 0 && nextIndex < upList.length) {
      return upList[nextIndex].mid;
    }
    return null;
  }

  Future<void> singleRefresh() {
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
      singleRefresh();
      return controller.onRefresh();
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
    tabController.dispose();
    super.onClose();
  }

  @override
  void onChangeAccount(bool isLogin) => onReload();

  @override
  Future<LoadingState<FollowUpModel>> customGetData() {
    if (_offset == null) {
      return DynamicsHttp.followUp();
    }
    if (_showAllUp) {
      return DynamicsHttp.followings(
        vmid: Accounts.main.mid,
        pn: _page,
        orderType: 'attention',
        ps: 50,
      );
    } else {
      return DynamicsHttp.dynUpList(_offset);
    }
  }

  @override
  Future<void> queryData([bool isRefresh = true]) {
    if (!isRefresh && _isEnd) return Future.value();
    return super.queryData(isRefresh);
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
