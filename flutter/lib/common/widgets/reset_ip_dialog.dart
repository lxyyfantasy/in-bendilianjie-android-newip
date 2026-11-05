import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/account_api.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/generated_bridge.dart';

Future<void> resetIpDialog(OverlayDialogManager dialogManager) async {
  final ipCtrl = TextEditingController();
  var isInProgress = false;
  String? err;

  dialogManager.show((setState, close, context) {
    submit() async {
      final ip = ipCtrl.text.trim();
      if (ip.isEmpty) {
        setState(() => err = 'IP必填');
        return;
      }
      setState(() {
        isInProgress = true;
        err = null;
      });
      final ok = await AccountApi.probeServerConfig(ip);
      setState(() => isInProgress = false);
      if (!ok) {
        setState(() => err = '该地址不是有效服务器');
        return;
      }
      await bind.mainSetOption(key: 'external-primary-server', value: ip);
      close();
      showToast('重置成功，请重启App生效');
    }

    return CustomAlertDialog(
      title: Text('重置IP'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: ipCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '服务器IP',
              errorText: err,
            ),
          ).workaroundFreezeLinuxMint(),
          if (isInProgress) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        dialogButton('取消', onPressed: close, isOutline: true),
        dialogButton('确认', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}