import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'face_detector_service.dart';

class FaceImageService {
  Future<img.Image> loadNormalizedImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Não foi possível decodificar a imagem capturada.');
    }

    return img.bakeOrientation(decoded);
  }

  Future<String> toBase64(String imagePath) async {
    final normalized = await loadNormalizedImage(imagePath);
    return imageToBase64(normalized);
  }

  String imageToBase64(img.Image image) {
    final normalizedBytes = img.encodeJpg(image, quality: 92);
    return base64Encode(normalizedBytes);
  }

  FaceCropResult cropFaceFromDetectedFace(
    img.Image image,
    DetectedFace face, {
    double targetFaceWidthFillRatio = 0.78,
    double targetFaceHeightFillRatio = 0.88,
  }) {
    final aligned = _alignFace(image, face);
    final alignedImage = aligned.image;
    final alignedFace = aligned.face;
    final contourRect = _resolveFaceRect(alignedFace);
    final faceWidth = contourRect.width;
    final faceHeight = contourRect.height;

    var side = math.max(
      faceWidth / targetFaceWidthFillRatio,
      faceHeight / targetFaceHeightFillRatio,
    );

    final eyeCenter = _average(alignedFace.leftEye, alignedFace.rightEye);
    final mouthCenter = _resolveMouthCenter(alignedFace);
    if (eyeCenter != null && mouthCenter != null) {
      final verticalSpan = (mouthCenter.dy - eyeCenter.dy).abs();
      side = math.max(side, verticalSpan * 2.05);
    }

    final centerX =
        alignedFace.noseBase?.dx ?? eyeCenter?.dx ?? contourRect.center.dx;
    final centerY = eyeCenter != null
        ? eyeCenter.dy + (side * 0.22)
        : contourRect.center.dy;

    final rawLeft = centerX - (side / 2);
    final rawTop = centerY - (side * 0.43);

    final left = rawLeft.clamp(0.0, math.max(0.0, alignedImage.width - side));
    final top = rawTop.clamp(0.0, math.max(0.0, alignedImage.height - side));

    final safeWidth = math
        .min(side, alignedImage.width - left)
        .clamp(1.0, alignedImage.width.toDouble());
    final safeHeight = math
        .min(side, alignedImage.height - top)
        .clamp(1.0, alignedImage.height.toDouble());

    final cropped = img.copyCrop(
      alignedImage,
      x: left.round(),
      y: top.round(),
      width: safeWidth.round(),
      height: safeHeight.round(),
    );

    final resized = img.copyResizeCropSquare(cropped, size: 112);
    final cropRect = Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      safeWidth.toDouble(),
      safeHeight.toDouble(),
    );
    final masked = _neutralizeBackground(
      resized,
      alignedFace,
      cropRect,
    );

    return FaceCropResult(
      image: masked,
      cropRect: cropRect,
    );
  }

  Rect _resolveFaceRect(DetectedFace face) {
    if (face.faceContour.isEmpty) {
      return face.boundingBox;
    }

    final xs = face.faceContour.map((point) => point.dx);
    final ys = face.faceContour.map((point) => point.dy);
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final contourRect = Rect.fromLTRB(minX, minY, maxX, maxY);

    final paddingX = contourRect.width * 0.08;
    final paddingY = contourRect.height * 0.08;
    return Rect.fromLTRB(
      contourRect.left - paddingX,
      contourRect.top - paddingY,
      contourRect.right + paddingX,
      contourRect.bottom + paddingY,
    );
  }

  Offset? _resolveMouthCenter(DetectedFace face) {
    if (face.mouthLeft != null && face.mouthRight != null) {
      return _average(face.mouthLeft, face.mouthRight);
    }

    return face.mouthBottom;
  }

  Offset? _average(Offset? a, Offset? b) {
    if (a == null || b == null) {
      return null;
    }

    return Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  }

  _AlignedFaceImage _alignFace(img.Image image, DetectedFace face) {
    final leftEye = face.leftEye;
    final rightEye = face.rightEye;
    if (leftEye == null || rightEye == null) {
      return _AlignedFaceImage(image: image, face: face);
    }

    final angleRadians =
        math.atan2(rightEye.dy - leftEye.dy, rightEye.dx - leftEye.dx);
    final angleDegrees = -(angleRadians * 180.0 / math.pi);
    if (angleDegrees.abs() < 0.5) {
      return _AlignedFaceImage(image: image, face: face);
    }

    final rotated = img.copyRotate(
      image,
      angle: angleDegrees,
      interpolation: img.Interpolation.linear,
    );

    Offset rotate(Offset point) => _rotatePoint(
          point,
          sourceWidth: image.width.toDouble(),
          sourceHeight: image.height.toDouble(),
          rotatedWidth: rotated.width.toDouble(),
          rotatedHeight: rotated.height.toDouble(),
          angleDegrees: angleDegrees,
        );

    final rotatedFace = face.copyWith(
      boundingBox: _rotateRect(
        face.boundingBox,
        sourceWidth: image.width.toDouble(),
        sourceHeight: image.height.toDouble(),
        rotatedWidth: rotated.width.toDouble(),
        rotatedHeight: rotated.height.toDouble(),
        angleDegrees: angleDegrees,
      ),
      faceContour: face.faceContour.map(rotate).toList(growable: false),
      leftEye: rotate(leftEye),
      rightEye: rotate(rightEye),
      noseBase: face.noseBase == null ? null : rotate(face.noseBase!),
      mouthLeft: face.mouthLeft == null ? null : rotate(face.mouthLeft!),
      mouthRight: face.mouthRight == null ? null : rotate(face.mouthRight!),
      mouthBottom: face.mouthBottom == null ? null : rotate(face.mouthBottom!),
    );

    return _AlignedFaceImage(
      image: rotated,
      face: rotatedFace,
    );
  }

  Offset _rotatePoint(
    Offset point, {
    required double sourceWidth,
    required double sourceHeight,
    required double rotatedWidth,
    required double rotatedHeight,
    required double angleDegrees,
  }) {
    final angleRadians = angleDegrees * math.pi / 180.0;
    final ca = math.cos(angleRadians);
    final sa = math.sin(angleRadians);
    final w2 = 0.5 * sourceWidth;
    final h2 = 0.5 * sourceHeight;
    final dw2 = 0.5 * rotatedWidth;
    final dh2 = 0.5 * rotatedHeight;
    final dx = point.dx - w2;
    final dy = point.dy - h2;

    return Offset(
      dw2 + (dx * ca) - (dy * sa),
      dh2 + (dx * sa) + (dy * ca),
    );
  }

  Rect _rotateRect(
    Rect rect, {
    required double sourceWidth,
    required double sourceHeight,
    required double rotatedWidth,
    required double rotatedHeight,
    required double angleDegrees,
  }) {
    final points = [
      _rotatePoint(
        rect.topLeft,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        rotatedWidth: rotatedWidth,
        rotatedHeight: rotatedHeight,
        angleDegrees: angleDegrees,
      ),
      _rotatePoint(
        rect.topRight,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        rotatedWidth: rotatedWidth,
        rotatedHeight: rotatedHeight,
        angleDegrees: angleDegrees,
      ),
      _rotatePoint(
        rect.bottomLeft,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        rotatedWidth: rotatedWidth,
        rotatedHeight: rotatedHeight,
        angleDegrees: angleDegrees,
      ),
      _rotatePoint(
        rect.bottomRight,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        rotatedWidth: rotatedWidth,
        rotatedHeight: rotatedHeight,
        angleDegrees: angleDegrees,
      ),
    ];

    final xs = points.map((point) => point.dx);
    final ys = points.map((point) => point.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  img.Image _neutralizeBackground(
    img.Image image,
    DetectedFace face,
    Rect cropRect,
  ) {
    if (face.faceContour.isEmpty) {
      return image;
    }

    final polygon = face.faceContour
        .map((point) => _mapPointToCroppedImage(point, cropRect, image.width))
        .toList(growable: false);

    if (polygon.length < 3) {
      return image;
    }

    final expandedPolygon = _expandPolygon(
      polygon,
      image.width / 2,
      image.height / 2,
      1.08,
    );

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (_pointInPolygon(x + 0.5, y + 0.5, expandedPolygon)) {
          continue;
        }

        final original = image.getPixel(x, y);
        final r = original.r.toInt();
        final g = original.g.toInt();
        final b = original.b.toInt();
        image.setPixelRgba(
          x,
          y,
          ((r * 0.35) + (127 * 0.65)).round(),
          ((g * 0.35) + (127 * 0.65)).round(),
          ((b * 0.35) + (127 * 0.65)).round(),
          255,
        );
      }
    }

    return image;
  }

  Offset _mapPointToCroppedImage(
    Offset point,
    Rect cropRect,
    int outputSize,
  ) {
    final normalizedX =
        ((point.dx - cropRect.left) / cropRect.width).clamp(0.0, 1.0);
    final normalizedY =
        ((point.dy - cropRect.top) / cropRect.height).clamp(0.0, 1.0);
    return Offset(
      normalizedX * (outputSize - 1),
      normalizedY * (outputSize - 1),
    );
  }

  List<Offset> _expandPolygon(
    List<Offset> polygon,
    double centerX,
    double centerY,
    double scale,
  ) {
    return polygon
        .map(
          (point) => Offset(
            centerX + ((point.dx - centerX) * scale),
            centerY + ((point.dy - centerY) * scale),
          ),
        )
        .toList(growable: false);
  }

  bool _pointInPolygon(double x, double y, List<Offset> polygon) {
    var inside = false;

    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].dx;
      final yi = polygon[i].dy;
      final xj = polygon[j].dx;
      final yj = polygon[j].dy;

      final intersects = ((yi > y) != (yj > y)) &&
          (x <
              ((xj - xi) * (y - yi)) / ((yj - yi) == 0 ? 0.000001 : (yj - yi)) +
                  xi);

      if (intersects) {
        inside = !inside;
      }
    }

    return inside;
  }
}

class FaceCropResult {
  const FaceCropResult({
    required this.image,
    required this.cropRect,
  });

  final img.Image image;
  final Rect cropRect;
}

class _AlignedFaceImage {
  const _AlignedFaceImage({
    required this.image,
    required this.face,
  });

  final img.Image image;
  final DetectedFace face;
}
