import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorService {
  FaceDetectorService()
      : _previewDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: false,
            enableLandmarks: false,
            performanceMode: FaceDetectorMode.accurate,
          ),
        ),
        _captureDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: true,
            enableLandmarks: true,
            performanceMode: FaceDetectorMode.accurate,
          ),
        );

  final FaceDetector _previewDetector;
  final FaceDetector _captureDetector;

  Future<Rect?> detectPrimaryFaceNormalized(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) async {
    final rotationDegrees = _resolveRotationDegrees(camera, deviceOrientation);
    final inputImage = _toInputImage(image, camera, deviceOrientation);
    final faces = await _previewDetector.processImage(inputImage);
    if (faces.isEmpty) return null;

    final face = _selectLargestFace(faces);

    return _mapRectToPreview(
      face.boundingBox,
      image.width.toDouble(),
      image.height.toDouble(),
      rotationDegrees,
      camera.lensDirection == CameraLensDirection.front,
    );
  }

  Future<void> close() async {
    await _previewDetector.close();
    await _captureDetector.close();
  }

  Future<DetectedFace?> detectPrimaryFaceFromFile(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _captureDetector.processImage(inputImage);
    if (faces.isEmpty) return null;

    final face = _selectLargestFace(faces);
    return DetectedFace(
      boundingBox: face.boundingBox,
      headEulerAngleX: face.headEulerAngleX,
      headEulerAngleY: face.headEulerAngleY,
      headEulerAngleZ: face.headEulerAngleZ,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      leftEye: _toOffset(face.landmarks[FaceLandmarkType.leftEye]),
      rightEye: _toOffset(face.landmarks[FaceLandmarkType.rightEye]),
      noseBase: _toOffset(face.landmarks[FaceLandmarkType.noseBase]),
      mouthLeft: _toOffset(face.landmarks[FaceLandmarkType.leftMouth]),
      mouthRight: _toOffset(face.landmarks[FaceLandmarkType.rightMouth]),
      mouthBottom: _toOffset(face.landmarks[FaceLandmarkType.bottomMouth]),
      faceContour: face.contours[FaceContourType.face]?.points
              .map((point) => Offset(point.x.toDouble(), point.y.toDouble()))
              .toList(growable: false) ??
          const [],
    );
  }

  Offset? _toOffset(FaceLandmark? landmark) {
    if (landmark == null) {
      return null;
    }

    return Offset(
      landmark.position.x.toDouble(),
      landmark.position.y.toDouble(),
    );
  }

  InputImage _toInputImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    final rotation = _resolveRotation(camera, deviceOrientation);

    if (format == null || rotation == null) {
      throw Exception('Formato ou rotação da imagem não suportado.');
    }

    if (Platform.isAndroid &&
        (format != InputImageFormat.nv21 || image.planes.length != 1)) {
      throw Exception(
        'Formato de câmera inválido no Android. Use NV21 com 1 plane.',
      );
    }

    if (Platform.isIOS &&
        (format != InputImageFormat.bgra8888 || image.planes.length != 1)) {
      throw Exception(
        'Formato de câmera inválido no iOS. Use BGRA8888 com 1 plane.',
      );
    }

    final plane = image.planes.first;

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: metadata,
    );
  }

  Face _selectLargestFace(List<Face> faces) {
    return faces.reduce((a, b) {
      final areaA = a.boundingBox.width * a.boundingBox.height;
      final areaB = b.boundingBox.width * b.boundingBox.height;
      return areaA >= areaB ? a : b;
    });
  }

  Rect? _mapRectToPreview(
    Rect rect,
    double imageWidth,
    double imageHeight,
    int rotationDegrees,
    bool mirrorHorizontally,
  ) {
    final points = [
      _transformPoint(
        rect.left,
        rect.top,
        imageWidth,
        imageHeight,
        rotationDegrees,
      ),
      _transformPoint(
        rect.right,
        rect.top,
        imageWidth,
        imageHeight,
        rotationDegrees,
      ),
      _transformPoint(
        rect.left,
        rect.bottom,
        imageWidth,
        imageHeight,
        rotationDegrees,
      ),
      _transformPoint(
        rect.right,
        rect.bottom,
        imageWidth,
        imageHeight,
        rotationDegrees,
      ),
    ];

    final rotatedWidth = rotationDegrees == 90 || rotationDegrees == 270
        ? imageHeight
        : imageWidth;
    final rotatedHeight = rotationDegrees == 90 || rotationDegrees == 270
        ? imageWidth
        : imageHeight;

    final normalizedPoints = points.map((point) {
      var dx = point.dx / rotatedWidth;
      final dy = point.dy / rotatedHeight;

      if (mirrorHorizontally) {
        dx = 1 - dx;
      }

      return Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
    }).toList(growable: false);

    final xs = normalizedPoints.map((point) => point.dx);
    final ys = normalizedPoints.map((point) => point.dy);

    final left = xs.reduce((a, b) => a < b ? a : b);
    final right = xs.reduce((a, b) => a > b ? a : b);
    final top = ys.reduce((a, b) => a < b ? a : b);
    final bottom = ys.reduce((a, b) => a > b ? a : b);

    if (right <= left || bottom <= top) {
      return null;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Offset _transformPoint(
    double x,
    double y,
    double imageWidth,
    double imageHeight,
    int rotationDegrees,
  ) {
    switch (rotationDegrees) {
      case 90:
        return Offset(y, imageWidth - x);
      case 180:
        return Offset(imageWidth - x, imageHeight - y);
      case 270:
        return Offset(imageHeight - y, x);
      default:
        return Offset(x, y);
    }
  }

  InputImageRotation? _resolveRotation(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    return InputImageRotationValue.fromRawValue(
      _resolveRotationDegrees(camera, deviceOrientation),
    );
  }

  int _resolveRotationDegrees(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    if (Platform.isIOS) {
      return camera.sensorOrientation;
    }

    const orientations = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    var rotationCompensation = orientations[deviceOrientation] ?? 0;

    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation =
          (camera.sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (camera.sensorOrientation - rotationCompensation + 360) % 360;
    }

    return rotationCompensation;
  }
}

class DetectedFace {
  const DetectedFace({
    required this.boundingBox,
    required this.faceContour,
    this.headEulerAngleX,
    this.headEulerAngleY,
    this.headEulerAngleZ,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.leftEye,
    this.rightEye,
    this.noseBase,
    this.mouthLeft,
    this.mouthRight,
    this.mouthBottom,
  });

  final Rect boundingBox;
  final List<Offset> faceContour;
  final double? headEulerAngleX;
  final double? headEulerAngleY;
  final double? headEulerAngleZ;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final Offset? leftEye;
  final Offset? rightEye;
  final Offset? noseBase;
  final Offset? mouthLeft;
  final Offset? mouthRight;
  final Offset? mouthBottom;

  DetectedFace copyWith({
    Rect? boundingBox,
    List<Offset>? faceContour,
    double? headEulerAngleX,
    double? headEulerAngleY,
    double? headEulerAngleZ,
    double? leftEyeOpenProbability,
    double? rightEyeOpenProbability,
    Offset? leftEye,
    Offset? rightEye,
    Offset? noseBase,
    Offset? mouthLeft,
    Offset? mouthRight,
    Offset? mouthBottom,
  }) {
    return DetectedFace(
      boundingBox: boundingBox ?? this.boundingBox,
      faceContour: faceContour ?? this.faceContour,
      headEulerAngleX: headEulerAngleX ?? this.headEulerAngleX,
      headEulerAngleY: headEulerAngleY ?? this.headEulerAngleY,
      headEulerAngleZ: headEulerAngleZ ?? this.headEulerAngleZ,
      leftEyeOpenProbability:
          leftEyeOpenProbability ?? this.leftEyeOpenProbability,
      rightEyeOpenProbability:
          rightEyeOpenProbability ?? this.rightEyeOpenProbability,
      leftEye: leftEye ?? this.leftEye,
      rightEye: rightEye ?? this.rightEye,
      noseBase: noseBase ?? this.noseBase,
      mouthLeft: mouthLeft ?? this.mouthLeft,
      mouthRight: mouthRight ?? this.mouthRight,
      mouthBottom: mouthBottom ?? this.mouthBottom,
    );
  }
}
