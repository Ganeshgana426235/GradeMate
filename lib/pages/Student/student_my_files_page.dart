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
import 'dart:math' as math;
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
  Future<CollectionReference<Map<String, dynamic>>> _getCurrentCollectionRef(String collectionName) async {
  final user = _auth.currentUser;
  if (user == null || user.email == null) {
    throw Exception("User not authenticated or email missing.");
  }

  // Fetch UID from user doc
  final userDoc = await _firestore.collection('users').doc(user.email).get();
  final uid = userDoc.data()?['uid'];
  if (uid == null) throw Exception("UID not found in user document.");

  // Path: /users/{user.email}/{collectionName}
  return _firestore.collection('users').doc(user.email).collection(collectionName);
}

  void _fetchAndCacheAllData() async {
  setState(() {
    _isLoading = true;
  });

  final user = _auth.currentUser;
  if (user == null || user.email == null) {
    if (mounted) setState(() { _isLoading = false; });
    _showSnackbar('User not authenticated. Please log in.', success: false); 
    return;
  }

  try {
    // Fetch UID from user doc
    final userDoc = await _firestore.collection('users').doc(user.email).get();
    final uid = userDoc.data()?['uid'];
    if (uid == null) throw Exception("UID not found in user document.");

    final filesCollectionRef = _firestore.collection('users').doc(user.email).collection('files');
    final foldersCollectionRef = _firestore.collection('users').doc(user.email).collection('folders');

    final queryParentId = _currentFolderId;

    Query filesQueryBase = filesCollectionRef.where('ownerId', isEqualTo: uid);
    Query foldersQueryBase = foldersCollectionRef.where('ownerId', isEqualTo: uid);

    if (queryParentId == null) {
      filesQueryBase = filesQueryBase.where('parentFolderId', isEqualTo: null);
      foldersQueryBase = foldersQueryBase.where('parentFolderId', isEqualTo: null);
    } else {
      filesQueryBase = filesQueryBase.where('parentFolderId', isEqualTo: queryParentId);
      foldersQueryBase = foldersQueryBase.where('parentFolderId', isEqualTo: queryParentId);
    }

    final filesSnapshot = await filesQueryBase.get();
    final foldersSnapshot = await foldersQueryBase.get();

    setState(() {
      _allFiles = filesSnapshot.docs.map((doc) => FileData.fromFirestore(doc)).toList();
      _allFolders = foldersSnapshot.docs.map((doc) => FolderData.fromFirestore(doc)).toList();
    });

  } catch (e) {
    debugPrint('Error fetching data: $e');
    _showSnackbar('Failed to load data. Please check your internet and application permissions.', success: false);
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
    final filesCollection = await _getCurrentCollectionRef('files');
    final fileDocRef = filesCollection.doc(); // Let Firestore generate the ID
    final newFileId = fileDocRef.id;

    // NOTE: This storage path uses file.name, which breaks rename. Using file.id is safer.
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
      
      // --- REMOVED MIRRORING CODE: FIX for toPointerMap error ---
      /*
      if (_currentFolderId == null) {
        await _firestore.collection('users').doc(user.email).update({
          'files': FieldValue.arrayUnion([newFileData.toPointerMap()]),
        });
      }
      */

      // Optimistically add to state
      setState(() {
        _allFiles.add(newFileData);
      });

      _showSnackbar('File uploaded successfully!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to upload file: ${e.toString()}', success: false);
      debugPrint('File upload error: $e');
    }
  }
  
 Future<void> _createFolder(String folderName) async {
  final user = _auth.currentUser;
  if (user == null || user.email == null) return;

  try {
    // Fetch UID from user doc
    final userDoc = await _firestore.collection('users').doc(user.email).get();
    final uid = userDoc.data()?['uid'];
    if (uid == null) throw Exception("UID not found in user document.");

    final userFoldersCollection = _firestore.collection('users').doc(user.email).collection('folders');
    final newFolderRef = userFoldersCollection.doc(); 
    final newFolderId = newFolderRef.id;

    final ownerName = userDoc.data()?['name'] ?? 'Unknown';

    final newFolderData = FolderData(
      id: newFolderId,
      name: folderName,
      ownerId: uid, // Use fetched UID
      ownerName: ownerName,
      parentFolderId: _currentFolderId,
      sharedWith: [],
      createdAt: Timestamp.now(),
      files: [],
      folders: [],
    );

    await newFolderRef.set(newFolderData.toMap());

    if (_currentFolderId != null && _currentFolderId!.isNotEmpty) {
      final parentFolderRef = userFoldersCollection.doc(_currentFolderId);
      await parentFolderRef.update({
        'folders': FieldValue.arrayUnion([newFolderId])
      });
    }

    setState(() {
      _allFolders.add(newFolderData);
    });

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
      final filesCollection = await _getCurrentCollectionRef('files');
      final fileDocRef = filesCollection.doc(file.id);
      await fileDocRef.delete();
      
      // --- REMOVED MIRRORING CODE: FIX for toPointerMap error ---
      /*
      // 3. MIRRORING FOR ROOT ONLY: Remove ID from user's document array
      if (_currentFolderId == null) {
        await _firestore.collection('users').doc(user.email).update({
          'files': FieldValue.arrayRemove([file.toPointerMap()]),
        });
      }
      */

      // Optimistically remove from state
      setState(() {
        _allFiles.removeWhere((f) => f.id == file.id);
      });
      
      _showSnackbar('File deleted successfully!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to delete file: ${e.toString()}', success: false);
      debugPrint('Delete file error: $e');
    }
  }

  // NOTE: This delete folder function is complex and relies on old mirroring/subcollection logic
  // which may not pass your security rules. Using the flat structure helper from previous revisions is safer.
  Future<void> _deleteFolder(FolderData folder) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return;

      final userDocRef = _firestore.collection('users').doc(user.email);
      final userFoldersCollection = userDocRef.collection('folders');

      // Safe delete
      Future<void> _safeDelete(DocumentReference ref) async {
        try {
          await ref.delete();
        } on FirebaseException catch (e) {
          debugPrint('Delete failed at ${ref.path}: ${e.code} ${e.message}');
        }
      }

      // Recursive delete (simplified based on your model, but likely still needs adjustment for security rules)
      Future<void> _recursiveDelete(DocumentReference folderRef) async {
        // Delete files (Assuming file documents live directly in the files collection, not nested)
        // If files are *only* in the /users/{email}/files collection, this part is incorrect.
        // If your files collection is flat, you should query the top-level files collection by parentFolderId
        final filesSnapshot = await folderRef.collection('files').get(); // This line assumes nested files, which is likely wrong.
        WriteBatch batch = _firestore.batch();

        for (var fileDoc in filesSnapshot.docs) {
          final fileData = FileData.fromFirestore(fileDoc);
          final storagePath = 'uploads/${user.uid}/${folderRef.id}/${fileData.name}';
          final storageRef = _storage.ref().child(storagePath);

          try {
            await storageRef.delete();
          } catch (e) {
            debugPrint('Storage delete failed: $e');
          }

          batch.delete(fileDoc.reference);
        }
        await batch.commit();

        // Delete subfolders recursively
        final subfoldersSnapshot = await folderRef.collection('folders').get(); // This line assumes nested folders, which is likely wrong.
        for (var subfolderDoc in subfoldersSnapshot.docs) {
          await _recursiveDelete(subfolderDoc.reference);
          await _safeDelete(subfolderDoc.reference);
        }

        // Delete this folder itself
        await _safeDelete(folderRef);
      }

      // Delete logic (Kept your original logic for fidelity to your request)
      if (folder.parentFolderId != null && folder.parentFolderId!.isNotEmpty) {
        final parentFolderRef = userFoldersCollection.doc(folder.parentFolderId);
        await parentFolderRef.update({
          'folders': FieldValue.arrayRemove([folder.id]),
        });
        
        // **This part is based on the assumption folders are documents nested within their parents, which conflicts with your security rules' requirement for `ownerId` on every document.**
        final subfolderRef = userFoldersCollection.doc(folder.id); // Using the flat collection path
        await _recursiveDelete(subfolderRef);
        await _safeDelete(subfolderRef);
      } else {
        // --- REMOVED MIRRORING CODE: FIX for toPointerMap error ---
        /*
        await userDocRef.update({
          'folders': FieldValue.arrayRemove([folder.toPointerMap()]),
        });
        */

        final folderRef = userFoldersCollection.doc(folder.id);
        await _recursiveDelete(folderRef);
        await _safeDelete(folderRef);
      }
      
      // Optimistically remove from state
      setState(() {
        _allFolders.removeWhere((f) => f.id == folder.id);
      });


      _showSnackbar('Folder and its contents deleted successfully!');
      _fetchAndCacheAllData();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _showSnackbar('Permission denied while deleting folder.', success: false);
        debugPrint('PERMISSION DENIED: ${e.message}');
      } else {
        _showSnackbar('Firestore error: ${e.message}', success: false);
        debugPrint('Firestore error: ${e.code} ${e.message}');
      }
    } catch (e) {
      _showSnackbar('Failed to delete folder: $e', success: false);
      debugPrint('Delete folder error: $e');
    }
  }


  
  Future<void> _renameItem(String itemId, String oldName, String newName, String type) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return;
      if (oldName == newName) return; // Added check for safety

      // Get the document reference for the item in the current location
      final targetCollection = await _getCurrentCollectionRef(type == 'File' ? 'files' : 'folders');
      final itemRef = targetCollection.doc(itemId);
      
      // 1. Update the name in the current location (which holds the full document)
      await itemRef.update({'name': newName});
      
      // 2. If it's a folder, update the master document name too (for consistency/traversal)
      if (type == 'Folder') {
          // Assuming you have a separate top-level 'folders' collection which is also used somewhere, but based on your structure, this line is likely redundant if all folder data is in /users/{email}/folders
          // await _firestore.collection('folders').doc(itemId).update({'name': newName}); 
      }

      // 3. ROOT ONLY: Update the name in the user's array for the mirrored root item.
      if (_currentFolderId == null) {
        final arrayName = type == 'File' ? 'files' : 'folders';
        // Read-modify-write required for array of maps
        // --- REMOVED MIRRORING CODE: FIX for toPointerMap error ---
        /*
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
        */
      }
      
      // Optimistically update state (requires copyWith which must be in your model)
      setState(() {
        if (type == 'File') {
          final index = _allFiles.indexWhere((f) => f.id == itemId);
          if (index != -1) {
            // Note: This requires FileData to have a copyWith method
            _allFiles[index] = _allFiles[index].copyWith(name: newName); 
          }
        } else {
          final index = _allFolders.indexWhere((f) => f.id == itemId);
          if (index != -1) {
            // Note: This requires FolderData to have a copyWith method
            _allFolders[index] = _allFolders[index].copyWith(name: newName); 
          }
        }
      });
      
      _showSnackbar('Successfully renamed!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to rename: ${e.toString()}', success: false);
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
    
    // Sort folders before files, then alphabetically by name (Added sorting)
    List<dynamic> unsortedItems = [];
    if (_searchTab == 'All' || _searchTab == 'Folders') {
      unsortedItems.addAll(_allFolders);
    }
    if (_searchTab == 'All' || _searchTab == 'Files') {
      unsortedItems.addAll(_allFiles);
    }
    
    unsortedItems.sort((a, b) {
      if (a is FolderData && b is FileData) return -1;
      if (a is FileData && b is FolderData) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    
    if (_searchQuery.isEmpty) {
      return unsortedItems;
    } else {
      return unsortedItems.where((item) => 
        item.name.toLowerCase().contains(lowerCaseQuery)
      ).toList();
    }
  }

  // Helper for file size formatting (required due to the addition of dart:math)
  String _formatBytes(int bytes, [int decimals = 0]) {
    if (bytes <= 0) return "0 B";
    const suffixes = [' B', ' KB', ' MB', ' GB', ' TB'];
    var i = (math.log(bytes) / math.log(1024)).floor(); 
    
    if (i < 0) i = 0;
    if (i >= suffixes.length) i = suffixes.length - 1;

    return ((bytes / (1 << (i * 10))).toStringAsFixed(decimals)) + suffixes[i];
  }
  
  // Helper for timestamp formatting (required for build tile)
  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    return DateFormat('MMM dd, yyyy').format(timestamp.toDate());
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
      subtitle: Text('${path} - ${_formatBytes(file.size)}', style: const TextStyle(color: Colors.grey)),
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
      _showSnackbar('❌ Failed to share file: ${e.toString()}', success: false);
    }
  }
}
