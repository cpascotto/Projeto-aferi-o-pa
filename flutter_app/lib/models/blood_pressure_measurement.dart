class BloodPressureMeasurement {
  const BloodPressureMeasurement({
    required this.systolic,
    required this.diastolic,
    required this.bpm,
    required this.recordIndex,
    required this.rawPayload,
  });

  final int systolic;
  final int diastolic;
  final int bpm;
  final int recordIndex;
  final String rawPayload;

  factory BloodPressureMeasurement.fromMap(Map<dynamic, dynamic> map) {
    return BloodPressureMeasurement(
      systolic: map['systolic'] as int,
      diastolic: map['diastolic'] as int,
      bpm: map['bpm'] as int,
      recordIndex: map['recordIndex'] as int,
      rawPayload: map['rawPayload'] as String,
    );
  }
}
