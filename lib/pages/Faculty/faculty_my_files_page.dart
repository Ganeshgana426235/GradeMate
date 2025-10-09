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


class FacultyMyFilesPage extends StatefulWidget {
  final String? folderId;
  final String? folderName;

  const FacultyMyFilesPage({super.key, this.folderId, this.folderName});

  @override
  State<FacultyMyFilesPage> createState() => _FacultyMyFilesPageState();
}

class _FacultyMyFilesPageState extends State<FacultyMyFilesPage> {
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

  // --- Notification Helper Functions ---

  Future<void> _showUploadProgressNotification(String fileName, int progress) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'upload_channel_id',
      'Upload Progress',
      channelDescription: 'Shows the progress of file uploads',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true,
      autoCancel: false,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      2, // Unique ID for upload notification
      'Uploading $fileName',
      'Upload in progress: $progress%',
      platformChannelSpecifics,
    );
  }

  Future<void> _showUploadCompletionNotification(String fileName) async {
    await flutterLocalNotificationsPlugin.cancel(2);

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'upload_completion_channel_id',
      'Upload Complete',
      channelDescription: 'Notifies when an upload is finished',
      importance: Importance.high,
      priority: Priority.high,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      3, 
      'Upload Complete',
      'The file "$fileName" has been uploaded successfully.',
      platformChannelSpecifics,
    );
  }

  Future<void> _showProgressNotification(String fileName, int progress) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'download_channel_id',
      'Download Progress',
      channelDescription: 'Shows the progress of file downloads',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
    );

    final NotificationDetails platformChannelSpecifics =
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

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      1,
      'Download Complete',
      'The file "$fileName" has been downloaded successfully.',
      platformChannelSpecifics,
    );
  }
  
  Future<CollectionReference<Map<String, dynamic>>> _getCurrentCollectionRef(String collectionName) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception("User not authenticated or email missing.");
    }
    return _firestore.collection('users').doc(user.email).collection(collectionName);
  }

  void _fetchAndCacheAllData() async {
    if (!mounted) return;
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
      final userDoc = await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      if (uid == null) throw Exception("UID not found in user document.");

      final filesCollectionRef = _firestore.collection('users').doc(user.email).collection('files');
      final foldersCollectionRef = _firestore.collection('users').doc(user.email).collection('folders');

      // For search: fetch ALL files and folders, not just current level
      Query filesQuery = filesCollectionRef.where('ownerId', isEqualTo: uid);
      Query foldersQuery = foldersCollectionRef.where('ownerId', isEqualTo: uid);

      // Only filter by parentFolderId when NOT searching
      if (_searchQuery.isEmpty) {
        final queryParentId = _currentFolderId;
        if (queryParentId == null) {
          filesQuery = filesQuery.where('parentFolderId', isEqualTo: null);
          foldersQuery = foldersQuery.where('parentFolderId', isEqualTo: null);
        } else {
          filesQuery = filesQuery.where('parentFolderId', isEqualTo: queryParentId);
          foldersQuery = foldersQuery.where('parentFolderId', isEqualTo: queryParentId);
        }
      }

      final filesSnapshot = await filesQuery.get();
      final foldersSnapshot = await foldersQuery.get();

      if (mounted) {
        setState(() {
          _allFiles = filesSnapshot.docs.map((doc) => FileData.fromFirestore(doc)).toList();
          _allFolders = foldersSnapshot.docs.map((doc) => FolderData.fromFirestore(doc)).toList();
        });
      }

    } catch (e) {
      debugPrint('Error fetching data: $e');
      _showSnackbar('Failed to load data. Please check your internet and application permissions.', success: false);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  void _onItemTapped(int index) {
    if (index == 0) {
      context.go('/faculty_home');
    } else if (index == 1) {
      context.go('/faculty_courses');
    } else if (index == 2) {
      context.go('/faculty_my_files');
    } else if (index == 3) {
      context.go('/faculty_profile');
    }
  }

  // --- File and Folder Management Functions ---

  Future<void> _uploadFile() async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        _showSnackbar('You must be logged in to upload files.', success: false);
        return;
      }

      // Get user UID from Firestore
      final userDoc = await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      final ownerName = userDoc.data()?['name'] ?? 'Unknown';
      
      if (uid == null) {
        _showSnackbar('Failed to get user information.', success: false);
        return;
      }

      // Let the user pick a single file
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result == null || result.files.isEmpty) {
        _showSnackbar("No file selected", success: false);
        return;
      }

      // Get the selected file path
      final filePath = result.files.single.path;
      if (filePath == null) {
        _showSnackbar("Cannot read the selected file", success: false);
        return;
      }

      final file = File(filePath);
      final fileName = result.files.single.name;
      final fileSize = result.files.single.size;
      final fileExtension = result.files.single.extension ?? '';

      // Create new file document in Firestore first to get the file ID
      final filesCollection = _firestore.collection('users').doc(user.email).collection('files');
      final newFileRef = filesCollection.doc();
      final newFileId = newFileRef.id;

      // Create storage reference with correct path matching the rules
      // uploads/{userId}/{fileId}/{fileName}
      final storageRef = _storage.ref().child('uploads/$uid/$newFileId/$fileName');

      _showSnackbar('Uploading file...');

      // Upload file with progress tracking
      final uploadTask = storageRef.putFile(file);
      
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes * 100).toInt();
        _showUploadProgressNotification(fileName, progress);
      });

      final snapshot = await uploadTask.whenComplete(() => null);

      // Get download URL
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Create FileData object
      final newFileData = FileData(
        id: newFileId,
        name: fileName,
        url: downloadUrl,
        ownerId: uid,
        ownerName: ownerName,
        parentFolderId: _currentFolderId,
        sharedWith: [],
        uploadedAt: Timestamp.now(),
        size: fileSize,
        type: fileExtension,
      );

      // Save file metadata to Firestore
      await newFileRef.set(newFileData.toMap());

      // If file is in a folder, update the folder's files array
      if (_currentFolderId != null && _currentFolderId!.isNotEmpty) {
        final foldersCollection = _firestore.collection('users').doc(user.email).collection('folders');
        final parentFolderRef = foldersCollection.doc(_currentFolderId);
        await parentFolderRef.update({
          'files': FieldValue.arrayUnion([newFileId])
        });
      }

      // Add to local list
      if (mounted) {
        setState(() {
          _allFiles.add(newFileData);
        });
      }

      await _showUploadCompletionNotification(fileName);
      _showSnackbar('File "$fileName" uploaded successfully!');

    } catch (e) {
      debugPrint("Error uploading file: $e");
      _showSnackbar('Failed to upload file: ${e.toString()}', success: false);
    }
  }
 
  Future<void> _createFolder(String folderName) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    try {
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
        ownerId: uid,
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
    } catch (e) {
      _showSnackbar('Failed to create folder: $e', success: false);
      debugPrint('Folder creation error: $e');
    }
  }
  
  Future<void> _deleteFile(FileData file) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      _showSnackbar('You must be logged in to delete files.', success: false);
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      if (uid == null) throw Exception("UID not found.");

      // Correct storage path matching the upload path
      final storagePath = 'uploads/$uid/${file.id}/${file.name}';
      final storageRef = _storage.ref().child(storagePath);

      try {
        await storageRef.delete();
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          debugPrint('File not found in storage, but proceeding to delete Firestore record.');
        } else {
          throw e;
        }
      }

      final filesCollection = await _getCurrentCollectionRef('files');
      await filesCollection.doc(file.id).delete();

      setState(() {
        _allFiles.removeWhere((f) => f.id == file.id);
      });

      _showSnackbar('File deleted successfully!');

    } catch (e) {
      _showSnackbar('Failed to delete file: ${e.toString()}', success: false);
      debugPrint('Delete file error: $e');
    }
  }

  Future<void> _deleteFolder(FolderData folder) async {
  // Show a confirmation dialog first, as this is a destructive action.
  final bool? confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Folder?'),
      content: Text(
        'Are you sure you want to permanently delete "${folder.name}" and ALL of its contents? This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirm != true) {
    return; // User cancelled the operation
  }

  // --- Deletion Logic Starts ---
  try {
    _showSnackbar('Deleting folder...');
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final userDoc = await _firestore.collection('users').doc(user.email).get();
    final uid = userDoc.data()?['uid'];
    if (uid == null) throw Exception("UID not found.");

    final foldersCollection = _firestore.collection('users').doc(user.email).collection('folders');
    final filesCollection = _firestore.collection('users').doc(user.email).collection('files');

    // This is our recursive helper function
    Future<void> deleteRecursively(String folderId) async {
      // 1. Find and delete all files directly inside the current folder
      final filesSnapshot = await filesCollection.where('parentFolderId', isEqualTo: folderId).get();
      for (final fileDoc in filesSnapshot.docs) {
        final fileData = FileData.fromFirestore(fileDoc);
        
        // Delete from Firebase Storage
        final storagePath = 'uploads/$uid/${fileData.id}/${fileData.name}';
        try {
          await _storage.ref().child(storagePath).delete();
        } catch (e) {
          debugPrint('Could not delete file from storage (may already be gone): ${fileData.name}, Error: $e');
        }
        
        // Delete from Firestore
        await fileDoc.reference.delete();
      }

      // 2. Find all subfolders directly inside the current folder
      final subfoldersSnapshot = await foldersCollection.where('parentFolderId', isEqualTo: folderId).get();
      
      // 3. Call this function again for each subfolder
      for (final subfolderDoc in subfoldersSnapshot.docs) {
        await deleteRecursively(subfolderDoc.id);
      }

      // 4. After all children are deleted, delete the current folder itself
      await foldersCollection.doc(folderId).delete();
    }

    // Start the recursive deletion process from the top-level folder
    await deleteRecursively(folder.id);

    // Update the UI immediately for a responsive feel
    if (mounted) {
      _fetchAndCacheAllData(); // Refresh all data to ensure consistency
    }

    _showSnackbar('Folder "${folder.name}" and all its contents deleted successfully!');
  } catch (e) {
    _showSnackbar('Failed to delete folder: ${e.toString()}', success: false);
    debugPrint('Delete folder error: $e');
  }
}

  Future<void> _renameItem(String itemId, String oldName, String newName, String type) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return;
      if (oldName == newName) return;

      final targetCollection = await _getCurrentCollectionRef(type == 'File' ? 'files' : 'folders');
      final itemRef = targetCollection.doc(itemId);
      
      await itemRef.update({'name': newName});
      
      setState(() {
        if (type == 'File') {
          final index = _allFiles.indexWhere((f) => f.id == itemId);
          if (index != -1) {
            _allFiles[index] = _allFiles[index].copyWith(name: newName); 
          }
        } else {
          final index = _allFolders.indexWhere((f) => f.id == itemId);
          if (index != -1) {
            _allFolders[index] = _allFolders[index].copyWith(name: newName); 
          }
        }
      });
      
      _showSnackbar('Successfully renamed!');
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }
  
  void _openFolder(String folderId, String folderName) {
    context.push('/faculty_my_files/$folderId', extra: folderName);
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

  String _formatBytes(int bytes, [int decimals = 0]) {
    if (bytes <= 0) return "0 B";
    const suffixes = [' B', ' KB', ' MB', ' GB', ' TB'];
    var i = (math.log(bytes) / math.log(1024)).floor(); 
    
    if (i < 0) i = 0;
    if (i >= suffixes.length) i = suffixes.length - 1;

    return ((bytes / (1 << (i * 10))).toStringAsFixed(decimals)) + suffixes[i];
  }
  
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
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                        // Refetch data to search globally
                        _fetchAndCacheAllData();
                      },
                      decoration: const InputDecoration(
                        icon: Icon(Icons.search, color: Colors.grey),
                        hintText: 'Search all files and folders',
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
              content: Text('Are you sure you want to delete "$itemName"? This action cannot be undone.'),
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
                   decoration: const InputDecoration(hintText: 'New name'),
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
          _showSnackbar('Move operation is not yet implemented.', success: false);
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
      _showSnackbar('File downloaded successfully to the GradeMate folder!');
      
    } catch (e) {
      _showSnackbar('Error during download: ${e.toString()}', success: false);
    }
  }

  Future<void> _shareFile(FileData file) async {
    try {
      final dio = Dio();
      final dir = await getTemporaryDirectory();
      final tempFilePath = '${dir.path}/${file.name}';
      
      _showSnackbar('Preparing file for sharing...');
      await dio.download(file.url, tempFilePath);

      await Share.shareXFiles([XFile(tempFilePath)], text: 'Check out this file from GradeMate: ${file.name}');

    } catch (e) {
      _showSnackbar('Failed to share file: ${e.toString()}', success: false);
    }
  }
}