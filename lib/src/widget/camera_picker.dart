///
/// [Author] Alex (https://github.com/AlexV525)
/// [Date] 2020/7/13 11:08
///
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

import '../constants/constants.dart';
import '../widget/circular_progress_bar.dart';

import 'builder/slide_page_transition_builder.dart';
import 'camera_picker_viewer.dart';
import 'exposure_point_widget.dart';

const Duration _kRouteDuration = Duration(milliseconds: 300);

/// Create a camera picker integrate with [CameraDescription].
/// 通过 [CameraDescription] 整合的拍照选择
///
/// The picker provides create an [AssetEntity] through the camera.
///
/// 该选择器可以通过拍照创建 [AssetEntity]。
class CameraPicker extends StatefulWidget {
  CameraPicker({
    Key key,
    this.isAllowRecording = false,
    this.isOnlyAllowRecording = false,
    this.enableAudio = true,
    this.maximumRecordingDuration = const Duration(seconds: 15),
    this.theme,
    this.resolutionPreset = ResolutionPreset.max,
    this.cameraQuarterTurns = 0,
    CameraPickerTextDelegate textDelegate,
  })  : assert(
          isAllowRecording == true || isOnlyAllowRecording != true,
          'Recording mode error.',
        ),
        assert(
          resolutionPreset != null,
          'Resolution preset must not be null.',
        ),
        super(key: key) {
    Constants.textDelegate = textDelegate ??
        (isAllowRecording
            ? DefaultCameraPickerTextDelegateWithRecording()
            : DefaultCameraPickerTextDelegate());
  }

  /// The number of clockwise quarter turns the camera view should be rotated.
  /// 摄像机视图顺时针旋转次数，每次90度
  final int cameraQuarterTurns;

  /// Whether the picker can record video.
  /// 选择器是否可以录像
  final bool isAllowRecording;

  /// Whether the picker can record video.
  /// 选择器是否可以录像
  final bool isOnlyAllowRecording;

  /// Whether the picker should record audio.
  /// 选择器录像时是否需要录制声音
  final bool enableAudio;

  /// The maximum duration of the video recording process.
  /// 录制视频最长时长
  ///
  /// Defaults to 15 seconds, also allow `null` for unrestricted video recording.
  final Duration maximumRecordingDuration;

  /// Theme data for the picker.
  /// 选择器的主题
  final ThemeData theme;

  /// Present resolution for the camera.
  /// 相机的分辨率预设
  final ResolutionPreset resolutionPreset;

  /// Static method to create [AssetEntity] through camera.
  /// 通过相机创建 [AssetEntity] 的静态方法
  static Future<AssetEntity> pickFromCamera(
    BuildContext context, {
    bool isAllowRecording = false,
    bool isOnlyAllowRecording = false,
    bool enableAudio = true,
    Duration maximumRecordingDuration = const Duration(seconds: 15),
    ThemeData theme,
    int cameraQuarterTurns = 0,
    CameraPickerTextDelegate textDelegate,
    ResolutionPreset resolutionPreset = ResolutionPreset.max,
  }) async {
    if (isAllowRecording != true && isOnlyAllowRecording == true) {
      throw ArgumentError('Recording mode error.');
    }
    if (resolutionPreset == null) {
      throw ArgumentError('Resolution preset must not be null.');
    }
    final AssetEntity result = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<AssetEntity>(
      SlidePageTransitionBuilder<AssetEntity>(
        builder: CameraPicker(
          isAllowRecording: isAllowRecording,
          isOnlyAllowRecording: isOnlyAllowRecording,
          enableAudio: enableAudio,
          maximumRecordingDuration: maximumRecordingDuration,
          theme: theme,
          cameraQuarterTurns: cameraQuarterTurns,
          textDelegate: textDelegate,
          resolutionPreset: resolutionPreset,
        ),
        transitionCurve: Curves.easeIn,
        transitionDuration: _kRouteDuration,
      ),
    );
    return result;
  }

