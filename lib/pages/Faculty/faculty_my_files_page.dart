import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:grademate/models/file_models.dart';
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
  String _searchQuery = '';
  String _searchTab = 'All'; // 'All', 'Files', 'Folders'

  String? _currentFolderId;
  String? _currentFolderName;
  String? userName;

  List<FolderData> _directoryFolders = [];
  List<FileData> _directoryFiles = [];
  List<FolderData> _allUserFolders = [];
  List<FileData> _allUserFiles = [];

  bool _isLoading = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _currentFolderId = widget.folderId;
    _currentFolderName = widget.folderName ?? 'My Files';
    _loadUserData();
    _loadInitialData();
    _initializeNotifications();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(user.email).get();
        if (mounted && userDoc.exists) {
          setState(() {
            userName = userDoc.data()?['name'];
          });
        }
      } catch (e) {
        print("Error loading user data: $e");
      }
    }
  }

  // --- Activity Logging ---
  Future<void> _logActivity(String action, Map<String, dynamic> details) async {
    if (_auth.currentUser == null || _auth.currentUser!.email == null) return;

    final userEmail = _auth.currentUser!.email!;
    final activityData = {
      'userEmail': userEmail,
      'userName': userName ?? 'Unknown',
      'action': action,
      'timestamp': FieldValue.serverTimestamp(),
      'details': details,
    };

    try {
      // Log to the main activities collection
      await _firestore.collection('activities').add(activityData);

      // Log to the user-specific activities subcollection
      await _firestore
          .collection('users')
          .doc(userEmail)
          .collection('activities')
          .add(activityData);
    } catch (e) {
      print("Error logging activity: $e");
    }
  }

  void _onSearchChanged() {
    // Cancel previous timer
    _debounceTimer?.cancel();

    // Start new timer - only search after user stops typing for 300ms
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
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

  Future<void> _showUploadProgressNotification(
      String fileName, int progress) async {
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
      2,
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

  Future<CollectionReference<Map<String, dynamic>>> _getCurrentCollectionRef(
      String collectionName) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception("User not authenticated or email missing.");
    }
    return _firestore
        .collection('users')
        .doc(user.email)
        .collection(collectionName);
  }

  Future<void> _loadInitialData() async {
    await _cacheAllUserData();
    await _loadDirectoryContents();
  }

  Future<void> _loadDirectoryContents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final userDoc =
          await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      if (uid == null) throw Exception("UID not found.");

      final filesRef =
          _firestore.collection('users').doc(user.email).collection('files');
      final foldersRef =
          _firestore.collection('users').doc(user.email).collection('folders');

      Query filesQuery = filesRef
          .where('ownerId', isEqualTo: uid)
          .where('parentFolderId', isEqualTo: _currentFolderId);
      Query foldersQuery = foldersRef
          .where('ownerId', isEqualTo: uid)
          .where('parentFolderId', isEqualTo: _currentFolderId);

      final filesSnapshot = await filesQuery.get();
      final foldersSnapshot = await foldersQuery.get();

      if (mounted) {
        setState(() {
          _directoryFiles =
              filesSnapshot.docs.map((doc) => FileData.fromFirestore(doc)).toList();
          _directoryFolders = foldersSnapshot.docs
              .map((doc) => FolderData.fromFirestore(doc))
              .toList();
        });
      }
    } catch (e) {
      _showSnackbar('Failed to load directory: $e', success: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cacheAllUserData() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    try {
      final userDoc =
          await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      if (uid == null) throw Exception("UID not found.");

      final filesRef =
          _firestore.collection('users').doc(user.email).collection('files');
      final foldersRef =
          _firestore.collection('users').doc(user.email).collection('folders');

      final filesSnapshot =
          await filesRef.where('ownerId', isEqualTo: uid).get();
      final foldersSnapshot =
          await foldersRef.where('ownerId', isEqualTo: uid).get();

      if (mounted) {
        _allUserFiles =
            filesSnapshot.docs.map((doc) => FileData.fromFirestore(doc)).toList();
        _allUserFolders = foldersSnapshot.docs
            .map((doc) => FolderData.fromFirestore(doc))
            .toList();
      }
    } catch (e) {
      debugPrint("Error caching all user data: $e");
    }
  }

  Future<void> _uploadFile() async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        _showSnackbar('You must be logged in to upload files.', success: false);
        return;
      }

      final userDoc =
          await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      final ownerName = userDoc.data()?['name'] ?? 'Unknown';

      if (uid == null) {
        _showSnackbar('Failed to get user information.', success: false);
        return;
      }

      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result == null || result.files.isEmpty) {
        _showSnackbar("No file selected", success: false);
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        _showSnackbar("Cannot read the selected file", success: false);
        return;
      }

      final file = File(filePath);
      final fileName = result.files.single.name;
      final fileSize = result.files.single.size;
      final fileExtension = result.files.single.extension ?? '';

      final filesCollection =
          _firestore.collection('users').doc(user.email).collection('files');
      final newFileRef = filesCollection.doc();
      final newFileId = newFileRef.id;

      final storageRef =
          _storage.ref().child('uploads/$uid/$newFileId/$fileName');

      _showSnackbar('Uploading file...');

      final uploadTask = storageRef.putFile(file);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress =
            (snapshot.bytesTransferred / snapshot.totalBytes * 100).toInt();
        _showUploadProgressNotification(fileName, progress);
      });

      final snapshot = await uploadTask.whenComplete(() => null);
      final downloadUrl = await snapshot.ref.getDownloadURL();

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

      await newFileRef.set(newFileData.toMap());
      await _logActivity('Uploaded My File',
          {'fileName': fileName, 'parentFolder': _currentFolderName});

      if (_currentFolderId != null && _currentFolderId!.isNotEmpty) {
        final foldersCollection =
            _firestore.collection('users').doc(user.email).collection('folders');
        final parentFolderRef = foldersCollection.doc(_currentFolderId);
        await parentFolderRef
            .update({'files': FieldValue.arrayUnion([newFileId])});
      }

      if (mounted) {
        setState(() {
          _directoryFiles.add(newFileData);
          _allUserFiles.add(newFileData);
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
      final userDoc =
          await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      if (uid == null) throw Exception("UID not found in user document.");

      final userFoldersCollection =
          _firestore.collection('users').doc(user.email).collection('folders');
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
      await _logActivity('Created My Folder',
          {'folderName': folderName, 'parentFolder': _currentFolderName});

      if (_currentFolderId != null && _currentFolderId!.isNotEmpty) {
        final parentFolderRef = userFoldersCollection.doc(_currentFolderId);
        await parentFolderRef
            .update({'folders': FieldValue.arrayUnion([newFolderId])});
      }

      setState(() {
        _directoryFolders.add(newFolderData);
        _allUserFolders.add(newFolderData);
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
      final userDoc =
          await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      if (uid == null) throw Exception("UID not found.");

      final storagePath = 'uploads/$uid/${file.id}/${file.name}';
      final storageRef = _storage.ref().child(storagePath);

      try {
        await storageRef.delete();
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          debugPrint(
              'File not found in storage, but proceeding to delete Firestore record.');
        } else {
          throw e;
        }
      }

      final filesCollection = await _getCurrentCollectionRef('files');
      await filesCollection.doc(file.id).delete();
      await _logActivity('Deleted My File',
          {'fileName': file.name, 'parentFolder': _currentFolderName});

      setState(() {
        _directoryFiles.removeWhere((f) => f.id == file.id);
        _allUserFiles.removeWhere((f) => f.id == file.id);
      });

      _showSnackbar('File deleted successfully!');
    } catch (e) {
      _showSnackbar('Failed to delete file: ${e.toString()}', success: false);
      debugPrint('Delete file error: $e');
    }
  }

  Future<void> _deleteFolder(FolderData folder) async {
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

    if (confirm != true) return;

    try {
      _showSnackbar('Deleting folder...');
      final user = _auth.currentUser;
      if (user == null || user.email == null) return;

      final userDoc =
          await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      if (uid == null) throw Exception("UID not found.");

      final foldersCollection =
          _firestore.collection('users').doc(user.email).collection('folders');
      final filesCollection =
          _firestore.collection('users').doc(user.email).collection('files');

      Future<void> deleteRecursively(String folderId) async {
        final filesSnapshot =
            await filesCollection.where('parentFolderId', isEqualTo: folderId).get();
        for (final fileDoc in filesSnapshot.docs) {
          final fileData = FileData.fromFirestore(fileDoc);

          final storagePath = 'uploads/$uid/${fileData.id}/${fileData.name}';
          try {
            await _storage.ref().child(storagePath).delete();
          } catch (e) {
            debugPrint(
                'Could not delete file from storage (may already be gone): ${fileData.name}, Error: $e');
          }

          await fileDoc.reference.delete();
        }

        final subfoldersSnapshot = await foldersCollection
            .where('parentFolderId', isEqualTo: folderId)
            .get();

        for (final subfolderDoc in subfoldersSnapshot.docs) {
          await deleteRecursively(subfolderDoc.id);
        }

        await foldersCollection.doc(folderId).delete();
      }

      await deleteRecursively(folder.id);
      await _logActivity('Deleted My Folder', {'folderName': folder.name});
      await _loadInitialData();
      _showSnackbar(
          'Folder "${folder.name}" and all its contents deleted successfully!');
    } catch (e) {
      _showSnackbar('Failed to delete folder: ${e.toString()}', success: false);
      debugPrint('Delete folder error: $e');
    }
  }

  Future<void> _renameItem(
      String itemId, String oldName, String newName, String type) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return;
      if (oldName == newName) return;

      final targetCollection =
          await _getCurrentCollectionRef(type == 'File' ? 'files' : 'folders');
      await targetCollection.doc(itemId).update({'name': newName});
      await _logActivity('Renamed My Item',
          {'type': type, 'oldName': oldName, 'newName': newName});

      setState(() {
        if (type == 'File') {
          int dirIndex = _directoryFiles.indexWhere((f) => f.id == itemId);
          if (dirIndex != -1)
            _directoryFiles[dirIndex] =
                _directoryFiles[dirIndex].copyWith(name: newName);
          int allIndex = _allUserFiles.indexWhere((f) => f.id == itemId);
          if (allIndex != -1)
            _allUserFiles[allIndex] =
                _allUserFiles[allIndex].copyWith(name: newName);
        } else {
          int dirIndex = _directoryFolders.indexWhere((f) => f.id == itemId);
          if (dirIndex != -1)
            _directoryFolders[dirIndex] =
                _directoryFolders[dirIndex].copyWith(name: newName);
          int allIndex = _allUserFolders.indexWhere((f) => f.id == itemId);
          if (allIndex != -1)
            _allUserFolders[allIndex] =
                _allUserFolders[allIndex].copyWith(name: newName);
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
    if (_searchQuery.isNotEmpty) {
      // Find the parent folder for search results to display a more useful path
      final parentFolderId = item.parentFolderId;
      if (parentFolderId == null) {
        return 'My Files';
      }
      final parentFolder =
          _allUserFolders.where((f) => f.id == parentFolderId).firstOrNull;
      return parentFolder?.name ?? 'My Files';
    }
    if (_currentFolderId == null) {
      return 'My Files';
    } else {
      return _currentFolderName ?? 'Unknown';
    }
  }

  List<dynamic> _getFilteredItems() {
    final lowerCaseQuery = _searchQuery.toLowerCase();
    List<dynamic> itemsToDisplay;

    if (lowerCaseQuery.isNotEmpty) {
      // Search from all user data (cached)
      final filteredFolders = _allUserFolders
          .where((folder) => folder.name.toLowerCase().contains(lowerCaseQuery));
      final filteredFiles = _allUserFiles
          .where((file) => file.name.toLowerCase().contains(lowerCaseQuery));
      itemsToDisplay = [...filteredFolders, ...filteredFiles];
    } else {
      // Show current directory contents
      itemsToDisplay = [..._directoryFolders, ..._directoryFiles];
    }

    // Apply tab filter
    if (_searchTab != 'All') {
      itemsToDisplay = itemsToDisplay.where((item) {
        if (_searchTab == 'Files') return item is FileData;
        if (_searchTab == 'Folders') return item is FolderData;
        return false;
      }).toList();
    }

    // Sort: folders first, then alphabetically
    itemsToDisplay.sort((a, b) {
      if (a is FolderData && b is FileData) return -1;
      if (a is FileData && b is FolderData) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return itemsToDisplay;
  }

  String _formatBytes(int bytes, [int decimals = 0]) {
    if (bytes <= 0) return "0 B";
    const suffixes = [' B', ' KB', ' MB', ' GB', ' TB'];
    var i = (math.log(bytes) / math.log(1024)).floor();

    if (i < 0) i = 0;
    if (i >= suffixes.length) i = suffixes.length - 1;

    return ((bytes / (1 << (i * 10))).toStringAsFixed(decimals)) + suffixes[i];
  }

  Widget _buildAddItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: Colors.blue[800]),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
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
        title: Text(
          _currentFolderName ?? 'My Files',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.black),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Add Content"),
                  content: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.height * 0.15,
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      children: [
                        _buildAddItem(Icons.create_new_folder_outlined,
                            'New Folder', () {
                          Navigator.pop(context);
                          _showCreateFolderDialog();
                        }),
                        _buildAddItem(Icons.upload_file, 'Upload File', () {
                          Navigator.pop(context);
                          _uploadFile();
                        }),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              // Search Bar - Always visible
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search, color: Colors.grey),
                    hintText: 'Search all files and folders',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Tab Selector - Always visible
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['All', 'Files', 'Folders'].map((tab) {
                  final isSelected = _searchTab == tab;
                  return GestureDetector(
                    onTap: () => setState(() => _searchTab = tab),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Content Area
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredItems.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchQuery.isNotEmpty
                                      ? Icons.search_off
                                      : Icons.folder_open,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'No files or folders here.\nTap the + button to create one.'
                                      : 'No results found for "$_searchQuery"',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
      ),
    );
  }

  Widget _buildFolderTile(FolderData folder, String path) {
    return ListTile(
      leading: Icon(Icons.folder_outlined, color: Colors.blue[800], size: 40),
      title: Text(
        folder.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        path,
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      trailing: _buildItemPopupMenu('Folder', folder),
      onTap: () => _openFolder(folder.id, folder.name),
    );
  }

  Widget _buildFileTile(FileData file, String path) {
    return ListTile(
      leading: Icon(_getFileIcon(file.type), color: Colors.blue[800], size: 40),
      title: Text(
        file.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${_formatBytes(file.size)}',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
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
              content: Text(
                  'Are you sure you want to delete "$itemName"? This action cannot be undone.'),
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
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
        } else if (value == 'rename') {
          final TextEditingController controller =
              TextEditingController(text: itemName);
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
              leading: Icon(
                  type == 'Folder' ? Icons.folder_open : Icons.open_in_new),
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
              leading: Icon(Icons.delete_outline, color: Colors.red),
              title: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ),
        ];

        if (type == 'File') {
          items.insertAll(1, [
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
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image_outlined;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.video_file_outlined;
      case 'zip':
      case 'rar':
        return Icons.folder_zip_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Future<void> _downloadFile(FileData file) async {
    try {
      final dio = Dio();
      final Directory? baseDownloadDir = await getExternalStorageDirectory();
      if (baseDownloadDir == null) {
        _showSnackbar('Failed to find a valid download directory.',
            success: false);
        return;
      }
      final Directory gradeMateDir =
          Directory('${baseDownloadDir.path}${Platform.pathSeparator}GradeMate');

      if (!await gradeMateDir.exists()) {
        try {
          await gradeMateDir.create(recursive: true);
        } catch (e) {
          _showSnackbar('Failed to create folder. Cannot download.',
              success: false);
          return;
        }
      }

      final filePath =
          '${gradeMateDir.path}${Platform.pathSeparator}${file.name}';

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

      await Share.shareXFiles([XFile(tempFilePath)],
          text: 'Check out this file from GradeMate: ${file.name}');
    } catch (e) {
      _showSnackbar('Failed to share file: ${e.toString()}', success: false);
    }
  }
}