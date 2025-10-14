import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:grademate/models/file_models.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

class StudentMyFilesPage extends StatefulWidget {
  final String? folderId;
  final String? folderName;

  const StudentMyFilesPage({super.key, this.folderId, this.folderName});

  @override
  State<StudentMyFilesPage> createState() => _StudentMyFilesPageState();
}

class _StudentMyFilesPageState extends State<StudentMyFilesPage> {
  String _searchQuery = '';
  String _searchTab = 'All'; // 'All', 'Files', 'Folders'

  String? _currentFolderId;
  String? _currentFolderName;
  String? userName;

  List<FolderData> _allUserFolders = [];
  List<FileData> _allUserFiles = [];
  List<String> _favoriteFileIds = [];
  List<Map<String, String?>> _folderPath = [];

  bool _isLoading = true;

  bool _isSelectionMode = false;
  final Set<String> _selectedItems = {};

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
    _initializeNotifications();
    _searchController.addListener(_onSearchChanged);
    _loadInitialData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _loadUserData();
    await _loadAllItems();
    await _buildFolderPath(_currentFolderId);
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(user.email).get();
        if (mounted && userDoc.exists) {
          final data = userDoc.data();
          setState(() {
            userName = data?['name'];
            _favoriteFileIds = List<String>.from(data?['favorites'] ?? []);
          });
        }
      } catch (e) {
        print("Error loading user data: $e");
      }
    }
  }

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
      await _firestore.collection('activities').add(activityData);
      await _firestore
          .collection('users')
          .doc(userEmail)
          .collection('activities')
          .add(activityData);
    } catch (e) {
      print("Error logging activity: $e");
    }
  }

  Future<bool> _isConnected() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      if (mounted) {
        _showSnackbar('❌ No internet connection. Please check your network.',
            success: false);
      }
      return false;
    }
    return true;
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
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
      2, 'Uploading $fileName', 'Upload in progress: $progress%', platformChannelSpecifics,
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
      3, 'Upload Complete', 'The file "$fileName" has been uploaded successfully.', platformChannelSpecifics,
    );
  }
  
  Future<void> _showVerificationNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'verification_channel_id',
      'Image Verification',
      channelDescription: 'Shows the progress of image verification',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      indeterminate: true,
      ongoing: true,
      autoCancel: false,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      4, 'Verifying Image', 'Please wait while we check the content...', platformChannelSpecifics,
    );
  }

  Future<void> _cancelVerificationNotification() async {
    await flutterLocalNotificationsPlugin.cancel(4);
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
      0, 'Downloading $fileName', 'Download in progress: $progress%', platformChannelSpecifics,
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
      1, 'Download Complete', 'The file "$fileName" has been downloaded successfully.', platformChannelSpecifics,
    );
  }

  Future<void> _loadAllItems() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final userDoc = await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      if (uid == null) throw Exception("UID not found.");
      final filesRef = _firestore.collection('users').doc(user.email).collection('files');
      final foldersRef = _firestore.collection('users').doc(user.email).collection('folders');
      final filesSnapshot = await filesRef.where('ownerId', isEqualTo: uid).get();
      final foldersSnapshot = await foldersRef.where('ownerId', isEqualTo: uid).get();
      if (mounted) {
        setState(() {
          _allUserFiles = filesSnapshot.docs.map((doc) => FileData.fromFirestore(doc)).toList();
          _allUserFolders = foldersSnapshot.docs.map((doc) => FolderData.fromFirestore(doc)).toList();
        });
      }
    } catch (e) {
      _showSnackbar('Failed to load files: $e', success: false);
      debugPrint("Error loading all items: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _verifyImageIsStudyMaterial(File imageFile) async {
    await _showVerificationNotification();
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      // IMPORTANT: Replace with your actual API key.
      final apiKey = dotenv.env['GEMINI_API_KEY']; 
      
      // CORRECTED: Using the correct model name for this type of request.
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-05-20:generateContent?key=$apiKey');

      final prompt = """
      You are an expert academic content verifier. Your task is to determine if an image is educational material.
      
      **VALID study material includes:**
      - Handwritten notes, even if they are on a clipboard or piece of paper.
      - A screenshot of text from a website, article, or document.
      - A page from a book, textbook, or a presentation slide.
      - Academic diagrams, charts, graphs, or mathematical formulas.
      - A resume or curriculum vitae.

      **INVALID content includes:**
      - Photos of people (selfies, group photos), unless they are part of a presentation slide.
      - Pictures of places, buildings, or landscapes.
      - Photos of animals or objects without any academic text or context.

      Analyze the provided image strictly based on these rules. Respond with a single word: 'YES' if it is valid study material, or 'NO' if it is not.
      """;

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
                {'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image}}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final text = body['candidates'][0]['content']['parts'][0]['text'];
        return text.trim().toUpperCase() == 'YES';
      } else {
         _showSnackbar('Image verification failed: ${response.body}', success: false);
        return false;
      }
    } catch (e) {
      _showSnackbar('Error during image verification: $e', success: false);
      return false;
    } finally {
      await _cancelVerificationNotification();
    }
  }


  Future<void> _uploadFile() async {
    if (!await _isConnected()) return;
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        _showSnackbar('You must be logged in to upload files.', success: false);
        return;
      }
      final userDoc = await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      final ownerName = userDoc.data()?['name'] ?? 'Unknown';
      if (uid == null) {
        _showSnackbar('Failed to get user information.', success: false);
        return;
      }
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'txt', 'zip', 'rar'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.single.path;
      if (filePath == null) {
        _showSnackbar("Cannot read the selected file", success: false);
        return;
      }
      final file = File(filePath);
      final fileName = result.files.single.name;
      final fileExtension = result.files.single.extension?.toLowerCase() ?? '';

      if (['jpg', 'jpeg', 'png'].contains(fileExtension)) {
        final isStudyMaterial = await _verifyImageIsStudyMaterial(file);
        if (!isStudyMaterial) {
          _showSnackbar('Image rejected. Please upload only study-related materials.', success: false);
          return;
        }
      }

      final fileSize = result.files.single.size;
      final filesCollection = _firestore.collection('users').doc(user.email).collection('files');
      final newFileRef = filesCollection.doc();
      final newFileId = newFileRef.id;
      final storageRef = _storage.ref().child('uploads/$uid/$newFileId/$fileName');
      _showSnackbar('Uploading file...');
      final uploadTask = storageRef.putFile(file);
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes * 100).toInt();
        _showUploadProgressNotification(fileName, progress);
      });
      final snapshot = await uploadTask.whenComplete(() => null);
      final downloadUrl = await snapshot.ref.getDownloadURL();
      final newFileData = FileData(
        id: newFileId, name: fileName, url: downloadUrl, ownerId: uid, ownerName: ownerName,
        parentFolderId: _currentFolderId, sharedWith: [], uploadedAt: Timestamp.now(), size: fileSize, type: fileExtension,
      );
      final batch = _firestore.batch();
      batch.set(newFileRef, newFileData.toMap());
      if (_currentFolderId != null && _currentFolderId!.isNotEmpty) {
        final foldersCollection = _firestore.collection('users').doc(user.email).collection('folders');
        final parentFolderRef = foldersCollection.doc(_currentFolderId);
        batch.update(parentFolderRef, {'files': FieldValue.arrayUnion([newFileId])});
      }
      await batch.commit();
      await _logActivity('Uploaded File', {'fileName': fileName, 'parentFolder': _currentFolderName});
      if (mounted) {
        setState(() => _allUserFiles.add(newFileData));
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
      if (uid == null) throw Exception("UID not found.");
      final userFoldersCollection = _firestore.collection('users').doc(user.email).collection('folders');
      final newFolderRef = userFoldersCollection.doc();
      final newFolderId = newFolderRef.id;
      final ownerName = userDoc.data()?['name'] ?? 'Unknown';
      final newFolderData = FolderData(
        id: newFolderId, name: folderName, ownerId: uid, ownerName: ownerName, parentFolderId: _currentFolderId,
        sharedWith: [], createdAt: Timestamp.now(), files: [], folders: [],
      );
      final batch = _firestore.batch();
      batch.set(newFolderRef, newFolderData.toMap());
      if (_currentFolderId != null && _currentFolderId!.isNotEmpty) {
        final parentFolderRef = userFoldersCollection.doc(_currentFolderId);
        batch.update(parentFolderRef, {'folders': FieldValue.arrayUnion([newFolderId])});
      }
      await batch.commit();
      await _logActivity('Created Folder', {'folderName': folderName, 'parentFolder': _currentFolderName});
      if (mounted) {
        setState(() => _allUserFolders.add(newFolderData));
      }
      _showSnackbar('Folder "$folderName" created successfully!');
    } catch (e) {
      _showSnackbar('Failed to create folder: $e', success: false);
      debugPrint('Folder creation error: $e');
    }
  }

  Future<void> _renameItem(String itemId, String oldName, String newName, String type) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return;
      if (oldName == newName) return;
      final targetCollection = _firestore.collection('users').doc(user.email).collection(type == 'File' ? 'files' : 'folders');
      await targetCollection.doc(itemId).update({'name': newName});
      await _logActivity('Renamed Item', {'type': type, 'oldName': oldName, 'newName': newName});
      setState(() {
        if (type == 'File') {
          int allIndex = _allUserFiles.indexWhere((f) => f.id == itemId);
          if (allIndex != -1) _allUserFiles[allIndex] = _allUserFiles[allIndex].copyWith(name: newName);
        } else {
          int allIndex = _allUserFolders.indexWhere((f) => f.id == itemId);
          if (allIndex != -1) _allUserFolders[allIndex] = _allUserFolders[allIndex].copyWith(name: newName);
        }
      });
      _showSnackbar('Successfully renamed!');
    } catch (e) {
      _showSnackbar('Failed to rename: ${e.toString()}', success: false);
    }
  }

  Future<bool?> _showDeleteConfirmationDialog(String itemName, String itemType) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $itemType?'),
        content: Text('Are you sure you want to permanently delete "$itemName"? ${itemType == 'Folder' ? 'This includes ALL of its contents. ' : ''}This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Future<void> _performFileDelete(FileData file) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) throw Exception('User not logged in.');
    final userDoc = await _firestore.collection('users').doc(user.email).get();
    final uid = userDoc.data()?['uid'];
    if (uid == null) throw Exception("UID not found.");

    final userRef = _firestore.collection('users').doc(user.email);
    final fileRefPath = 'users/${user.email}/files/${file.id}';
    await userRef.update({
      'favorites': FieldValue.arrayRemove([fileRefPath]),
      'recentlyAccessed': FieldValue.arrayRemove([fileRefPath]),
    });


    if (file.type != 'link') {
      final storagePath = 'uploads/$uid/${file.id}/${file.name}';
      final storageRef = _storage.ref().child(storagePath);
      try {
        await storageRef.delete();
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          debugPrint('File not found in storage, proceeding to delete Firestore record.');
        } else {
          rethrow;
        }
      }
    }
    final filesCollection = _firestore.collection('users').doc(user.email).collection('files');
    await filesCollection.doc(file.id).delete();
    if (!_isSelectionMode) {
      await _logActivity('Deleted File', {'fileName': file.name, 'parentFolder': _currentFolderName});
    }
  }

  Future<void> _deleteFile(FileData file) async {
    final bool? confirm = await _showDeleteConfirmationDialog(file.name, 'File');
    if (confirm != true) return;
    try {
      _showSnackbar('Deleting file...');
      await _performFileDelete(file);
      _showSnackbar('File deleted successfully!');
      await _loadAllItems();
    } catch (e) {
      _showSnackbar('Failed to delete file: ${e.toString()}', success: false);
    }
  }

  Future<void> _performFolderDelete(FolderData folder) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) throw Exception('User not logged in.');
    final userDoc = await _firestore.collection('users').doc(user.email).get();
    final uid = userDoc.data()?['uid'];
    if (uid == null) throw Exception("UID not found.");
    final foldersCollection = _firestore.collection('users').doc(user.email).collection('folders');
    final filesCollection = _firestore.collection('users').doc(user.email).collection('files');
    Future<void> deleteRecursively(String folderId) async {
      final filesSnapshot = await filesCollection.where('parentFolderId', isEqualTo: folderId).get();
      for (final fileDoc in filesSnapshot.docs) {
        final fileData = FileData.fromFirestore(fileDoc);
        await _performFileDelete(fileData);
      }
      final subfoldersSnapshot = await foldersCollection.where('parentFolderId', isEqualTo: folderId).get();
      for (final subfolderDoc in subfoldersSnapshot.docs) {
        await deleteRecursively(subfolderDoc.id);
      }
      await foldersCollection.doc(folderId).delete();
    }
    await deleteRecursively(folder.id);
    if (!_isSelectionMode) {
      await _logActivity('Deleted Folder', {'folderName': folder.name});
    }
  }

  Future<void> _deleteFolder(FolderData folder) async {
    final bool? confirm = await _showDeleteConfirmationDialog(folder.name, 'Folder');
    if (confirm != true) return;
    try {
      _showSnackbar('Deleting folder...');
      await _performFolderDelete(folder);
      _showSnackbar('Folder "${folder.name}" and all its contents deleted successfully!');
      await _loadAllItems();
    } catch (e) {
      _showSnackbar('Failed to delete folder: ${e.toString()}', success: false);
    }
  }

  Future<void> _confirmDeleteSelected() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_selectedItems.length} items?'),
        content: const Text('Are you sure you want to permanently delete the selected items? This includes all contents of selected folders. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _deleteSelectedItems();
    }
  }

  Future<void> _deleteSelectedItems() async {
    _showSnackbar('Deleting selected items...');
    setState(() => _isLoading = true);
    final itemsToDelete = Set<String>.from(_selectedItems);
    List<FileData> filesToDelete = _allUserFiles.where((file) => itemsToDelete.contains(file.id)).toList();
    List<FolderData> foldersToDelete = _allUserFolders.where((folder) => itemsToDelete.contains(folder.id)).toList();
    try {
      for (final file in filesToDelete) {
        await _performFileDelete(file);
      }
      for (final folder in foldersToDelete) {
        await _performFolderDelete(folder);
      }
      _showSnackbar('Selected items deleted successfully!');
      await _logActivity('Deleted Multiple Items', {'count': itemsToDelete.length});
    } catch (e) {
      _showSnackbar('An error occurred during deletion: $e', success: false);
    } finally {
      setState(() {
        _selectedItems.clear();
        _isSelectionMode = false;
      });
      await _loadAllItems();
    }
  }

  Future<void> _showCreateFolderDialog() async {
    final TextEditingController controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create New Folder'),
          content: TextField(controller: controller, decoration: const InputDecoration(hintText: "Folder Name"), autofocus: true),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              child: const Text('Create'),
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  _createFolder(controller.text.trim());
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
      SnackBar(content: Text(message), backgroundColor: success ? Colors.green : Colors.red),
    );
  }

  void _openFolder(String folderId, String folderName) {
    context.push('/student_my_files/$folderId', extra: folderName);
  }

  void _goBack() => context.pop();
  void _toggleSelection(String itemId) {
    setState(() {
      if (_selectedItems.contains(itemId)) {
        _selectedItems.remove(itemId);
      } else {
        _selectedItems.add(itemId);
      }
      if (_selectedItems.isEmpty) _isSelectionMode = false;
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedItems.clear();
    });
  }

  String _getItemPath(dynamic item) {
    if (_searchQuery.isNotEmpty) {
      final parentFolderId = item.parentFolderId;
      if (parentFolderId == null) return 'My Files';
      final parentFolder = _allUserFolders.where((f) => f.id == parentFolderId).firstOrNull;
      return parentFolder?.name ?? 'My Files';
    }
    return _currentFolderName ?? 'My Files';
  }

  List<dynamic> _getFilteredItems() {
    final lowerCaseQuery = _searchQuery.toLowerCase();
    List<dynamic> itemsToDisplay;
    if (lowerCaseQuery.isNotEmpty) {
      final filteredFolders = _allUserFolders.where((folder) => folder.name.toLowerCase().contains(lowerCaseQuery));
      final filteredFiles = _allUserFiles.where((file) => file.name.toLowerCase().contains(lowerCaseQuery));
      itemsToDisplay = [...filteredFolders, ...filteredFiles];
    } else {
      final currentFolders = _allUserFolders.where((folder) => folder.parentFolderId == _currentFolderId);
      final currentFiles = _allUserFiles.where((file) => file.parentFolderId == _currentFolderId);
      itemsToDisplay = [...currentFolders, ...currentFiles];
    }
    if (_searchTab != 'All') {
      itemsToDisplay = itemsToDisplay.where((item) {
        if (_searchTab == 'Files') return item is FileData;
        if (_searchTab == 'Folders') return item is FolderData;
        return false;
      }).toList();
    }
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

  AppBar _buildNormalAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: widget.folderId != null ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: _goBack) : null,
      title: Text(_currentFolderName ?? 'My Files', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.black),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Add Content"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(Icons.create_new_folder_outlined, color: Colors.blue[800]),
                      title: const Text('New Folder'),
                      onTap: (){
                         Navigator.pop(context);
                         _showCreateFolderDialog();
                      },
                    ),
                     ListTile(
                      leading: Icon(Icons.upload_file, color: Colors.blue[800]),
                      title: const Text('Upload File \n (Please upload study materials only — our AI will strictly verify the content.)'),
                      onTap: (){
                         Navigator.pop(context);
                         _uploadFile();
                      },
                    ),
                     ListTile(
                      leading: Icon(Icons.add_link, color: Colors.blue[800]),
                      title: const Text('Add Link'),
                      onTap: (){
                         Navigator.pop(context);
                         _showAddLinkDialog();
                      },
                    ),
                  ],
                )
              ),
            );
          },
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: Colors.blueGrey[800],
      leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _cancelSelection),
      title: Text('${_selectedItems.length} selected'),
      actions: [
        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white), onPressed: _confirmDeleteSelected),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    List<dynamic> filteredItems = _getFilteredItems();
    return WillPopScope(
      onWillPop: () async {
        if (_isSelectionMode) {
          _cancelSelection();
          return false; // Prevent page from popping
        }
        if (widget.folderId == null) {
          // This is the root "My Files" page, navigate to home instead of exiting.
          context.go('/student_home'); // Assuming '/home' is your main home route.
          return false; // Prevent default pop action (which would exit the app).
        }
        return true; // Allow default pop for sub-folders.
      },
      child: Scaffold(
        appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
        body: RefreshIndicator(
          onRefresh: _loadAllItems,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _buildBreadcrumbs(),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                        icon: Icon(Icons.search, color: Colors.grey),
                        hintText: 'Search all files and folders',
                        border: InputBorder.none),
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
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isSelected ? Colors.blue : Colors.transparent, width: 2))),
                        child: Text(tab, style: TextStyle(color: isSelected ? Colors.blue : Colors.grey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                if (_isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()))
                else if (filteredItems.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_searchQuery.isNotEmpty ? Icons.search_off : Icons.folder_open, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? 'No files or folders here.\nTap the + button to create one.' : 'No results found for "$_searchQuery"',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          ),
                        ],
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
        ),
      ),
    );
  }

  Widget _buildFolderTile(FolderData folder, String path) {
    final isSelected = _selectedItems.contains(folder.id);
    return ListTile(
      leading: _isSelectionMode
          ? Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue[800], size: 40)
          : Icon(Icons.folder_outlined, color: Colors.blue[800], size: 40),
      title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(path, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: _isSelectionMode ? null : _buildItemPopupMenu('Folder', folder),
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(folder.id);
        } else {
          _openFolder(folder.id, folder.name);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectedItems.add(folder.id);
          });
        }
      },
    );
  }

  Widget _buildFileTile(FileData file, String path) {
    final isSelected = _selectedItems.contains(file.id);
    return ListTile(
      leading: _isSelectionMode
          ? Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue[800], size: 40)
          : Icon(_getFileIcon(file.type), color: Colors.blue[800], size: 40),
      title: Text(file.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(file.type == 'link' ? file.url : '${_formatBytes(file.size)}', style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis),
      trailing: _isSelectionMode ? null : _buildItemPopupMenu('File', file),
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(file.id);
        } else {
          _openFile(file);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectedItems.add(file.id);
          });
        }
      },
    );
  }

  Widget _buildItemPopupMenu(String type, dynamic item) {
    final itemId = item.id;
    final itemName = item.name;
    final fileData = type == 'File' ? item as FileData : null;
    final folderData = type == 'Folder' ? item as FolderData : null;
    final isFavorite = fileData != null && _favoriteFileIds.contains(fileData.id);

    return PopupMenuButton<String>(
      onSelected: (String value) async {
        if (value == 'delete') {
          if (type == 'File') _deleteFile(fileData!); else _deleteFolder(folderData!);
        } else if (value == 'rename') {
          _showRenameDialog(type, itemId, itemName);
        } else if (value == 'details' && fileData != null) {
          context.push('/file_details', extra: fileData);
        } else if (value == 'open' && folderData != null) {
          _openFolder(folderData.id, folderData.name);
        } else if (value == 'view' && fileData != null) {
          _openFile(fileData);
        } else if (value == 'download' && fileData != null) {
          _downloadFile(fileData);
        } else if (value == 'share' && fileData != null) {
          _shareFile(fileData);
        } else if (value == 'favorite' && fileData != null) {
          _toggleFavorite(fileData);
        }
      },
      itemBuilder: (BuildContext context) {
        final List<PopupMenuEntry<String>> items = [];
        if (type == 'Folder') {
          items.add(_buildPopupMenuItem('open', Icons.folder_open, 'Open'));
        } else {
          items.add(_buildPopupMenuItem('view', Icons.open_in_new, 'View'));
           if (fileData?.type != 'link') {
            items.add(_buildPopupMenuItem('download', Icons.download, 'Download'));
          }
          items.add(_buildPopupMenuItem('share', Icons.share, 'Share'));
          items.add(_buildPopupMenuItem('favorite', isFavorite ? Icons.favorite : Icons.favorite_border, isFavorite ? 'Remove from Favorites' : 'Add to Favorites',));
          items.add(_buildPopupMenuItem('details', Icons.info_outline, 'Details'));
        }
        items.add(_buildPopupMenuItem('rename', Icons.drive_file_rename_outline, 'Rename'));
        items.add(_buildPopupMenuItem('delete', Icons.delete_outline, 'Delete', color: Colors.red));
        return items;
      },
    );
  }

  PopupMenuItem<String> _buildPopupMenuItem(String value, IconData icon, String title, {Color? color}) {
    return PopupMenuItem<String>(
      value: value,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(color: color)),
      ),
    );
  }

  Future<void> _showRenameDialog(String type, String itemId, String currentName) async {
    final TextEditingController controller = TextEditingController(text: currentName);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Rename $type'),
          content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'New name')),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  _renameItem(itemId, currentName, controller.text.trim(), type);
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }

  IconData _getFileIcon(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'link': return Icons.link;
      case 'pdf': return Icons.picture_as_pdf_outlined;
      case 'doc': case 'docx': return Icons.description_outlined;
      case 'ppt': case 'pptx': return Icons.slideshow_outlined;
      case 'xls': case 'xlsx': return Icons.table_chart_outlined;
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Icons.image_outlined;
      case 'zip': case 'rar': return Icons.folder_zip_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  Future<void> _downloadFile(FileData file) async {
    if (file.type == 'link') {
      _showSnackbar("Cannot download a link.", success: false);
      return;
    }
    if (!await _isConnected()) return;
    try {
      final dio = Dio();
      final Directory? baseDownloadDir = await getExternalStorageDirectory();
      if (baseDownloadDir == null) {
        _showSnackbar('Failed to find a valid download directory.', success: false);
        return;
      }
      final Directory gradeMateDir = Directory('${baseDownloadDir.path}${Platform.pathSeparator}GradeMate');
      if (!await gradeMateDir.exists()) {
        await gradeMateDir.create(recursive: true);
      }
      final filePath = '${gradeMateDir.path}${Platform.pathSeparator}${file.name}';
      await dio.download(
        file.url, filePath, onReceiveProgress: (received, total) {
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
    if (!await _isConnected()) return;
    try {
       if (file.type == 'link') {
        await Share.share('Check out this link from GradeMate: ${file.url}');
        return;
      }
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

  Future<void> _toggleFavorite(FileData file) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      _showSnackbar("You must be logged in to manage favorites.", success: false);
      return;
    }
    final userRef = _firestore.collection('users').doc(user.email);
    final fileRef = 'users/${user.email}/files/${file.id}';
    if (_favoriteFileIds.contains(file.id)) {
      await userRef.update({
        'favorites': FieldValue.arrayRemove([fileRef])
      });
      setState(() => _favoriteFileIds.remove(file.id));
      _showSnackbar('Removed from favorites');
      await _logActivity('Removed from Favorites', {'fileName': file.name});
    } else {
      await userRef.update({
        'favorites': FieldValue.arrayUnion([fileRef])
      });
      setState(() => _favoriteFileIds.add(file.id));
      _showSnackbar('Added to favorites');
      await _logActivity('Added to Favorites', {'fileName': file.name});
    }
  }

  Future<void> _buildFolderPath(String? folderId) async {
    if (!mounted) return;
    List<Map<String, String?>> path = [];
    String? currentId = folderId;
    while (currentId != null) {
      final folder = _allUserFolders.firstWhere((f) => f.id == currentId, orElse: () {
        return FolderData(id: '', name: '...', ownerId: '', createdAt: Timestamp.now());
      });
      if (folder.id.isNotEmpty) {
          path.insert(0, {'id': folder.id, 'name': folder.name});
          currentId = folder.parentFolderId;
      } else {
          break;
      }
    }
    path.insert(0, {'id': null, 'name': 'My Files'});
    setState(() {
      _folderPath = path;
    });
  }

  Widget _buildBreadcrumbs() {
    if (_folderPath.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _folderPath.map((folder) {
          final isLast = folder == _folderPath.last;
          return Row(
            children: [
              InkWell(
                onTap: isLast ? null : () {
                  final folderId = folder['id'];
                  if (folderId == null) {
                    context.go('/student_my_files');
                  } else {
                     _openFolder(folderId, folder['name']!);
                  }
                },
                child: Text(
                  folder['name']!,
                  style: TextStyle(
                    color: isLast ? Colors.black : Colors.blue,
                    fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (!isLast)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0),
                  child: Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Future<void> _showAddLinkDialog() async {
    final formKey = GlobalKey<FormState>();
    final TextEditingController nameController = TextEditingController();
    final TextEditingController urlController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add a new link'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g., Google Drive'),
                  validator: (value) => value!.isEmpty ? 'Please enter a name' : null,
                ),
                TextFormField(
                  controller: urlController,
                  decoration: const InputDecoration(labelText: 'URL', hintText: 'https://...'),
                  validator: (value) {
                    if (value!.isEmpty) return 'Please enter a URL';
                    if (!Uri.parse(value).isAbsolute) return 'Please enter a valid URL';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              child: const Text('Add'),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  _addLink(nameController.text.trim(), urlController.text.trim());
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _addLink(String name, String url) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;
    try {
      final userDoc = await _firestore.collection('users').doc(user.email).get();
      final uid = userDoc.data()?['uid'];
      if (uid == null) throw Exception("UID not found.");
      final ownerName = userDoc.data()?['name'] ?? 'Unknown';

      final filesCollection = _firestore.collection('users').doc(user.email).collection('files');
      final newFileRef = filesCollection.doc();
      final newFileId = newFileRef.id;

      final newLinkData = FileData(
        id: newFileId, name: name, url: url, ownerId: uid, ownerName: ownerName,
        parentFolderId: _currentFolderId, sharedWith: [], uploadedAt: Timestamp.now(), size: 0, type: 'link',
      );

      await newFileRef.set(newLinkData.toMap());
      await _logActivity('Added Link', {'linkName': name, 'url': url});
      if (mounted) {
        setState(() => _allUserFiles.add(newLinkData));
      }
      _showSnackbar('Link "$name" added successfully!');
    } catch (e) {
      _showSnackbar('Failed to add link: $e', success: false);
    }
  }

  Future<void> _openFile(FileData file) async {
    await _addToRecentlyAccessed(file);

    if (file.type == 'link') {
      final url = Uri.parse(file.url);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        _showSnackbar('Could not open the link: ${file.url}', success: false);
      }
    } else {
      context.push('/file_viewer', extra: file);
    }
  }

  Future<void> _addToRecentlyAccessed(FileData file) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;
    
    final userRef = _firestore.collection('users').doc(user.email);
    final fileRefPath = 'users/${user.email}/files/${file.id}';

    try {
       await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        final data = snapshot.data();
        
        List<String> recentlyAccessed = data?['recentlyAccessed'] != null
            ? List<String>.from(data!['recentlyAccessed'])
            : [];
        
        recentlyAccessed.remove(fileRefPath);
        
        recentlyAccessed.insert(0, fileRefPath);
        
        if (recentlyAccessed.length > 10) {
          recentlyAccessed = recentlyAccessed.sublist(0, 10);
        }
        
        transaction.update(userRef, {'recentlyAccessed': recentlyAccessed});
      });
    } catch(e) {
      print("Error updating recently accessed: $e");
    }
  }
}

