// ignore_for_file: must_be_immutable

library camera_filters;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:camera_filters/src/edit_image_screen.dart';
import 'package:camera_filters/src/filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_image/flutter_native_image.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as imglib;

class CameraScreenPlugin extends StatefulWidget {
  /// this function will return the path of edited picture
  Function(dynamic)? onDone;

  /// this function will return the path of edited video
  Function(dynamic)? onVideoDone;

  /// list of filters
  List<Color>? filters;

  bool applyFilters;

  /// notify color to change
  ValueNotifier<Color>? filterColor;

  ///circular gradient color
  List<Color>? gradientColors;

  /// profile widget if you want to use profile widget on camera
  Widget? profileIconWidget;

  /// profile widget if you want to use profile widget on camera
  Widget? sendButtonWidget;

  CameraScreenPlugin(
      {Key? key,
      this.onDone,
      this.onVideoDone,
      this.filters,
      this.profileIconWidget,
      this.applyFilters = true,
      this.gradientColors,
      this.sendButtonWidget,
      this.filterColor})
      : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreenPlugin>
    with TickerProviderStateMixin {
  ///animation controller for circular progress indicator
  late AnimationController controller;

  /// Camera Controller
  late CameraController _controller;

  /// initializer of controller
  Future<void>? _initializeControllerFuture;

  /// local storage for mobile
  GetStorage sp = GetStorage();

  /// flash mode changer
  ValueNotifier<int> flashCount = ValueNotifier(0);

  /// flash mode changer
  ValueNotifier<String> time = ValueNotifier("");

  /// condition check that picture is taken or not
  bool capture = false;

  ///Timer initialize
  Timer? t;

  /// camera list, this list will tell user that he/she is on front camera or back
  List<CameraDescription> cameras = [];

  /// bool to change picture to video or video to picture
  ValueNotifier<bool> cameraChange = ValueNotifier(false);

  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentZoomLevel = 1.0;

  AnimationController? _rotationController;
  double _rotation = 0;
  double _scale = 0.85;

  void _updateRotation() {
    _rotation = (_rotationController!.value * 2) * pi;
    print("_rotation is $_rotation");
  }

  void _updateScale() {
    _scale = (controller.value * 0.2) + 0.85;
    print("scale is $_scale");
  }

  ///list of filters color
  final _filters = [
    Colors.transparent,
    ...List.generate(
      Colors.primaries.length,
      (index) => Colors.primaries[(index) % Colors.primaries.length],
    )
  ];

  ///filter color notifier
  final _filterColor = ValueNotifier<Color>(Colors.transparent);

  ///filter color change function
  void _onFilterChanged(Color value) {
    widget.filterColor == null
        ? _filterColor.value = value
        : widget.filterColor!.value = value;
  }

  @override
  void initState() {
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3500),
    )..addListener(() async {
        setState(_updateScale);
      });
    _rotationController =
        AnimationController(vsync: this, duration: Duration(seconds: 5))
          ..addListener(() {
            setState(_updateRotation);
            if (_rotation > 5) {
              _rotationController!.reset();
              _rotationController!.forward();
            }
          });

