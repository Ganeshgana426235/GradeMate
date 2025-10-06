import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single file's data stored in Firestore.
/// This class acts as a data model to organize file information
/// retrieved from the 'files' collection.
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
      id: doc.id,
      name: data['name'] ?? '',
      url: data['url'] ?? '',
      type: data['type'] ?? 'unknown',
      size: data['size'] ?? 0,
      uploadedAt: data['uploadedAt'] ?? Timestamp.now(),
      ownerId: data['ownerId'] ?? '',
      ownerName: data['ownerName'],
      parentFolderId: data['parentFolderId'],
      sharedWith: List<String>.from(data['sharedWith'] ?? []),
    );
  }
}

/// Represents a folder's data stored in Firestore.
/// This model is used to organize and manage folders and their contents
/// (sub-folders and files).
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
}