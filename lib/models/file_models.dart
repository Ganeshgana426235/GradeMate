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
  
  /// Creates a copy of this FileData object, optionally changing the name.
  FileData copyWith({
    String? id,
    String? name,
    String? url,
    String? type,
    int? size,
    Timestamp? uploadedAt,
    String? ownerId,
    String? ownerName,
    String? parentFolderId,
    List<String>? sharedWith,
  }) {
    return FileData(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      size: size ?? this.size,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      parentFolderId: parentFolderId ?? this.parentFolderId,
      sharedWith: sharedWith ?? this.sharedWith,
    );
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
  final Timestamp? createdAt;
  final List<String> files; // Optional: file IDs
  final List<String> folders; // Optional: child folder IDs

  FolderData({
    required this.id,
    required this.name,
    required this.ownerId,
    this.ownerName,
    this.parentFolderId,
    this.sharedWith = const [],
    this.createdAt,
    this.files = const [],
    this.folders = const [],
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
      createdAt: data['createdAt'] as Timestamp?,
      files: List<String>.from(data['files'] ?? []),
      folders: List<String>.from(data['folders'] ?? []),
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
      'createdAt': createdAt ?? Timestamp.now(),
      'files': files,
      'folders': folders,
    };
  }

  /// Creates a copy of this FolderData object, optionally changing the name.
  FolderData copyWith({
    String? id,
    String? name,
    String? ownerId,
    String? ownerName,
    String? parentFolderId,
    List<String>? sharedWith,
    Timestamp? createdAt,
    List<String>? files,
    List<String>? folders,
  }) {
    return FolderData(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      parentFolderId: parentFolderId ?? this.parentFolderId,
      sharedWith: sharedWith ?? this.sharedWith,
      createdAt: createdAt ?? this.createdAt,
      files: files ?? this.files,
      folders: folders ?? this.folders,
    );
  }
}