  /// Build a dark theme according to the theme color.
  /// 通过主题色构建一个默认的暗黑主题
  static ThemeData themeData(Color themeColor) => ThemeData.dark().copyWith(
        buttonColor: themeColor,
        brightness: Brightness.dark,
        primaryColor: Colors.grey[900],
        primaryColorBrightness: Brightness.dark,
        primaryColorLight: Colors.grey[900],
        primaryColorDark: Colors.grey[900],
        accentColor: themeColor,
        accentColorBrightness: Brightness.dark,
        canvasColor: Colors.grey[850],
        scaffoldBackgroundColor: Colors.grey[900],
        bottomAppBarColor: Colors.grey[900],
        cardColor: Colors.grey[900],
        highlightColor: Colors.transparent,
        toggleableActiveColor: themeColor,
        cursorColor: themeColor,
        textSelectionColor: themeColor.withAlpha(100),
        textSelectionHandleColor: themeColor,
        indicatorColor: themeColor,
        appBarTheme: const AppBarTheme(
          brightness: Brightness.dark,
          elevation: 0,
        ),
        colorScheme: ColorScheme(
          primary: Colors.grey[900],
          primaryVariant: Colors.grey[900],
          secondary: themeColor,
          secondaryVariant: themeColor,
          background: Colors.grey[900],
          surface: Colors.grey[900],
          brightness: Brightness.dark,
          error: const Color(0xffcf6679),
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: Colors.white,
          onBackground: Colors.white,
          onError: Colors.black,
        ),
      );

  @override
  CameraPickerState createState() => CameraPickerState();
}

