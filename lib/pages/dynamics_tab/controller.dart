import 'package:PiliPlus/http/dynamics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/msg.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class DynamicsTabController
    extends CommonListController<DynamicsDataModel, DynamicItemModel>
    with AccountMixin {
  DynamicsTabController({required this.dynamicsType});
  final DynamicsTabType dynamicsType;

  String? offset;
  int? _queryHostMid;
  int? _queryUpRevision;

  bool get _hasStaleUpResponse =>
      dynamicsType == .up &&
      (_queryHostMid != dynamicsController.hostMid ||
          _queryUpRevision != dynamicsController.upSelectionRevision);

  late final mainController = Get.find<MainController>();
  final dynamicsController = Get.find<DynamicsController>();

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    if (dynamicsType != .up || isLoading) {
      return super.queryData(isRefresh);
    }
    while (!isClosed) {
      _queryHostMid = dynamicsController.hostMid;
      _queryUpRevision = dynamicsController.upSelectionRevision;
      await super.queryData(isRefresh);
      if (!_hasStaleUpResponse) return;
      // A newer selection replaces the old request, including during pagination.
      isRefresh = true;
      offset = null;
      page = 1;
      isEnd = false;
    }
  }

  @override
  bool customHandleResponse(
    bool isRefresh,
    Success<DynamicsDataModel> response,
  ) => _hasStaleUpResponse;

  @override
  bool handleError(String? errMsg) => _hasStaleUpResponse;

  @override
  Future<void> onRefresh() {
    if (dynamicsType == .all) {
      mainController.setDynCount();
    }
    offset = null;
    return super.onRefresh();
  }

  @override
  List<DynamicItemModel>? getDataList(DynamicsDataModel response) {
    offset = response.offset;
    return response.items;
  }

  @override
  Future<LoadingState<DynamicsDataModel>> customGetData() =>
      DynamicsHttp.followDynamic(
        offset: offset,
        type: dynamicsType,
        hostMid: dynamicsController.hostMid,
        tempBannedList: dynamicsController.tempBannedList,
      );

  Future<void> onRemove(int index, dynamic dynamicId) async {
    final res = await MsgHttp.removeDynamic(dynIdStr: dynamicId);
    if (res.isSuccess) {
      loadingState
        ..value.data!.removeAt(index)
        ..refresh();
      SmartDialog.showToast('删除成功');
    } else {
      res.toast();
    }
  }

  @override
  Future<void> onReload() {
    scrollController.jumpToTop();
    return super.onReload();
  }

  void onBlock(int index) {
    if (dynamicsType != .up) {
      loadingState
        ..value.data!.removeAt(index)
        ..refresh();
    }
  }

  void onUnfold(DynamicItemModel item, int index) {
    try {
      final list = loadingState.value.data!;
      final ids = item.modules.moduleFold!.ids!;
      final flag = index + ids.length + 1;
      for (int i = index + 1; i < flag; i++) {
        list[i].visible = true;
      }
      item.modules.moduleFold = null;
      loadingState.refresh();
    } catch (_) {}
  }

  @override
  void onChangeAccount(bool isLogin) => onReload();
}
