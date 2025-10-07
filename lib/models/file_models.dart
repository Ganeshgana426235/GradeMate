// lib/models/file_models.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single file's data stored in Firestore document.
class FileData {
  final String id;
  final String name;
  final String url;
  final String type;
  final int size;
  final Timestamp uploadedAt;
  final String ownerId;
  final String? ownerName;
  final String? parentFolderId;
  final List<String> sharedWith;

  FileData({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    required this.size,
    required this.uploadedAt,
    required this.ownerId,
    this.ownerName,
    this.parentFolderId,
    this.sharedWith = const [],
  });

  /// Factory constructor to create a FileData object from a Firestore document snapshot.
  factory FileData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FileData(
      id: doc.id, // ID comes from the Document ID
      name: data['name'] ?? '',
      url: data['url'] ?? '',
      type: data['type'] ?? 'unknown',
      size: (data['size'] ?? 0).toInt(),
      uploadedAt: data['uploadedAt'] ?? Timestamp.now(),
      ownerId: data['ownerId'] ?? '',
      ownerName: data['ownerName'],
      parentFolderId: data['parentFolderId'],
      sharedWith: List<String>.from(data['sharedWith'] ?? []),
    );
  }

  /// Converts FileData to a Map for storage as a document.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'url': url,
      'type': type,
      'size': size,
      'uploadedAt': uploadedAt,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'parentFolderId': parentFolderId,
      'sharedWith': sharedWith,
    };
  }
  
  /// Creates a simple map containing only the ID, used for root array mirroring.
  Map<String, dynamic> toPointerMap() {
    return {'id': id};
  }
}

/// Represents a folder's data stored in Firestore document.
class FolderData {
  final String id;
  final String name;
  final String ownerId;
  final String? ownerName;
  final String? parentFolderId;
  final List<String> sharedWith;

  FolderData({
    required this.id,
    required this.name,
    required this.ownerId,
    this.ownerName,
    this.parentFolderId,
    this.sharedWith = const [],
  });

  /// Factory constructor to create a FolderData object from a Firestore document snapshot.
  factory FolderData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FolderData(
      id: doc.id,
      name: data['name'] ?? '',
      ownerId: data['ownerId'] ?? '',
      ownerName: data['ownerName'],
      parentFolderId: data['parentFolderId'],
      sharedWith: List<String>.from(data['sharedWith'] ?? []),
    );
  }

  /// Converts FolderData to a Map for storage as a document.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'parentFolderId': parentFolderId,
      'sharedWith': sharedWith,
    };
  }
  
  /// Creates a simple map containing only the ID, used for root array mirroring.
  Map<String, dynamic> toPointerMap() {
    return {'id': id};
  }
}