class CameraPickerState extends State<CameraPicker>
    with WidgetsBindingObserver {
  /// The [Duration] for record detection. (200ms)
  /// 检测是否开始录制的时长 (200毫秒)
  final Duration recordDetectDuration = const Duration(milliseconds: 200);

  /// The last exposure point offset on the screen.
  /// 最后一次手动聚焦的点坐标
  final ValueNotifier<Offset> _lastExposurePoint = ValueNotifier<Offset>(null);

  /// The controller for the current camera.
  /// 当前相机实例的控制器
  CameraController controller;

  /// Available cameras.
  /// 可用的相机实例
  List<CameraDescription> cameras;

  /// 当前曝光值
  final ValueNotifier<double> _currentExposureOffset =
      ValueNotifier<double>(0.0);

  /// The maximum available value for exposure.
  /// 最大可用曝光值
  double _maxAvailableExposureOffset = 0.0;

  /// The minimum available value for exposure.
  /// 最小可用曝光值
  double _minAvailableExposureOffset = 0.0;

  /// The maximum available value for zooming.
  /// 最大可用缩放值
  double _maxAvailableZoom;

  /// The minimum available value for zooming.
  /// 最小可用缩放值
  double _minAvailableZoom;

  /// Counting pointers (number of user fingers on screen).
  /// 屏幕上的触摸点计数
  int _pointers = 0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;

  /// The index of the current cameras. Defaults to `0`.
  /// 当前相机的索引。默认为0
  int currentCameraIndex = 0;

  /// Whether the [shootingButton] should animate according to the gesture.
  /// 拍照按钮是否需要执行动画
  ///
  /// This happens when the [shootingButton] is being long pressed.
  /// It will animate for video recording state.
  ///
  /// 当长按拍照按钮时，会进入准备录制视频的状态，此时需要执行动画。
  bool isShootingButtonAnimate = false;

  /// The [Timer] for keep the [_lastExposurePoint] displays.
  /// 用于控制上次手动聚焦点显示的计时器
  Timer _exposurePointDisplayTimer;

  /// The [Timer] for record start detection.
  /// 用于检测是否开始录制的计时器
  ///
  /// When the [shootingButton] started animate, this [Timer] will start
  /// at the same time. When the time is more than [recordDetectDuration],
  /// which means we should start recoding, the timer finished.
  ///
  /// 当拍摄按钮开始执行动画时，定时器会同时启动。时长超过检测时长时，定时器完成。
  Timer _recordDetectTimer;

  /// The [Timer] for record countdown.
  /// 用于录制视频倒计时的计时器
  ///
  /// Stop record When the record time reached the [maximumRecordingDuration].
  /// However, if there's no limitation on record time, this will be useless.
  ///
  /// 当录像时间达到了最大时长，将通过定时器停止录像。
  /// 但如果录像时间没有限制，定时器将不会起作用。
  Timer _recordCountdownTimer;

  ////////////////////////////////////////////////////////////////////////////
  ////////////////////////////// Global Getters //////////////////////////////
  ////////////////////////////////////////////////////////////////////////////

  /// Whether the current [CameraDescription] initialized.
  /// 当前的相机实例是否已完成初始化
  bool get isInitialized =>
      controller != null && controller.value?.isInitialized == true;

  /// Whether the picker can record video. (A non-null wrapper)
  /// 选择器是否可以录像（非空包装）
  bool get isAllowRecording => widget.isAllowRecording ?? false;

  /// Whether the picker can only record video. (A non-null wrapper)
  /// 选择器是否仅可以录像（非空包装）
  bool get isOnlyAllowRecording => widget.isOnlyAllowRecording ?? false;

  /// Whether the picker should record audio. (A non-null wrapper)
  /// 选择器录制视频时，是否需要录制音频（非空包装）
  ///
  /// No audio integration required when it's only for camera.
  /// 在仅允许拍照时不需要启用音频
  bool get enableAudio => isAllowRecording && (widget.enableAudio ?? true);

  /// Getter for `widget.maximumRecordingDuration` .
  Duration get maximumRecordingDuration => widget.maximumRecordingDuration;

  /// Whether the recording restricted to a specific duration.
  /// 录像是否有限制的时长
  bool get isRecordingRestricted => maximumRecordingDuration != null;

  /// A getter to the current [CameraDescription].
  /// 获取当前相机实例
  CameraDescription get currentCamera => cameras?.elementAt(currentCameraIndex);

  /// If there's no theme provided from the user, use [CameraPicker.themeData] .
  /// 如果用户未提供主题，
  ThemeData _theme;

  /// Get [ThemeData] of the [AssetPicker] through [Constants.pickerKey].
  /// 通过常量全局 Key 获取当前选择器的主题
  ThemeData get theme => _theme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.removeObserver(this);
    _theme = widget.theme ?? CameraPicker.themeData(C.themeColor);

    // TODO(Alex): Currently hide status bar will cause the viewport shaking on Android.
    /// Hide system status bar automatically on iOS.
    /// 在iOS设备上自动隐藏状态栏
    if (Platform.isIOS) {
      SystemChrome.setEnabledSystemUIOverlays(<SystemUiOverlay>[]);
    }

    Future<void>.delayed(_kRouteDuration, () {
      if (mounted) {
        try {
          initCameras();
        } catch (e) {
          realDebugPrint('Error when initializing: $e');
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  void dispose() {
    if (Platform.isIOS) {
      SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
    }
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    _exposurePointDisplayTimer?.cancel();
    _recordDetectTimer?.cancel();
    _recordCountdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changed before we got the chance to initialize.
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (controller != null) {
        initCameras(currentCamera);
      }
    }
  }

  /// Adjust the proper scale type according to the [controller].
  /// 通过 [controller] 的预览大小，判断相机预览适用的缩放类型。
  _PreviewScaleType get _effectiveScaleType {
    assert(controller != null);
    final Size _size = controller.value.previewSize;
    final Size _scaledSize = _size * (Screens.widthPixels / _size.height);
    if (_scaledSize.width > Screens.heightPixels) {
      return _PreviewScaleType.width;
    } else if (_scaledSize.width < Screens.heightPixels) {
      return _PreviewScaleType.height;
    } else {
      return _PreviewScaleType.none;
    }
  }

  /// Initialize cameras instances.
  /// 初始化相机实例
  Future<void> initCameras([CameraDescription cameraDescription]) async {
    await controller?.dispose();

    /// When it's null, which means this is the first time initializing cameras.
    /// So cameras should fetch.
    if (cameraDescription == null) {
      cameras = await availableCameras();
    }

    /// After cameras fetched, judge again with the list is empty or not to
    /// ensure there is at least an available camera for use.
    if (cameraDescription == null && (cameras?.isEmpty ?? true)) {
      realDebugPrint('No cameras found.');
      return;
    }

    /// Initialize the controller with the given resolution preset.
    controller = CameraController(
      cameraDescription ?? cameras[0],
      widget.resolutionPreset,
      enableAudio: enableAudio,
    )..addListener(() {
        safeSetState(() {});
        if (controller.value.hasError) {
          realDebugPrint('Camera error ${controller.value.errorDescription}');
        }
      });

    try {
      await controller.initialize();
      Future.wait<void>(<Future<dynamic>>[
        (() async => _maxAvailableExposureOffset =
            await controller.getMaxExposureOffset())(),
        (() async => _minAvailableExposureOffset =
            await controller.getMinExposureOffset())(),
        (() async => _maxAvailableZoom = await controller.getMaxZoomLevel())(),
        (() async => _minAvailableZoom = await controller.getMinZoomLevel())(),
      ]);
    } on CameraException catch (e) {
      realDebugPrint('CameraException: $e');
    } finally {
      safeSetState(() {});
    }
  }

  /// The method to switch cameras.
  /// 切换相机的方法
  ///
  /// Switch cameras in order. When the [currentCameraIndex] reached the length
  /// of cameras, start from the beginning.
  ///
  /// 按顺序切换相机。当达到相机数量时从头开始。
  void switchCameras() {
    ++currentCameraIndex;
    if (currentCameraIndex == cameras.length) {
      currentCameraIndex = 0;
    }
    initCameras(currentCamera);
  }

  /// The method to switch between flash modes.
  /// 切换闪光灯模式的方法
  Future<void> switchFlashesMode() async {
    switch (controller.value.flashMode) {
      case FlashMode.off:
        await controller.setFlashMode(FlashMode.auto);
        break;
      case FlashMode.auto:
        await controller.setFlashMode(FlashMode.always);
        break;
      case FlashMode.always:
      case FlashMode.torch:
        await controller.setFlashMode(FlashMode.off);
        break;
    }
  }

  /// Handle when the scale gesture start.
  /// 处理缩放开始的手势
  void _handleScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  /// Handle when the scale details is updating.
  /// 处理缩放更新
  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (_pointers != 2) {
      return;
    }

    _currentZoom = (_baseZoom * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom)
        .toDouble();

    await controller.setZoomLevel(_currentZoom);
  }

  /// Use the [details] point to set exposure and focus.
  /// 通过点击点的 [details] 设置曝光和对焦。
  void setExposurePoint(TapDownDetails details) {
    _lastExposurePoint.value = Offset(
      details.localPosition.dx,
      details.localPosition.dy,
    );
    _exposurePointDisplayTimer?.cancel();
    _exposurePointDisplayTimer = Timer(const Duration(seconds: 5), () {
      _lastExposurePoint.value = null;
    });
    controller.setExposurePoint(
      _lastExposurePoint.value.scale(1 / Screens.width, 1 / Screens.height),
    );
    realDebugPrint(
      'Setting new exposure point ('
      'x: ${_lastExposurePoint.value.dx}, '
      'y: ${_lastExposurePoint.value.dy}'
      ')',
    );
  }

  /// The method to take a picture.
  /// 拍照方法
  ///
  /// The picture will only taken when [isInitialized], and the camera is not
  /// taking pictures.
  ///
  /// 仅当初始化成功且相机未在拍照时拍照。
  Future<void> takePicture() async {
    if (controller.value.isInitialized && !controller.value.isTakingPicture) {
      try {
        final AssetEntity entity = await CameraPickerViewer.pushToViewer(
          context,
          pickerState: this,
          pickerType: CameraPickerViewType.image,
          previewXFile: await controller.takePicture(),
          theme: theme,
        );
        if (entity != null) {
          Navigator.of(context).pop(entity);
        } else {
          safeSetState(() {});
        }
      } catch (e) {
        realDebugPrint('Error when taking pictures: $e');
      }
    }
  }

  /// When the [shootingButton]'s `onLongPress` called, the [_recordDetectTimer]
  /// will be initialized to achieve press time detection. If the duration
  /// reached to same as [recordDetectDuration], and the timer still active,
  /// start recording video.
  ///
  /// 当 [shootingButton] 触发了长按，初始化一个定时器来实现时间检测。如果长按时间
  /// 达到了 [recordDetectDuration] 且定时器未被销毁，则开始录制视频。
  void recordDetection() {
    _recordDetectTimer = Timer(recordDetectDuration, () {
      startRecordingVideo();
      safeSetState(() {});
    });
    setState(() {
      isShootingButtonAnimate = true;
    });
  }

  /// This will be given to the [Listener] in the [shootingButton]. When it's
  /// called, which means no more pressing on the button, cancel the timer and
  /// reset the status.
  ///
  /// 这个方法会赋值给 [shootingButton] 中的 [Listener]。当按钮释放了点击后，定时器
  /// 将被取消，并且状态会重置。
  void recordDetectionCancel(PointerUpEvent event) {
    _recordDetectTimer?.cancel();
    if (controller.value.isRecordingVideo) {
      stopRecordingVideo();
      safeSetState(() {});
    }
    if (isShootingButtonAnimate) {
      safeSetState(() {
        isShootingButtonAnimate = false;
      });
    }
  }

  /// Set record file path and start recording.
  /// 设置拍摄文件路径并开始录制视频
  void startRecordingVideo() {
    if (!controller.value.isRecordingVideo) {
      controller.startVideoRecording().then((dynamic _) {
        safeSetState(() {});
        if (isRecordingRestricted) {
          _recordCountdownTimer = Timer(maximumRecordingDuration, () {
            stopRecordingVideo();
          });
        }
      }).catchError((dynamic e) {
        realDebugPrint('Error when recording video: $e');
        if (controller.value.isRecordingVideo) {
          controller.stopVideoRecording().catchError((dynamic e) {
            realDebugPrint('Error when stop recording video: $e');
          });
        }
      });
    }
  }

  /// Stop the recording process.
  /// 停止录制视频
  Future<void> stopRecordingVideo() async {
    if (controller.value.isRecordingVideo) {
      controller.stopVideoRecording().then((XFile file) async {
        final AssetEntity entity = await CameraPickerViewer.pushToViewer(
          context,
          pickerState: this,
          pickerType: CameraPickerViewType.video,
          previewXFile: file,
          theme: theme,
        );
        if (entity != null) {
          Navigator.of(context).pop(entity);
        } else {
          safeSetState(() {});
        }
      }).catchError((dynamic e) {
        realDebugPrint('Error when stop recording video: $e');
      }).whenComplete(() {
        isShootingButtonAnimate = false;
      });
    }
  }

  /// Settings action section widget.
  /// 设置操作区
  ///
  /// This displayed at the top of the screen.
  /// 该区域显示在屏幕上方。
  Widget get settingsAction {
    if (!isInitialized) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        children: <Widget>[const Spacer(), switchFlashesButton],
      ),
    );
  }

  /// The button to switch flash modes.
  /// 切换闪光灯模式的按钮
  Widget get switchFlashesButton {
    IconData icon;
    switch (controller.value.flashMode) {
      case FlashMode.off:
        icon = Icons.flash_off;
        break;
      case FlashMode.auto:
        icon = Icons.flash_auto;
        break;
      case FlashMode.always:
      case FlashMode.torch:
        icon = Icons.flash_on;
        break;
    }
    return IconButton(
      onPressed: switchFlashesMode,
      icon: Icon(icon, size: 24),
    );
  }

  /// Text widget for shooting tips.
  /// 拍摄的提示文字
  Widget get tipsTextWidget {
    if (!isInitialized) {
      return const SizedBox.shrink();
    }
    return AnimatedOpacity(
      duration: recordDetectDuration,
      opacity: controller.value.isRecordingVideo ? 0.0 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 20.0,
        ),
        child: Text(
          Constants.textDelegate.shootingTips,
          style: const TextStyle(fontSize: 15.0),
        ),
      ),
    );
  }

  /// Shooting action section widget.
  /// 拍照操作区
  ///
  /// This displayed at the top of the screen.
  /// 该区域显示在屏幕下方。
  Widget get shootingActions {
    return SizedBox(
      height: Screens.width / 3.5,
      child: Row(
        children: <Widget>[
          Expanded(
            child: controller?.value?.isRecordingVideo == false
                ? Center(child: backButton)
                : const SizedBox.shrink(),
          ),
          Expanded(child: Center(child: shootingButton)),
          const Spacer(),
        ],
      ),
    );
  }

  /// The back button near to the [shootingButton].
  /// 靠近拍照键的返回键
  Widget get backButton {
    return InkWell(
      borderRadius: maxBorderRadius,
      onTap: Navigator.of(context).pop,
      child: Container(
        margin: const EdgeInsets.all(10.0),
        width: Screens.width / 15,
        height: Screens.width / 15,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(
            Icons.keyboard_arrow_down,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  /// The shooting button.
  /// 拍照按钮
  Widget get shootingButton {
    final Size outerSize = Size.square(Screens.width / 3.5);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerUp: isAllowRecording ? recordDetectionCancel : null,
      child: InkWell(
        borderRadius: maxBorderRadius,
        onTap: !isOnlyAllowRecording ? takePicture : null,
        onLongPress: isAllowRecording ? recordDetection : null,
        child: SizedBox.fromSize(
          size: outerSize,
          child: Stack(
            children: <Widget>[
              Center(
                child: AnimatedContainer(
                  duration: kThemeChangeDuration,
                  width: isShootingButtonAnimate
                      ? outerSize.width
                      : (Screens.width / 5),
                  height: isShootingButtonAnimate
                      ? outerSize.height
                      : (Screens.width / 5),
                  padding: EdgeInsets.all(
                    Screens.width / (isShootingButtonAnimate ? 10 : 35),
                  ),
                  decoration: BoxDecoration(
                    color: theme.canvasColor.withOpacity(0.95),
                    shape: BoxShape.circle,
                  ),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              _initializeWrapper(
                isInitialized: () =>
                    controller?.value?.isRecordingVideo == true &&
                    isRecordingRestricted,
                child: CircleProgressBar(
                  duration: maximumRecordingDuration,
                  outerRadius: outerSize.width,
                  ringsWidth: 2.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The area widget for the last exposure point that user manually set.
  /// 用户手动设置的曝光点的区域显示
  Widget get _focusingAreaWidget {
    Widget _buildFromPoint(Offset point) {
      final double _width = Screens.width / 5;

      final double _effectiveLeft = math.min(
        Screens.width - _width,
        math.max(0, point.dx - _width / 2),
      );
      final double _effectiveTop = math.min(
        Screens.height - _width,
        math.max(0, point.dy - _width / 2),
      );

      return Positioned(
        left: _effectiveLeft,
        top: _effectiveTop,
        width: _width,
        height: _width,
        child: ExposurePointWidget(key: ValueKey<int>(currentTimeStamp)),
      );
    }

    return ValueListenableBuilder<Offset>(
      valueListenable: _lastExposurePoint,
      builder: (_, Offset point, __) {
        if (point == null) {
          return const SizedBox.shrink();
        }
        return _buildFromPoint(point);
      },
    );
  }

  /// The [GestureDetector] widget for setting exposure poing manually.
  /// 用于手动设置曝光点的 [GestureDetector]
  Widget _exposureDetectorWidget(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTapDown: setExposurePoint,
        behavior: HitTestBehavior.translucent,
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _cameraPreview(BuildContext context) {
    assert(controller != null);

    Widget _preview = Listener(
      onPointerDown: (_) => _pointers++,
      onPointerUp: (_) => _pointers--,
      child: GestureDetector(
        onScaleStart: _handleScaleStart,
        onScaleUpdate: _handleScaleUpdate,
        onDoubleTap: switchCameras,
        child: CameraPreview(controller),
      ),
    );

    if (_effectiveScaleType == _PreviewScaleType.none) {
      return _preview;
    }

    double _width;
    double _height;
    switch (_effectiveScaleType) {
      case _PreviewScaleType.width:
        _width = Screens.width;
        _height = Screens.width / controller.value.aspectRatio;
        break;
      case _PreviewScaleType.height:
        _width = Screens.height * controller.value.aspectRatio;
        _height = Screens.height;
        break;
      default:
        _width = Screens.width;
        _height = Screens.height;
        break;
    }
    final double _offsetHorizontal = (_width - Screens.width).abs() / -2;
    final double _offsetVertical = (_height - Screens.height).abs() / -2;
    _preview = Stack(
      children: <Widget>[
        Positioned(
          left: _offsetHorizontal,
          right: _offsetHorizontal,
          top: _offsetVertical,
          bottom: _offsetVertical,
          child: _preview,
        ),
      ],
    );
    return _preview;
  }

  Widget _initializeWrapper({
    @required Widget child,
    bool Function() isInitialized,
  }) {
    assert(child != null);
    return AnimatedSwitcher(
      duration: kThemeAnimationDuration,
      child: isInitialized?.call() ?? this.isInitialized
          ? child
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: theme,
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: <Widget>[
            if (isInitialized)
              RotatedBox(
                quarterTurns: widget.cameraQuarterTurns ?? 0,
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: _cameraPreview(context)),
                      _focusingAreaWidget,
                    ],
                  ),
                ),
              ),
            _exposureDetectorWidget(context),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Column(
                  children: <Widget>[
                    settingsAction,
                    const Spacer(),
                    tipsTextWidget,
                    shootingActions,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PreviewScaleType { none, width, height }
