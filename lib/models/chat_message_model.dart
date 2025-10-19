import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String text;
  final String role; // 'user' or 'model'
  final Timestamp timestamp;

  ChatMessage({
    required this.text,
    required this.role,
    required this.timestamp,
  });

  /// Factory constructor to create a ChatMessage from a map (e.g., from Firestore)
  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      text: map['text'] ?? '',
      role: map['role'] ?? 'model',
      timestamp: map['timestamp'] ?? Timestamp.now(),
    );
  }

  /// Converts a ChatMessage object into a map for Firestore storage
  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'role': role,
      'timestamp': timestamp,
    };
  }
}