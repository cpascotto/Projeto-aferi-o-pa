class PatientModel {
  final int id;
  final String name;
  final String cpf;
  final List<List<double>> faceEmbeddings;
  final String? faceImagePath;
  final int faceSamplesCount;

  const PatientModel({
    required this.id,
    required this.name,
    required this.cpf,
    required this.faceEmbeddings,
    this.faceImagePath,
    this.faceSamplesCount = 0,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    final rawEmbedding = (json['face_embedding'] as List?) ?? const [];
    return PatientModel(
      id: json['id'] as int,
      name: (json['name'] ?? '') as String,
      cpf: (json['cpf'] ?? '') as String,
      faceEmbeddings: _parseFaceEmbeddings(rawEmbedding),
      faceImagePath: json['face_image_path'] as String?,
      faceSamplesCount: (json['face_samples_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cpf': cpf,
      'face_embedding': faceEmbeddings,
      'face_image_path': faceImagePath,
      'face_samples_count': faceSamplesCount,
    };
  }

  static List<List<double>> _parseFaceEmbeddings(List rawEmbedding) {
    if (rawEmbedding.isEmpty) {
      return const [];
    }

    final firstItem = rawEmbedding.first;
    if (firstItem is List) {
      return rawEmbedding
          .whereType<List>()
          .map(
            (embedding) => embedding
                .whereType<num>()
                .map((value) => value.toDouble())
                .toList(growable: false),
          )
          .where((embedding) => embedding.isNotEmpty)
          .toList(growable: false);
    }

    return [
      rawEmbedding
          .whereType<num>()
          .map((value) => value.toDouble())
          .toList(growable: false),
    ];
  }
}
