import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/web/settings_page.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'connection_page.dart';
import '../../common/widgets/dialog.dart';   // 增加自定义ID弹窗
import '../../common/widgets/account_api.dart';
import 'dart:async';   // 增加自定义ID弹窗
import '../../utils/platform_channel.dart';

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  final List<PageShape> _pages = [];
  int _chatPageTabIndex = -1;
  bool get isChatPageCurrentTab => isAndroid
      ? _selectedIndex == _chatPageTabIndex
      : false; // change this when ios have chat page

  void refreshPages() {
    setState(() {
      initPages();
    });
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _checkCustomId();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    initPages();
    // 运行中 ID 冲突：Rust 推 need_wait_id，立刻弹窗
    platformFFI.registerEventHandler(
      'need_wait_id',
      'need_wait_id',
      (Map<String, dynamic> evt) async {
        if (!mounted) return;
        await _checkCustomId();
      },
    );
    WidgetsBinding.instance.addObserver(this);
    // 增加自定义ID
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkCustomId();
    });
  }

  void initPages() {
    _pages.clear();
    if (!bind.isIncomingOnly()) {
      _pages.add(ConnectionPage(
        appBarActions: [],
      ));
    }
    if (isAndroid && !bind.isOutgoingOnly()) {
      _chatPageTabIndex = _pages.length;
      _pages.addAll([ChatPage(type: ChatPageType.mobileMain), ServerPage()]);
    }
    _pages.add(SettingsPage());
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          if (_selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
          } else {
            return true;
          }
          return false;
        },
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: appTitle(),
            actions: [],
          ),
          bottomNavigationBar: BottomNavigationBar(
            key: navigationBarKey,
            // 改动：label固定为空字符串，只保留图标，所有tab文字全部隐藏
            items: _pages
                .map((page) =>
                    BottomNavigationBarItem(icon: page.icon, label: ""))
                .toList(),
            currentIndex: _selectedIndex,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: MyTheme.accent,
            unselectedItemColor: MyTheme.darkGray,
            onTap: (index) => setState(() {
              if (_selectedIndex != index) {
                _selectedIndex = index;
                if (isChatPageCurrentTab) {
                  gFFI.chatModel.hideChatIconOverlay();
                  gFFI.chatModel.hideChatWindowOverlay();
                  gFFI.chatModel.mobileClearClientUnread(
                      gFFI.chatModel.currentKey.connId);
                }
              }
            }),
          ),
          body: _pages.elementAt(_selectedIndex),
        ));
  }

  bool _customIdDialogShowing = false;

  /// 启动时调用：没设过 ID 就弹，不依赖 NEED_WAIT_ID
  Future<void> checkCustomIdOnStartup() async {
    if (!mounted) return;
    final myId = await bind.mainGetMyId();
    if (myId.isNotEmpty) return;
    await _showCustomIdIfNeeded();
  }

  /// 事件/前后台切换调用：need_wait_id 或没设过 ID 都弹
  Future<void> _checkCustomId() async {
    final myId = await bind.mainGetMyId();
    final needWait = await bind.mainNeedWaitId();
    if (myId.isNotEmpty && !needWait) return;
    await _showCustomIdIfNeeded();
  }

  Future<void> _showCustomIdIfNeeded() async {
    if (!mounted || _customIdDialogShowing) return;
    _customIdDialogShowing = true;
    try {
      await _showCustomIdDialog();
    } finally {
      _customIdDialogShowing = false;
    }
  }
  
  Future<void> _showCustomIdDialog() {
    final completer = Completer<void>();
    final controller = TextEditingController();
    final inviteController = TextEditingController();
    final errorNotifier = ValueNotifier<String?>(null);
    final inviteErrorNotifier = ValueNotifier<String?>(null);
    final submittingNotifier = ValueNotifier<bool>(false);

    gFFI.dialogManager.show((setState, close, context) {
      submit() async {
        if (submittingNotifier.value) return;
        final id = controller.text.trim();
        if (id.isEmpty) {
          errorNotifier.value = '请输入ID';
          return;
        }
        if (!RegExp(r'^[a-zA-Z]').hasMatch(id)) {
          errorNotifier.value = '必须以字母开头';
          return;
        }
        if (id.length < 6 || id.length > 16) {
          errorNotifier.value = '长度必须是6-16位';
          return;
        }
        if (!RegExp(r'^[a-zA-Z][\w-]{5,15}$').hasMatch(id)) {
          errorNotifier.value = '只能包含字母、数字、下划线、连字符';
          return;
        }
        final invite = inviteController.text.trim();
        if (invite.isEmpty) {
          inviteErrorNotifier.value = '请输入邀请码';
          return;
        }
        errorNotifier.value = null;
        inviteErrorNotifier.value = null;
        submittingNotifier.value = true;
        String deviceCode = '';
        try {
          deviceCode = (await RdPlatformChannel.instance.getAndroidId()).trim();
        } catch (_) {}
        if (deviceCode.isEmpty) {
          try {
            deviceCode = (await bind.mainGetOption(key: 'device_code')).trim();
          } catch (_) {}
        }
        final r = await AccountApi.checkInvite(invite, id, deviceCode);
        if (!r.isOk) {
          submittingNotifier.value = false;
          if (r.code == 'INVITE_ERROR') {
            inviteErrorNotifier.value = '邀请码错误';
          } else if (r.code == 'ID_DUPLICATE') {
            errorNotifier.value = 'ID 已存在，请换一个';
          } else {
            inviteErrorNotifier.value = '邀请码校验失败';
          }
          return;
        }
        await bind.mainClearIdConflict();
        await bind.mainSetCustomId(id: id);
        close();
        if (!completer.isCompleted) completer.complete();
      }

      return CustomAlertDialog(
        title: const Text('设置ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<String?>(
              valueListenable: errorNotifier,
              builder: (context, errorMsg, _) {
                return TextField(
                  controller: controller,
                  cursorColor: const Color(0xFF2E7D32),
                  decoration: InputDecoration(
                    labelText: '设备ID',
                    errorText: errorMsg,
                    labelStyle: const TextStyle(color: Colors.black54),
                    floatingLabelStyle: const TextStyle(color: Color(0xFF2E7D32)),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.black38),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                    ),
                  ),
                ).workaroundFreezeLinuxMint();
              },
            ),
            const SizedBox(height: 8),
            const Text(
              '以字母开头，6-16位，仅限字母、数字、下划线、连字符',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String?>(
              valueListenable: inviteErrorNotifier,
              builder: (context, inviteError, _) {
                return TextField(
                  controller: inviteController,
                  cursorColor: const Color(0xFF2E7D32),
                  decoration: InputDecoration(
                    labelText: '邀请码',
                    errorText: inviteError,
                    labelStyle: const TextStyle(color: Colors.black54),
                    floatingLabelStyle:
                        const TextStyle(color: Color(0xFF2E7D32)),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.black38),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                    ),
                  ),
                ).workaroundFreezeLinuxMint();
              },
            ),
          ],
        ),
        actions: [
          dialogButton('确认',
              onPressed: submit,
              style: const TextStyle(color: Color(0xFF2E7D32))),
        ],
        onSubmit: submit,
        onCancel: () {},
      );
    }, backDismiss: false, clickMaskDismiss: false);
    return completer.future;
  }

  Widget appTitle() {
    final currentUser = gFFI.chatModel.currentUser;
    final currentKey = gFFI.chatModel.currentKey;
    if (isChatPageCurrentTab &&
        currentUser != null &&
        currentKey.peerId.isNotEmpty) {
      final connected =
          gFFI.serverModel.clients.any((e) => e.id == currentKey.connId);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Tooltip(
            message: currentKey.isOut
                ? translate('Outgoing connection')
                : translate('Incoming connection'),
            child: Icon(
              currentKey.isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${currentUser.firstName}   ${currentUser.id}",
                  ),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 133, 246, 199)),
                    ).marginSymmetric(horizontal: 2),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Text("");
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text("电子邮件 (Preview)"),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "rustdesk://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id, 
        isFileTransfer: isFileTransfer, 
        isViewCamera: isViewCamera, 
        isTerminal: isTerminal,
        password: password);
    }
  }
}