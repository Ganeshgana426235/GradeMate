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
import 'package:shimmer/shimmer.dart'; 
import 'package:google_fonts/google_fonts.dart'; // Added for consistent styling
import 'package:intl/intl.dart'; // Added for reminder dialog

// Primary accent color from student_home_page
const Color _kPrimaryColor = Color(0xFF6A67FE);

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
  String? _userUid; // Store UID once

  // NOTE: These lists only contain files/folders for the CURRENT folder ID,
  // except when search is activated.
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

  // Stream subscriptions for real-time updates and cache handling
  StreamSubscription<QuerySnapshot>? _filesSubscription;
  StreamSubscription<QuerySnapshot>? _foldersSubscription;
  StreamSubscription<QuerySnapshot>? _allFoldersSubscription; // For breadcrumbs

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
    _filesSubscription?.cancel();
    _foldersSubscription?.cancel();
    _allFoldersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _loadUserData();
    _startListeners();
    // Use the function that relies on the ongoing allFolders listener
    await _buildFolderPath(_currentFolderId); 
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        final userDoc = await _firestore.collection('users').doc(user.email).get(); 
        if (mounted && userDoc.exists) {
          final data = userDoc.data();
          setState(() {
            userName = data?['name'];
            _userUid = data?['uid'];
             // Store file IDs only, extracting from full path stored in old versions
            _favoriteFileIds = List<String>.from(data?['favorites'] ?? [])
              .map((path) => path.split('/').last) // Extract ID from path
              .toList();
          });
        }
      } catch (e) {
        print("Error loading user data: $e");
      }
    }
  }

  void _startListeners({bool forceServerFetch = false}) {
    if (_userUid == null) {
      _loadUserData().then((_) => _startListeners(forceServerFetch: forceServerFetch));
      return;
    }

    _filesSubscription?.cancel();
    _foldersSubscription?.cancel();
    _allFoldersSubscription?.cancel();

    final userFilesRef = _firestore.collection('users').doc(_auth.currentUser!.email).collection('files');
    final userFoldersRef = _firestore.collection('users').doc(_auth.currentUser!.email).collection('folders');

    // 1. Listener for files in the CURRENT folder (optimized query)
    final filesQuery = userFilesRef
        .where('ownerId', isEqualTo: _userUid)
        .where('parentFolderId', isEqualTo: _currentFolderId);

    if (forceServerFetch) {
        filesQuery.get(const GetOptions(source: Source.server)).then((snapshot) {
            if (mounted) {
                setState(() {
                    _allUserFiles = snapshot.docs.map((doc) => FileData.fromFirestore(doc)).toList();
                    _isLoading = false; 
                });
            }
        });
    }

    _filesSubscription = filesQuery.snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _allUserFiles = snapshot.docs.map((doc) => FileData.fromFirestore(doc)).toList();
          if (forceServerFetch) _isLoading = false;
        });
      }
    }, onError: (e) {
      debugPrint("Error listening to files: $e");
    });


    // 2. Listener for folders in the CURRENT folder (optimized query)
    final foldersQuery = userFoldersRef
        .where('ownerId', isEqualTo: _userUid)
        .where('parentFolderId', isEqualTo: _currentFolderId);
    
    if (forceServerFetch) {
        foldersQuery.get(const GetOptions(source: Source.server)).then((snapshot) {
            if (mounted) {
                setState(() {
                    _allUserFolders = snapshot.docs.map((doc) => FolderData.fromFirestore(doc)).toList();
                    _isLoading = false; 
                });
            }
        });
    }

    _foldersSubscription = foldersQuery.snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _allUserFolders = snapshot.docs.map((doc) => FolderData.fromFirestore(doc)).toList();
          if (forceServerFetch) _isLoading = false;
        });
      }
    }, onError: (e) {
      debugPrint("Error listening to folders: $e");
    });
    
    // 3. Listener for ALL folders (for breadcrumbs)
    final allFoldersQuery = userFoldersRef
        .where('ownerId', isEqualTo: _userUid);

    _allFoldersSubscription = allFoldersQuery.snapshots().listen((snapshot) {
      if (mounted) {
        List<FolderData> allFolders = snapshot.docs.map((doc) => FolderData.fromFirestore(doc)).toList();
        _buildFolderPathFromAll(allFolders);
      }
    }, onError: (e) {
      debugPrint("Error listening to all folders for pathing: $e");
    });

    if (!forceServerFetch && mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshItems() async {
    if (mounted) setState(() => _isLoading = true);
    _startListeners(forceServerFetch: true);
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
    await flutterLocalNotificationsPlugin.cancel(2);
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
      3, 'Upload Complete', 'The file "$fileName" has been uploaded successfully.', platformChannelSpecifics,
    );
  }
  
  Future<bool> _verifyImageIsStudyMaterial(File imageFile) async {
    await _showVerificationNotification();
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final apiKey = dotenv.env['GEMINI_API_KEY']; 
      
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
      if (user == null || user.email == null || _userUid == null) {
        _showSnackbar('User information is missing. Please log in again.', success: false);
        return;
      }
      final uid = _userUid!;
      final ownerName = userName ?? 'Unknown';

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
      
      await _showUploadCompletionNotification(fileName);
      _showSnackbar('File "$fileName" uploaded successfully!');
    } catch (e) {
      debugPrint("Error uploading file: $e");
      _showSnackbar('Failed to upload file: ${e.toString()}', success: false);
    }
  }

  Future<void> _createFolder(String folderName) async {
    final user = _auth.currentUser;
    // CRITICAL CHANGE: Folder creation is only allowed in the root directory for Students, 
    // but Faculty likely needs this flexibility. For parity with Student code, 
    // I will allow folder creation in any folder, unless there's a specific instruction to restrict it.
    
    if (user == null || user.email == null || _userUid == null) return;
    try {
      final uid = _userUid!;
      final userFoldersCollection = _firestore.collection('users').doc(user.email).collection('folders');
      final newFolderRef = userFoldersCollection.doc();
      final newFolderId = newFolderRef.id;
      final ownerName = userName ?? 'Unknown';
      
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
    
    final uid = _userUid;
    if (uid == null) throw Exception("UID not found.");

    final userRef = _firestore.collection('users').doc(user.email);
    final fileRefPath = 'users/${user.email}/files/${file.id}';
    
    final batch = _firestore.batch();
    
    // Use file.id for favorites, path for recentlyAccessed
    batch.update(userRef, {
      'favorites': FieldValue.arrayRemove([file.id]),
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
    batch.delete(filesCollection.doc(file.id));
    
    await batch.commit();

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
    } catch (e) {
      _showSnackbar('Failed to delete file: ${e.toString()}', success: false);
    }
  }

  Future<void> _performFolderDelete(FolderData folder) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) throw Exception('User not logged in.');
    final uid = _userUid;
    if (uid == null) throw Exception("UID not found.");
    
    final foldersCollection = _firestore.collection('users').doc(user.email).collection('folders');
    final filesCollection = _firestore.collection('users').doc(user.email).collection('files');
    
    // Recursive delete is necessary here
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
        _isLoading = false;
      });
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
    // Navigate to the new folder route
    context.push('/faculty_my_files/$folderId', extra: folderName);
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
      // Use the list updated by the allFolders listener
      final parentFolder = _allUserFolders.firstWhere((f) => f.id == parentFolderId, orElse: () => FolderData(id: '', name: 'My Files', ownerId: '', createdAt: Timestamp.now()));
      return parentFolder.name;
    }
    return _currentFolderName ?? 'My Files';
  }

  List<dynamic> _getFilteredItems() {
    final lowerCaseQuery = _searchQuery.toLowerCase();
    List<dynamic> itemsToDisplay;
    
    if (lowerCaseQuery.isNotEmpty) {
      final searchableFolders = _allUserFolders.where((folder) => folder.name.toLowerCase().contains(lowerCaseQuery));
      final searchableFiles = _allUserFiles.where((file) => file.name.toLowerCase().contains(lowerCaseQuery));
      itemsToDisplay = [...searchableFolders, ...searchableFiles];
    } else {
      itemsToDisplay = [..._allUserFolders, ..._allUserFiles];
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
  
  String _getFileInfoText(FileData file) {
    String typeDisplay = file.type == 'link' ? 'Link' : file.type.toUpperCase();
    String sizeDisplay = file.type != 'link' ? _formatBytes(file.size) : file.url;
    
    // Add additional info for common types
    if (file.type == 'mp4' || file.type == 'mov') {
      typeDisplay = 'Video';
    } else if (['jpg', 'jpeg', 'png', 'gif'].contains(file.type)) {
      typeDisplay = 'Image';
    } else if (file.type == 'pdf') {
       typeDisplay = 'PDF';
    } else if (file.type == 'docx') {
       typeDisplay = 'DOCX';
    }
    
    return '$typeDisplay • $sizeDisplay';
  }

  Future<void> _buildFolderPathFromAll(List<FolderData> allFolders) async {
    if (!mounted) return;
    List<Map<String, String?>> path = [];
    String? currentId = _currentFolderId;
    while (currentId != null) {
      final folder = allFolders.firstWhere((f) => f.id == currentId, orElse: () {
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

  // Helper retained for initial call consistency
  Future<void> _buildFolderPath(String? folderId) async {
    _buildFolderPathFromAll(_allUserFolders);
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
                  // Use faculty router path
                  String targetPath = folderId == null ? '/faculty_my_files' : '/faculty_my_files/$folderId';
                  GoRouter.of(context).go(targetPath);
                },
                child: Text(
                  folder['name']!,
                  style: GoogleFonts.inter(
                    color: isLast ? Colors.black : _kPrimaryColor,
                    fontWeight: isLast ? FontWeight.bold : FontWeight.w500,
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

  // NEW: Upload Confirmation Dialog (Copied from student page)
  Future<void> _showUploadConfirmationDialog() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Important: Upload Policy'),
        content: const Text(
          'Only study materials (notes, slides, documents, academic images) are permitted. '
          'Personal images, photos of people, or non-educational content will be rejected by our AI verification system. '
          'Please ensure you select the correct file type.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue to Selection'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      _uploadFile();
    }
  }


  AppBar _buildNormalAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: widget.folderId != null ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: _goBack) : null,
      title: Text('My Files', style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.bold)),
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined, color: Colors.black),
          onPressed: () => _showCreateFolderDialog(),
        ),
        IconButton(
          icon: const Icon(Icons.upload_file_outlined, color: Colors.black),
          onPressed: () => _showUploadConfirmationDialog(),
        ),
        IconButton(
          icon: const Icon(Icons.add_link_outlined, color: Colors.black),
          onPressed: () => _showAddLinkDialog(),
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: _kPrimaryColor,
      leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _cancelSelection),
      title: Text('${_selectedItems.length} selected', style: const TextStyle(color: Colors.white)),
      actions: [
        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white), onPressed: _confirmDeleteSelected),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    List<dynamic> filteredItems = _getFilteredItems();
    List<FolderData> folders = filteredItems.whereType<FolderData>().toList();
    List<FileData> files = filteredItems.whereType<FileData>().toList();

    return WillPopScope(
      onWillPop: () async {
        if (_isSelectionMode) {
          _cancelSelection();
          return false;
        }
        if (widget.folderId == null) {
          context.go('/faculty_home'); 
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
        body: RefreshIndicator(
          onRefresh: _refreshItems, 
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _buildBreadcrumbs(),
                const SizedBox(height: 16),
                
                _buildSearchBar(),
                const SizedBox(height: 16),
                
                _buildTabs(),
                const SizedBox(height: 24),
                
                if (_isLoading)
                    const _FacultyMyFilesShimmer(),

                if (!_isLoading) ...[
                  // --- Folders Section ---
                  if (folders.isNotEmpty && (_searchTab == 'All' || _searchTab == 'Folders'))
                    _buildFoldersSection(folders),
                  
                  // --- Files Section ---
                  if (files.isNotEmpty && (_searchTab == 'All' || _searchTab == 'Files'))
                    _buildFilesSection(files),

                  // --- Empty State ---
                  if (filteredItems.isEmpty)
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
                                style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // NEW: Search Bar Widget
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300)
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
            icon: Icon(Icons.search, color: Colors.grey[600]),
            hintText: 'Search folders and files',
            hintStyle: GoogleFonts.inter(color: Colors.grey[600]),
            border: InputBorder.none,
            isDense: true,
        ),
        onChanged: (value) {
          // Listener already attached for debouncing
        },
      ),
    );
  }
  
  // NEW: Tabs Widget
  Widget _buildTabs() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double tabWidth = constraints.maxWidth * 0.30; 

        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: ['All', 'Folders', 'Files'].map((tab) {
            final isSelected = _searchTab == tab;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: GestureDetector(
                onTap: () => setState(() => _searchTab = tab),
                child: Container(
                  width: tabWidth,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFF0F5FF) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSelected ? _kPrimaryColor.withOpacity(0.5) : Colors.grey.shade300, width: 1.5),
                  ),
                  child: Text(
                    tab,
                    style: GoogleFonts.inter(
                      color: isSelected ? _kPrimaryColor : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      }
    );
  }

  // NEW: Folders Section Widget
  Widget _buildFoldersSection(List<FolderData> folders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text('Folders', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        
        if (_searchTab == 'All')
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: folders.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: _buildFolderCard(folders[index]),
                );
              },
            ),
          )
        else if (_searchTab == 'Folders')
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12.0,
              mainAxisSpacing: 12.0,
              childAspectRatio: 1.3,
            ),
            itemCount: folders.length,
            itemBuilder: (context, index) {
              return _buildFolderCard(folders[index]);
            },
          ),
          
        const SizedBox(height: 24),
      ],
    );
  }

  // NEW: Folder Card Widget
  Widget _buildFolderCard(FolderData folder) {
    final isSelected = _selectedItems.contains(folder.id);
    final itemCount = folder.files.length + folder.folders.length; 
    final lastUpdated = (folder.createdAt?.toDate().toString().split(' ')[0] ?? '');

    return GestureDetector(
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
      child: Container(
        width: _searchTab == 'All' ? 160 : null, 
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? _kPrimaryColor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.folder_outlined, color: _kPrimaryColor, size: 30),
                if (!_isSelectionMode) _buildItemPopupMenu('Folder', folder),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                folder.name,
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$itemCount items • $lastUpdated',
              style: GoogleFonts.inter(color: Colors.grey, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_isSelectionMode)
              Align(
                alignment: Alignment.bottomRight,
                child: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, 
                  color: isSelected ? _kPrimaryColor : Colors.grey, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  // NEW: Files Section Widget
  Widget _buildFilesSection(List<FileData> files) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text('Files', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: files.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _buildFileRow(files[index]),
            );
          },
        ),
      ],
    );
  }

  // NEW: File Row Widget
  Widget _buildFileRow(FileData file) {
    final isSelected = _selectedItems.contains(file.id);
    final isFavorite = _favoriteFileIds.contains(file.id);
    
    return GestureDetector(
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? _kPrimaryColor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Leading Icon
            Icon(_getFileIcon(file.type), color: _kPrimaryColor, size: 30),
            const SizedBox(width: 12),
            
            // Name and Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getFileInfoText(file),
                    style: GoogleFonts.inter(color: Colors.grey, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            
            // Trailing Actions
            if (!_isSelectionMode)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Favorite/Star Action
                  GestureDetector(
                    onTap: () => _toggleFavorite(file),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Icon(isFavorite ? Icons.star : Icons.star_border, color: isFavorite ? Colors.orange : Colors.grey, size: 24),
                    ),
                  ),
                  // Download Action
                  if (file.type != 'link')
                    GestureDetector(
                      onTap: () => _downloadFile(file),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.0),
                        child: Icon(Icons.download_outlined, color: Colors.grey, size: 24),
                      ),
                    ),
                  // Pop-up Menu
                  _buildItemPopupMenu('File', file),
                ],
              ),
            
            // Selection Checkbox
            if (_isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, 
                  color: isSelected ? _kPrimaryColor : Colors.grey, size: 24),
              ),
          ],
        ),
      ),
    );
  }


  // NEW: Reminder-related methods (Copied from student page)
  CollectionReference get _remindersCollection {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception("User not logged in");
    }
    return _firestore
        .collection('users')
        .doc(user.email)
        .collection('reminders');
  }

  Future<void> _addReminder(String title, String description, DateTime reminderTime,
      String recurrence) async {
    final notificationId = math.Random().nextInt(100000);
    try {
      await _remindersCollection.add({
        'title': title,
        'description': description,
        'reminderTime': Timestamp.fromDate(reminderTime),
        'recurrence': recurrence,
        'notificationId': notificationId,
        'sourceFile': title,
      });
      _showSnackbar('Reminder added for "$title"!');

    } catch (e) {
      print("Error adding reminder: $e");
      _showSnackbar('Failed to set reminder: ${e.toString()}', success: false);
    }
  }

  Future<void> _showAddReminderDialogForFile(FileData file) async {
    final titleController = TextEditingController(text: file.name);
    final descriptionController = TextEditingController();
    DateTime? selectedDate = DateTime.now();
    TimeOfDay? selectedTime = TimeOfDay.now();
    String recurrence = 'Once';

    return showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set Reminder for "${file.name}"',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      Text("Description (Optional)", style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descriptionController,
                        decoration: InputDecoration(
                          hintText: "What do you need to do with this file?",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        maxLines: null,
                      ),
                      const SizedBox(height: 20),
                      
                      // --- Date Picker ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('EEE, MMM d, yyyy').format(selectedDate!),
                            style: const TextStyle(fontSize: 16),
                          ),
                          TextButton(
                            onPressed: () async {
                              final now = DateTime.now();
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedDate ?? now,
                                firstDate: DateTime(now.year, now.month, now.day),
                                lastDate: DateTime(2101),
                              );
                              if (date != null) {
                                setDialogState(() => selectedDate = date);
                              }
                            },
                            child: const Text('Change Date'),
                          ),
                        ],
                      ),
                      const Divider(),
                      
                      // --- Time Picker ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            selectedTime == null ? 'No time chosen' : selectedTime!.format(context),
                            style: const TextStyle(fontSize: 16),
                          ),
                          TextButton(
                            onPressed: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: selectedTime ?? TimeOfDay.now(),
                              );
                              if (time != null) {
                                setDialogState(() => selectedTime = time);
                              }
                            },
                            child: const Text('Change Time'),
                          ),
                        ],
                      ),
                       const Divider(),
                       
                      // --- Recurrence ---
                      const SizedBox(height: 8),
                       Text("Repeat", style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                       const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: recurrence,
                        items: ['Once', 'Daily', 'Weekly', 'Monthly']
                            .map((label) => DropdownMenuItem(
                                  value: label,
                                  child: Text(label),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => recurrence = value);
                          }
                        },
                         decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // --- Actions ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            onPressed: () async {
                              if (selectedDate != null && selectedTime != null) {
                                  final reminderDateTime = DateTime(
                                    selectedDate!.year,
                                    selectedDate!.month,
                                    selectedDate!.day,
                                    selectedTime!.hour,
                                    selectedTime!.minute,
                                  );

                                  if (recurrence == 'Once' && reminderDateTime.isBefore(DateTime.now())) {
                                    _showSnackbar('Cannot set a one-time reminder for a past time.', success: false);
                                    return;
                                  }

                                  _addReminder(
                                    titleController.text,
                                    descriptionController.text,
                                    reminderDateTime,
                                    recurrence,
                                  );
                                  Navigator.pop(context);
                                } else {
                                   _showSnackbar('Please choose a date and time.', success: false);
                                }
                            },
                            child: const Text('Save Reminder', style: TextStyle(fontSize: 16)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  // Existing Pop-up menu builder updated for new items (Reminder)
  Widget _buildItemPopupMenu(String type, dynamic item) {
    final itemId = item.id;
    final itemName = item.name;
    final fileData = type == 'File' ? item as FileData : null;
    final folderData = type == 'Folder' ? item as FolderData : null;
    final isFavorite = fileData != null && _favoriteFileIds.contains(fileData.id);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.grey),
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
        } else if (value == 'reminder' && fileData != null) {
          _showAddReminderDialogForFile(fileData);
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
          items.add(_buildPopupMenuItem('favorite', isFavorite ? Icons.star : Icons.star_border, isFavorite ? 'Remove from Favorites' : 'Add to Favorites', color: isFavorite ? Colors.orange : null));
          items.add(_buildPopupMenuItem('reminder', Icons.alarm_add_outlined, 'Add to Reminder')); // Added Reminder option
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
        leading: Icon(icon, color: color ?? Colors.black87),
        title: Text(title, style: TextStyle(color: color ?? Colors.black87)),
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
      case 'mp4': case 'mov': return Icons.videocam_outlined;
      case 'txt': return Icons.text_snippet_outlined;
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
    final fileId = file.id;
    
    if (_favoriteFileIds.contains(fileId)) {
      await userRef.update({
        'favorites': FieldValue.arrayRemove([fileId])
      });
      setState(() => _favoriteFileIds.remove(fileId));
      _showSnackbar('Removed from favorites');
      await _logActivity('Removed from Favorites', {'fileName': file.name});
    } else {
      await userRef.update({
        'favorites': FieldValue.arrayUnion([fileId])
      });
      setState(() => _favoriteFileIds.add(fileId));
      _showSnackbar('Added to favorites');
      await _logActivity('Added to Favorites', {'fileName': file.name});
    }
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
    if (user == null || user.email == null || _userUid == null) return;
    try {
      final uid = _userUid!;
      final ownerName = userName ?? 'Unknown';

      final filesCollection = _firestore.collection('users').doc(user.email).collection('files');
      final newFileRef = filesCollection.doc();
      final newFileId = newFileRef.id;

      final newLinkData = FileData(
        id: newFileId, name: name, url: url, ownerId: uid, ownerName: ownerName,
        parentFolderId: _currentFolderId, sharedWith: [], uploadedAt: Timestamp.now(), size: 0, type: 'link',
      );

      await newFileRef.set(newLinkData.toMap());
      await _logActivity('Added Link', {'linkName': name, 'url': url});
      
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

// ----------------------------------------------------------------------
// UPDATED SHIMMER EFFECT WIDGET (Matching new layout)
// ----------------------------------------------------------------------

class _FacultyMyFilesShimmer extends StatelessWidget {
  const _FacultyMyFilesShimmer();

  Widget _buildBreadcrumbPlaceholder() {
    return Container(
      height: 20,
      width: double.infinity,
      child: Row(
        children: [
          Container(width: 60, height: 14, color: Colors.white),
          const SizedBox(width: 8),
          Container(width: 16, height: 16, color: Colors.white),
          const SizedBox(width: 8),
          Container(width: 80, height: 14, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildSearchPlaceholder() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.only(bottom: 16),
    );
  }

  Widget _buildTabPlaceholder() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Container(width: 80, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))), 
        const SizedBox(width: 8),
        Container(width: 80, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
        const SizedBox(width: 8),
        Container(width: 80, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
      ],
    );
  }
  
  Widget _buildFolderCardPlaceholder() {
    return Container(
      width: 160,
      height: 120, // Added explicit height for horizontal list
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(width: 30, height: 30, color: Colors.grey[200], margin: const EdgeInsets.only(bottom: 8)),
          Container(height: 14, width: 120, color: Colors.grey[200]),
          const SizedBox(height: 4),
          Container(height: 11, width: 90, color: Colors.grey[200]),
        ],
      ),
    );
  }

  Widget _buildFileRowPlaceholder() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(width: 30, height: 30, color: Colors.grey[200]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: double.infinity, color: Colors.grey[200], margin: const EdgeInsets.only(bottom: 4)),
                  Container(height: 12, width: 150, color: Colors.grey[200]),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(width: 80, height: 24, color: Colors.grey[200]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _buildBreadcrumbPlaceholder(),
          const SizedBox(height: 8),
          _buildSearchPlaceholder(),
          _buildTabPlaceholder(),
          const SizedBox(height: 24),
          
          // Folders Title
          Container(height: 18, width: 100, color: Colors.white, margin: const EdgeInsets.only(bottom: 12.0)),
          // Folders List Placeholder (Horizontal)
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: _buildFolderCardPlaceholder(),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Files Title
          Container(height: 18, width: 80, color: Colors.white, margin: const EdgeInsets.only(bottom: 12.0)),
          // Files List Placeholder (Vertical)
          _buildFileRowPlaceholder(),
          _buildFileRowPlaceholder(),
          _buildFileRowPlaceholder(),
          _buildFileRowPlaceholder(),
          _buildFileRowPlaceholder(),
        ],
      ),
    );
  }
}
