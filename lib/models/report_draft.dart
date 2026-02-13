class ReportDraft {
  final String id;
  final int reportNumber;
  final int createdTimestamp;
  final String createdBy;
  final String projectName;
  final String clientName;
  final String summary;
  final List<String> photoIds;
  final List<Map<String, double>> signaturePoints;

  ReportDraft({
    required this.id,
    required this.reportNumber,
    required this.createdTimestamp,
    required this.createdBy,
    required this.projectName,
    required this.clientName,
    this.summary = '',
    required this.photoIds,
    this.signaturePoints = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'reportNumber': reportNumber,
        'createdTimestamp': createdTimestamp,
        'createdBy': createdBy,
        'projectName': projectName,
        'clientName': clientName,
        'summary': summary,
        'photoIds': photoIds,
        'signaturePoints': signaturePoints,
      };

  factory ReportDraft.fromJson(Map<String, dynamic> json) => ReportDraft(
        id: json['id'],
        reportNumber: json['reportNumber'],
        createdTimestamp: json['createdTimestamp'],
        createdBy: json['createdBy'],
        projectName: json['projectName'],
        clientName: json['clientName'],
        summary: json['summary'] ?? '',
        photoIds: List<String>.from(json['photoIds'] ?? []),
        signaturePoints: (json['signaturePoints'] as List?)
                ?.map((e) => Map<String, double>.from(e))
                .toList() ??
            [],
      );

  String getReportNumberFormatted() {
    final date = DateTime.fromMillisecondsSinceEpoch(createdTimestamp);
    final months = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
    return 'Nr ${reportNumber.toString().padLeft(3, '0')}/${date.day}/${months[date.month - 1]}/${date.year}';
  }
}
