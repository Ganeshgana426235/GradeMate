import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:grademate/widgets/bottom_nav_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:grademate/widgets/file_details_page.dart';
import 'package:grademate/models/file_models.dart';
import 'package:grademate/widgets/file_viewer_page.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


class MyFilesPage extends StatefulWidget {
  final String? folderId;
  final String? folderName;

  const MyFilesPage({super.key, this.folderId, this.folderName});

  @override
  State<MyFilesPage> createState() => _MyFilesPageState();
}

class _MyFilesPageState extends State<MyFilesPage> {
  int _selectedIndex = 2;
  String _searchQuery = '';
  String _searchTab = 'All'; // 'All', 'Files', 'Folders'
  
  String? _currentFolderId;
  String? _currentFolderName;

  List<FolderData> _allFolders = [];
  List<FileData> _allFiles = [];
  bool _isLoading = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  @override
  void initState() {
    super.initState();
    _currentFolderId = widget.folderId;
    _currentFolderName = widget.folderName ?? 'My Files';
    _fetchAndCacheAllData();
    _initializeNotifications();
  }
  
  void _initializeNotifications() {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidInitializationSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
      InitializationSettings(android: androidInitializationSettings);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _showProgressNotification(String fileName, int progress) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'download_channel_id',
      'Download Progress',
      channelDescription: 'Shows the progress of file downloads',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: 0,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Downloading $fileName',
      'Download in progress: $progress%',
      platformChannelSpecifics,
    );
  }

  Future<void> _showCompletionNotification(String fileName) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'download_completion_channel_id',
      'Download Complete',
      channelDescription: 'Notifies when a download is finished',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      1,
      'Download Complete',
      'The file "$fileName" has been downloaded successfully.',
      platformChannelSpecifics,
    );
  }
  
  // Helper to get the correct collection reference for the current file/folder location
  CollectionReference<Map<String, dynamic>> _getCurrentCollectionRef(String collectionName) {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception("User not authenticated or email missing.");
    }

    if (_currentFolderId == null) {
      // Root level: /users/{email}/files or /users/{email}/folders
      return _firestore.collection('users').doc(user.email).collection(collectionName);
    } else {
      // Nested level: /folders/{folderId}/files or /folders/{folderId}/folders
      return _firestore.collection('folders').doc(_currentFolderId).collection(collectionName);
    }
  }

  void _fetchAndCacheAllData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch data from the appropriate subcollections
      final filesCollection = _getCurrentCollectionRef('files');
      final foldersCollection = _getCurrentCollectionRef('folders');

      final filesSnapshot = await filesCollection.get();
      final foldersSnapshot = await foldersCollection.get();
      
      setState(() {
        _allFiles = filesSnapshot.docs.map((doc) => FileData.fromFirestore(doc)).toList();
        _allFolders = foldersSnapshot.docs.map((doc) => FolderData.fromFirestore(doc)).toList();
      });
      
    } catch (e) {
      debugPrint('Error fetching data: $e');
      _showSnackbar('Failed to load data.', success: false);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      context.go('/student_home');
    } else if (index == 1) {
      context.go('/student_courses');
    } else if (index == 2) {
      context.go('/student_my_files');
    } else if (index == 3) {
      context.go('/student_profile');
    }
  }

  // --- File and Folder Management Functions ---

  Future<void> _uploadFile() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;
    
    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final file = result.files.first;
    final fileName = file.name;
    final filePathBytes = file.bytes!;
    
    // Determine the collection for the new file
    final filesCollection = _getCurrentCollectionRef('files');
    final fileDocRef = filesCollection.doc(); // Let Firestore generate the ID
    final newFileId = fileDocRef.id;

    final storagePath = 'uploads/${user.uid}/${_currentFolderId ?? 'root'}/$fileName';
    final storageRef = _storage.ref().child(storagePath);
    
    try {
      final uploadTask = storageRef.putData(filePathBytes);
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();

      final userDoc = await _firestore.collection('users').doc(user.email).get();
      final ownerName = userDoc.data()?['name'] ?? 'Unknown';

      final newFileData = FileData(
        id: newFileId,
        name: fileName,
        url: downloadUrl,
        size: file.size ?? 0,
        type: file.extension ?? 'unknown',
        uploadedAt: Timestamp.now(),
        ownerId: user.uid,
        ownerName: ownerName,
        parentFolderId: _currentFolderId,
        sharedWith: [],
      );
      
      // 1. Store the full details as a document in the appropriate subcollection
      await fileDocRef.set(newFileData.toMap());
      
      // 2. MIRRORING FOR ROOT ONLY (User requested this feature)
      if (_currentFolderId == null) {
        await _firestore.collection('users').doc(user.email).update({
          'files': FieldValue.arrayUnion([newFileData.toPointerMap()]),
        });
      }

      _showSnackbar('File uploaded successfully!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to upload file: $e', success: false);
      debugPrint('File upload error: $e');
    }
  }
  
  Future<void> _createFolder(String folderName) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    // Determine the collection for the new folder
    final foldersCollection = _getCurrentCollectionRef('folders');
    final folderDocRef = foldersCollection.doc(); // Let Firestore generate the ID
    final newFolderId = folderDocRef.id;

    final userDoc = await _firestore.collection('users').doc(user.email).get();
    final ownerName = userDoc.data()?['name'] ?? 'Unknown';

    final newFolderData = FolderData(
      id: newFolderId,
      name: folderName,
      ownerId: user.uid,
      ownerName: ownerName,
      parentFolderId: _currentFolderId,
      sharedWith: [],
    );

    try {
      // 1. Store the full details as a document in the appropriate subcollection
      await folderDocRef.set(newFolderData.toMap());

      // 2. Create the master document in the top-level /folders collection 
      // This is necessary because it hosts the NESTED subcollections for subsequent levels.
      final masterFolderRef = _firestore.collection('folders').doc(newFolderId);
      await masterFolderRef.set(newFolderData.toMap());
      
      // 3. MIRRORING FOR ROOT ONLY (User requested this feature)
      if (_currentFolderId == null) {
        await _firestore.collection('users').doc(user.email).update({
          'folders': FieldValue.arrayUnion([newFolderData.toPointerMap()]),
        });
      }
      
      _showSnackbar('Folder "$folderName" created successfully!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to create folder: $e', success: false);
      debugPrint('Folder creation error: $e');
    }
  }
  
  Future<void> _deleteFile(FileData file) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return;
      
      // 1. Delete from Storage
      final storagePath = 'uploads/${user.uid}/${file.parentFolderId ?? 'root'}/${file.name}';
      final storageRef = _storage.ref().child(storagePath);
      try {
        await storageRef.getDownloadURL(); 
        await storageRef.delete();
      } catch (e) {
        debugPrint('File not found in storage or failed to delete: $e');
      }

      // 2. Delete the document from the current subcollection location
      final fileDocRef = _getCurrentCollectionRef('files').doc(file.id);
      await fileDocRef.delete();
      
      // 3. MIRRORING FOR ROOT ONLY: Remove ID from user's document array
      if (_currentFolderId == null) {
        await _firestore.collection('users').doc(user.email).update({
          'files': FieldValue.arrayRemove([file.toPointerMap()]),
        });
      }
      
      _showSnackbar('File deleted successfully!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to delete file: $e', success: false);
      debugPrint('Delete file error: $e');
    }
  }

  Future<void> _deleteFolder(FolderData folder) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return;
      
      // Recursive helper to delete contents and master documents in nested structure
      Future<void> _recursiveDelete(String folderId, String ownerUid) async {
        final masterFolderRef = _firestore.collection('folders').doc(folderId);

        // 1. Target the collections that hold the *contents* of this folder
        CollectionReference filesCollection = masterFolderRef.collection('files');
        CollectionReference foldersCollection = masterFolderRef.collection('folders');
        
        final WriteBatch batch = _firestore.batch();
        
        // Delete all files in the current folder
        final filesSnapshot = await filesCollection.get();
        for (var fileDoc in filesSnapshot.docs) {
          final fileData = FileData.fromFirestore(fileDoc);
          // Delete from Storage
          final storagePath = 'uploads/$ownerUid/${folderId}/${fileData.name}';
          final storageRef = _storage.ref().child(storagePath);
          try { await storageRef.delete(); } catch (e) { debugPrint('Storage delete error: $e'); }
          
          batch.delete(fileDoc.reference);
        }
        
        // Delete all subfolders and their contents
        final foldersSnapshot = await foldersCollection.get();
        for (var subfolderDoc in foldersSnapshot.docs) {
          // Recursively delete subfolder contents and master document
          await _recursiveDelete(subfolderDoc.id, ownerUid); 
          batch.delete(subfolderDoc.reference); // Delete the subfolder doc
        }
        
        // After deleting all contents, delete the master folder document itself
        batch.delete(masterFolderRef);
        await batch.commit();
      }

      // 1. Delete the document from the current subcollection location
      final folderDocRef = _getCurrentCollectionRef('folders').doc(folder.id);
      await folderDocRef.delete();
      
      // 2. Recursively delete the master folder document and its contents from the /folders collection
      await _recursiveDelete(folder.id, user.uid);
      
      // 3. MIRRORING FOR ROOT ONLY: Remove ID from user's document array
      if (_currentFolderId == null) {
        await _firestore.collection('users').doc(user.email).update({
          'folders': FieldValue.arrayRemove([folder.toPointerMap()]),
        });
      }

      _showSnackbar('Folder and its contents deleted successfully!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to delete folder: ${e.toString()}', success: false);
      debugPrint('Delete folder error: $e');
    }
  }
  
  Future<void> _renameItem(String itemId, String oldName, String newName, String type) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return;

      // Get the document reference for the item in the current location
      final targetCollection = _getCurrentCollectionRef(type == 'File' ? 'files' : 'folders');
      final itemRef = targetCollection.doc(itemId);
      
      // 1. Update the name in the current location (which holds the full document)
      await itemRef.update({'name': newName});
      
      // 2. If it's a folder, update the master document name too (for consistency/traversal)
      if (type == 'Folder') {
          await _firestore.collection('folders').doc(itemId).update({'name': newName});
      }

      // 3. ROOT ONLY: Update the name in the user's array for the mirrored root item.
      if (_currentFolderId == null) {
        final arrayName = type == 'File' ? 'files' : 'folders';
        // Read-modify-write required for array of maps
        await _firestore.runTransaction((transaction) async {
          final userDocRef = _firestore.collection('users').doc(user.email);
          final userDoc = await transaction.get(userDocRef);

          if (userDoc.exists) {
            // Need to fetch and convert the array of simple maps (ID/Name)
            List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(userDoc.data()?[arrayName] ?? []).cast<Map<String, dynamic>>();
            final index = items.indexWhere((item) => item['id'] == itemId);
            
            if (index != -1) {
              // Update the name property within the map in the array
              final updatedItem = Map<String, dynamic>.from(items[index])..['name'] = newName;
              items[index] = updatedItem;
              
              transaction.update(userDocRef, {arrayName: items});
            }
          }
        });
      }
      
      _showSnackbar('Successfully renamed!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to rename: $e', success: false);
    }
  }

  Future<void> _showCreateFolderDialog() async {
    final TextEditingController controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create New Folder'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "Folder Name"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Create'),
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  _createFolder(controller.text);
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }
  
  void _showSnackbar(String message, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }
  
  void _openFolder(String folderId, String folderName) {
    context.push('/student_my_files/$folderId', extra: folderName);
  }
  
  void _goBack() {
    context.pop();
  }

  String _getItemPath(dynamic item) {
    if (_currentFolderId == null) {
      return 'My Files';
    } else {
      return '.../${_currentFolderName}';
    }
  }
  
  List<dynamic> _getFilteredItems() {
    List<dynamic> items = [];
    final lowerCaseQuery = _searchQuery.toLowerCase();
    
    if (_searchQuery.isEmpty) {
        if (_searchTab == 'All' || _searchTab == 'Folders') {
          items.addAll(_allFolders);
        }
        if (_searchTab == 'All' || _searchTab == 'Files') {
          items.addAll(_allFiles);
        }
    } else {
        if (_searchTab == 'All' || _searchTab == 'Folders') {
          items.addAll(_allFolders.where((f) => 
            f.name.toLowerCase().contains(lowerCaseQuery)
          ));
        }
        if (_searchTab == 'All' || _searchTab == 'Files') {
          items.addAll(_allFiles.where((f) => 
            f.name.toLowerCase().contains(lowerCaseQuery)
          ));
        }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    List<dynamic> filteredItems = _getFilteredItems();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: widget.folderId != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: _goBack,
              )
            : null,
        title: Text(_currentFolderName ?? 'My Files', style: const TextStyle(color: Colors.black)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.black),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.create_new_folder),
                      title: const Text('Create New Folder'),
                      onTap: () {
                        Navigator.pop(context);
                        _showCreateFolderDialog();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.upload_file),
                      title: const Text('Upload File'),
                      onTap: () {
                        Navigator.pop(context);
                        _uploadFile();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      onChanged: (value) => setState(() => _searchQuery = value),
                      decoration: const InputDecoration(
                        icon: Icon(Icons.search, color: Colors.grey),
                        hintText: 'Search',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['All', 'Files', 'Folders'].map((tab) {
                      final isSelected = _searchTab == tab;
                      return GestureDetector(
                        onTap: () => setState(() => _searchTab = tab),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isSelected ? Colors.blue : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            tab,
                            style: TextStyle(
                              color: isSelected ? Colors.blue : Colors.grey,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  if (filteredItems.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          _searchQuery.isEmpty ? 'No files or folders here. Tap the + button to create one.' : 'No results found for "$_searchQuery"',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        if (item is FileData) {
                          return _buildFileTile(item, _getItemPath(item));
                        } else if (item is FolderData) {
                          return _buildFolderTile(item, _getItemPath(item));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                ],
              ),
            ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  Widget _buildFolderTile(FolderData folder, String path) {
    return ListTile(
      leading: Icon(Icons.folder_outlined, color: Colors.blue[800]),
      title: Text(folder.name),
      subtitle: Text(path, style: const TextStyle(color: Colors.grey)),
      trailing: _buildItemPopupMenu('Folder', folder),
      onTap: () => _openFolder(folder.id, folder.name),
    );
  }

  Widget _buildFileTile(FileData file, String path) {
    return ListTile(
      leading: Icon(_getFileIcon(file.type), color: Colors.blue[800]),
      title: Text(file.name),
      subtitle: Text(path, style: const TextStyle(color: Colors.grey)),
      trailing: _buildItemPopupMenu('File', file),
      onTap: () {
        context.push('/file_viewer', extra: file);
      },
    );
  }

  Widget _buildItemPopupMenu(String type, dynamic item) {
    final itemId = item.id;
    final itemName = item.name;
    final fileData = type == 'File' ? item as FileData : null;
    final folderData = type == 'Folder' ? item as FolderData : null;

    return PopupMenuButton<String>(
      onSelected: (String value) async {
        if (value == 'delete') {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Delete $type'),
              content: Text('Are you sure you want to delete "$itemName"? This cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (type == 'File') {
                      _deleteFile(fileData!);
                    } else {
                      _deleteFolder(folderData!);
                    }
                  },
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
        } else if (value == 'rename') {
           final TextEditingController controller = TextEditingController(text: itemName);
           await showDialog(
             context: context,
             builder: (context) {
               return AlertDialog(
                 title: Text('Rename $type'),
                 content: TextField(
                   controller: controller,
                   decoration: InputDecoration(hintText: 'New name for $type'),
                 ),
                 actions: [
                   TextButton(
                     onPressed: () => Navigator.of(context).pop(),
                     child: const Text('Cancel'),
                   ),
                   TextButton(
                     onPressed: () {
                       if (controller.text.isNotEmpty) {
                         _renameItem(itemId, itemName, controller.text, type);
                         Navigator.of(context).pop();
                       }
                     },
                     child: const Text('Rename'),
                   ),
                 ],
               );
             },
           );
        } else if (value == 'move') {
          _showSnackbar('Move operation is temporarily disabled.', success: false);
        } else if (value == 'details' && type == 'File') {
          if (fileData != null) {
            context.push('/file_details', extra: fileData);
          }
        } else if (value == 'open' && type == 'Folder') {
          _openFolder(itemId, itemName);
        } else if (value == 'view' && type == 'File') {
          if (fileData != null) {
            context.push('/file_viewer', extra: fileData);
          }
        } else if (value == 'download' && type == 'File' && fileData != null) {
          _downloadFile(fileData);
        } else if (value == 'share' && type == 'File' && fileData != null) {
          _shareFile(fileData);
        }
      },
      itemBuilder: (BuildContext context) {
        final List<PopupMenuEntry<String>> items = [
          PopupMenuItem<String>(
            value: type == 'Folder' ? 'open' : 'view',
            child: ListTile(
              leading: Icon(type == 'Folder' ? Icons.folder_open : Icons.open_in_new),
              title: Text(type == 'Folder' ? 'Open' : 'View'),
            ),
          ),
          const PopupMenuItem<String>(
            value: 'rename',
            child: ListTile(
              leading: Icon(Icons.drive_file_rename_outline),
              title: Text('Rename'),
            ),
          ),
          const PopupMenuItem<String>(
            value: 'move',
            child: ListTile(
              leading: Icon(Icons.folder_copy_outlined),
              title: Text('Move'),
            ),
          ),
          const PopupMenuItem<String>(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Delete'),
            ),
          ),
        ];

        if (type == 'File') {
          items.addAll([
            const PopupMenuItem<String>(
              value: 'download',
              child: ListTile(
                leading: Icon(Icons.download),
                title: Text('Download'),
              ),
            ),
            const PopupMenuItem<String>(
              value: 'share',
              child: ListTile(
                leading: Icon(Icons.share),
                title: Text('Share'),
              ),
            ),
            const PopupMenuItem<String>(
              value: 'details',
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Details'),
              ),
            ),
          ]);
        }
        return items;
      },
    );
  }
  
  IconData _getFileIcon(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf': return Icons.picture_as_pdf_outlined;
      case 'doc': case 'docx': return Icons.description_outlined;
      case 'ppt': case 'pptx': return Icons.slideshow_outlined;
      case 'xls': case 'xlsx': return Icons.table_chart_outlined;
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Icons.image_outlined;
      case 'mp4': case 'mov': case 'avi': return Icons.video_file_outlined;
      case 'zip': case 'rar': return Icons.folder_zip_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }
  
  Future<void> _downloadFile(FileData file) async {
    try {
      final dio = Dio();
      final Directory? baseDownloadDir = await getExternalStorageDirectory();
      if (baseDownloadDir == null) {
        _showSnackbar('Failed to find a valid download directory.', success: false);
        return;
      }
      final Directory gradeMateDir = Directory('${baseDownloadDir.path}${Platform.pathSeparator}GradeMate');

      if (!await gradeMateDir.exists()) {
        try {
          await gradeMateDir.create(recursive: true);
        } catch (e) {
          _showSnackbar('Failed to create folder. Cannot download.', success: false);
          return;
        }
      }
      
      final filePath = '${gradeMateDir.path}${Platform.pathSeparator}${file.name}';
      
      await dio.download(
        file.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toInt();
            _showProgressNotification(file.name, progress);
          }
        },
      );
      await _showCompletionNotification(file.name);
      _showSnackbar('File downloaded successfully!');
      
    } catch (e) {
      _showSnackbar('Error during download: ${e.toString()}', success: false);
    }
  }

  Future<void> _shareFile(FileData file) async {
    try {
      final dio = Dio();
      final dir = await getTemporaryDirectory();
      final tempFilePath = '${dir.path}/${file.name}';
      
      await dio.download(file.url, tempFilePath);

      await Share.shareXFiles([XFile(tempFilePath)], text: 'Check out this file from GradeMate: ${file.name}');

    } catch (e) {
      _showSnackbar('❌ Failed to share file: $e', success: false);
    }
  }
}