    super.initState();
    if (sp.read("flashCount") != null) {
      flashCount.value = sp.read("flashCount");
    }
    if (widget.filterColor != null) {
      widget.filterColor = ValueNotifier<Color>(Colors.transparent);
    }
    initCamera();
  }

  ///timer Widget
  timer() {
    t = Timer.periodic(Duration(seconds: 1), (timer) {
      time.value = timer.tick.toString();
    });
  }

  ///timer function
  String formatHHMMSS(int seconds) {
    int hours = (seconds / 3600).truncate();
    seconds = (seconds % 3600).truncate();
    int minutes = (seconds / 60).truncate();

    String hoursStr = (hours).toString().padLeft(2, '0');
    String minutesStr = (minutes).toString().padLeft(2, '0');
    String secondsStr = (seconds % 60).toString().padLeft(2, '0');

    if (hours == 0) {
      return "$minutesStr:$secondsStr";
    }

    return "$hoursStr:$minutesStr:$secondsStr";
  }

  ///this function will initialize camera
  initCamera() async {
    WidgetsFlutterBinding.ensureInitialized();

    /// this condition check that camera is available on your device
    cameras = await availableCameras();

    ///put camera in camera controller
    _controller = CameraController(
      cameras[0],
      ResolutionPreset.veryHigh,
    );

    await _controller.initialize();

    _initializeControllerFuture =
        Future.delayed(const Duration(seconds: 1), () {});

    Future.delayed(Duration(seconds: 2), () {
      _controller.setFlashMode(FlashMode.off);
    });

    await Future.wait([
      _controller.getMaxZoomLevel().then((value) => _maxAvailableZoom = value),
      _controller.getMinZoomLevel().then((value) => _minAvailableZoom = value),
    ]);

    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: _initializeControllerFuture == null
          ? Center(child: CircularProgressIndicator())
          : GestureDetector(
              onScaleUpdate: (details) async {
                print(details.scale);

                if (details.scale == 1.0 ||
                    _currentZoomLevel * details.scale < _minAvailableZoom ||
                    _currentZoomLevel * details.scale > _maxAvailableZoom) {
                  return;
                }

                setState(() {
                  if (details.scale > 1) {
                    _currentZoomLevel = _currentZoomLevel +
                        _minAvailableZoom *
                            (_minAvailableZoom / _maxAvailableZoom);
                  } else {
                    _currentZoomLevel = _currentZoomLevel -
                        _minAvailableZoom *
                            (_minAvailableZoom / _maxAvailableZoom);
                  }
                  // _currentZoomLevel *= details.scale;
                });
                await _controller.setZoomLevel(_currentZoomLevel);
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FutureBuilder<void>(
                      future: _initializeControllerFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done) {
                          /// If the Future is complete, display the preview.
                          return ValueListenableBuilder(
                              valueListenable: cameraChange,
                              builder: (context, value, Widget? c) {
                                return cameraChange.value == false
                                    ? ValueListenableBuilder(
                                        valueListenable:
                                            widget.filterColor ?? _filterColor,
                                        builder: (context, value, child) {
                                          return ColorFiltered(
                                            colorFilter: ColorFilter.mode(
                                                widget.filterColor == null
                                                    ? _filterColor.value
                                                    : widget.filterColor!.value,
                                                BlendMode.softLight),
                                            child: CameraPreview(_controller),
                                          );
                                        })
                                    : CameraPreview(_controller);
                              });
                        } else {
                          /// Otherwise, display a loading indicator.
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                      },
                    ),
                  ),
                  Positioned(
                    top: 50.0,
                    right: 10.0,
                    child: ValueListenableBuilder(
                        valueListenable: cameraChange,
                        builder: (context, value, Widget? c) {
                          return cameraChange.value == false
                              ? Container()
                              : Text(
                                  time.value == ""
                                      ? ""
                                      : formatHHMMSS(int.parse(time.value)),
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                );
                        }),
                  ),
                  Positioned(
                    left: 0.0,
                    right: 0.0,
                    bottom: 0.0,
                    child: ValueListenableBuilder(
                        valueListenable: cameraChange,
                        builder: (context, value, Widget? c) {
                          return _buildFilterSelector();
                        }),
                  ),
                  Positioned(
                    right: 10.0,
                    top: 30.0,
                    child: widget.profileIconWidget ?? Container(),
                  ),
                  Positioned(
                    left: 10.0,
                    top: 30.0,
                    child: Row(
                      children: [
                        /// icon for flash modes
                        IconButton(
                          onPressed: () {
                            /// if flash count is zero flash will off
                            if (flashCount.value == 0) {
                              flashCount.value = 1;
                              sp.write("flashCount", 1);
                              _controller.setFlashMode(FlashMode.torch);

                              /// if flash count is one flash will on
                            } else if (flashCount.value == 1) {
                              flashCount.value = 2;
                              sp.write("flashCount", 2);
                              _controller.setFlashMode(FlashMode.auto);
                            }

                            /// if flash count is two flash will auto
                            else {
                              flashCount.value = 0;
                              sp.write("flashCount", 0);
                              _controller.setFlashMode(FlashMode.off);
                            }
                          },
                          icon: ValueListenableBuilder(
                              valueListenable: flashCount,
                              builder: (context, value, Widget? c) {
                                return Icon(
                                  flashCount.value == 0
                                      ? Icons.flash_off
                                      : flashCount.value == 1
                                          ? Icons.flash_on
                                          : Icons.flash_auto,
                                  color: Colors.white,
                                );
                              }),
                        ),
                        SizedBox(
                          width: 5,
                        ),

                        /// camera change to front or back
                        IconButton(
                          icon: Icon(
                            Icons.cameraswitch,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            if (_controller.description.lensDirection ==
                                CameraLensDirection.front) {
                              final CameraDescription selectedCamera =
                                  cameras[0];
                              _initCameraController(selectedCamera);
                            } else {
                              final CameraDescription selectedCamera =
                                  cameras[1];
                              _initCameraController(selectedCamera);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RotatedBox(
                            quarterTurns: 3,
                            child: Container(
                              height: 30,
                              child: Slider(
                                value: _currentZoomLevel,
                                min: _minAvailableZoom,
                                max: _maxAvailableZoom,
                                activeColor: Colors.white,
                                inactiveColor: Colors.white30,
                                onChanged: (value) async {
                                  setState(() {
                                    _currentZoomLevel = value;
                                  });
                                  await _controller.setZoomLevel(value);
                                },
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  _currentZoomLevel.toStringAsFixed(1) + 'x',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
    );
  }

  flashCheck() {
    if (sp.read("flashCount") == 1) {
      _controller.setFlashMode(FlashMode.off);
    }
  }

  /// function will call when user tap on picture button
  void onTakePictureButtonPressed(context) {
    takePicture(context).then((String? filePath) async {
      if (_controller.value.isInitialized) {
        if (filePath != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => EditImageScreen(
                      path: filePath,
                      applyFilters: widget.applyFilters,
                      sendButtonWidget: widget.sendButtonWidget,
                      filter: ColorFilter.mode(
                          widget.filterColor == null
                              ? _filterColor.value
                              : widget.filterColor!.value,
                          BlendMode.softLight),
                      onDone: widget.onDone,
                    )),
          ).then((value) {
            if (sp.read("flashCount") == 1) {
              _controller.setFlashMode(FlashMode.torch);
            }
          });
          flashCheck();
        }
      }
    });
  }

  Future<String> compressFile(File file, {takePicture = false}) async {
    final List<int> imageBytes = await file.readAsBytes();

    imglib.Image? originalImage = imglib.decodeImage(imageBytes);

    if (_controller.description.lensDirection == CameraLensDirection.front) {
      originalImage = imglib.flipHorizontal(originalImage!);
    }

    final File files = File(file.path);

    final File fixedFile = await files.writeAsBytes(
      imglib.encodeJpg(originalImage!),
      flush: true,
    );
    return fixedFile.path;
  }

  /// function will call when user take picture
  Future<String> takePicture(context) async {
    if (!_controller.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: camera is not initialized')));
    }
    final String dirPath = getTemporaryDirectory().toString();
    String filePath = '$dirPath/${timestamp()}.jpg';

    try {
      await _controller.takePicture().then((file) async {
        filePath = await compressFile(File(file.path));
      });
    } on CameraException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: ${e.description}')));
    }
    return filePath;
  }

  /// timestamp for image creation date
  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  /// widget will build the filter selector
  Widget _buildFilterSelector() {
    return FilterSelector(
      onFilterChanged: _onFilterChanged,
      filters: widget.applyFilters == false ? [] : widget.filters ?? _filters,
      onTap: () {
        if (capture == false) {
          capture = true;
          onTakePictureButtonPressed(context);
          Future.delayed(Duration(seconds: 3), () {
            capture = false;
          });
        }
      },
    );
  }

  /// function initialize camera controller
  Future _initCameraController(CameraDescription cameraDescription) async {
    /// 1
    _controller =
        CameraController(cameraDescription, ResolutionPreset.veryHigh);

    /// 2
    /// If the controller is updated then update the UI.
    _controller.addListener(() {
      /// 3
      if (_controller.value.hasError) {
        print('Camera error ${_controller.value.errorDescription}');
      }
    });

    /// 4
    try {
      await _controller.initialize();
    } on CameraException catch (e) {
      print(e);
    }
    setState(() {});
  }

  ///video recording function
  // Widget videoRecordingWidget() {
  //   return Padding(
  //     padding: const EdgeInsets.only(bottom: 10),
  //     child: GestureDetector(
  //       onLongPress: () async {
  //         // if(controller.value ){

  //         await _controller.prepareForVideoRecording();
  //         await _controller.startVideoRecording();
  //         timer();
  //         controller.forward();
  //         _rotationController!.forward();
  //         // }
  //       },
  //       onLongPressEnd: (v) async {
  //         t!.cancel();
  //         time.value = "";
  //         controller.reset();
  //         _rotationController!.reset();
  //         final file = await _controller.stopVideoRecording();
  //         flashCheck();
  //         Navigator.push(
  //           context,
  //           MaterialPageRoute(
  //               builder: (context) => VideoPlayer(
  //                     file.path,
  //                     applyFilters: widget.applyFilters,
  //                     onVideoDone: widget.onVideoDone,
  //                     sendButtonWidget: widget.sendButtonWidget,
  //                   )),
  //         ).then((value) {
  //           if (sp.read("flashCount") == 1) {
  //             _controller.setFlashMode(FlashMode.torch);
  //           }
  //         });
  //       },
  //       child: Container(
  //         width: 70,
  //         height: 70,
  //         child: ConstrainedBox(
  //           constraints: BoxConstraints(minWidth: 10, minHeight: 10),
  //           child: Stack(
  //             alignment: Alignment.bottomCenter,
  //             children: [
  //               if (_showWaves) ...[
  //                 Blob(
  //                     color: Color(0xff0092ff),
  //                     scale: _scale,
  //                     rotation: _rotation),
  //                 Blob(
  //                     color: Color(0xff4ac7b7),
  //                     scale: _scale,
  //                     rotation: _rotation * 2 - 30),
  //                 Blob(
  //                     color: Color(0xffa4a6f6),
  //                     scale: _scale,
  //                     rotation: _rotation * 3 - 45),
  //               ],
  //               Container(
  //                 constraints: BoxConstraints.expand(),
  //                 child: AnimatedSwitcher(
  //                   child: Container(
  //                     width: 70,
  //                     height: 70,
  //                     decoration: BoxDecoration(
  //                         color: Color(0xffd51820),
  //                         borderRadius: BorderRadius.circular(100)),
  //                   ),
  //                   duration: Duration(milliseconds: 300),
  //                 ),
  //                 decoration: BoxDecoration(
  //                   shape: BoxShape.circle,
  //                   color: Colors.white,
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ),
  //     ),
  //   );
  // }
}
