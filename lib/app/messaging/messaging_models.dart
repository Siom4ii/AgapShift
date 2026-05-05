/// In-app direct message (1:1) models.

class DmConversationSummary {
  const DmConversationSummary({
    required this.conversationId,
    required this.otherUserId,
    required this.otherDisplayName,
    required this.lastPreview,
    required this.updatedAt,
  });

  final String conversationId;
  final String otherUserId;
  final String otherDisplayName;
  final String lastPreview;
  final DateTime updatedAt;
}

class DmMessage {
  const DmMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime createdAt;
}
