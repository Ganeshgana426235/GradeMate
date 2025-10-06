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
  
  void _fetchAndCacheAllData() async {
    setState(() {
      _isLoading = true;
    });

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      CollectionReference filesCollection;
      CollectionReference foldersCollection;

      if (_currentFolderId == null) {
        // Fetch from user's root subcollections
        filesCollection = _firestore.collection('users').doc(user.uid).collection('files');
        foldersCollection = _firestore.collection('users').doc(user.uid).collection('folders');
      } else {
        // Fetch from subcollections of the current folder
        filesCollection = _firestore.collection('folders').doc(_currentFolderId).collection('files');
        foldersCollection = _firestore.collection('folders').doc(_currentFolderId).collection('folders');
      }

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
    if (user == null) return;
    
    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final file = result.files.first;
    final fileName = file.name;
    final filePath = file.bytes!;
    
    final storageRef = _storage.ref().child('uploads/${user.uid}/${_currentFolderId ?? 'root'}/$fileName');
    
    try {
      final uploadTask = storageRef.putData(filePath);
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final ownerName = userDoc.data()?['name'] ?? 'Unknown';

      final fileData = {
        'name': fileName,
        'url': downloadUrl,
        'size': file.size,
        'type': file.extension,
        'uploadedAt': FieldValue.serverTimestamp(),
        'ownerId': user.uid,
        'ownerName': ownerName,
        'parentFolderId': _currentFolderId,
        'sharedWith': [],
      };
      
      CollectionReference filesCollection;
      if (_currentFolderId == null) {
        filesCollection = _firestore.collection('users').doc(user.uid).collection('files');
      } else {
        filesCollection = _firestore.collection('folders').doc(_currentFolderId).collection('files');
      }
      
      await filesCollection.add(fileData);

      _showSnackbar('File uploaded successfully!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to upload file: $e', success: false);
      debugPrint('File upload error: $e');
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
      _showSnackbar('❌ Failed to share file: $e',);
    }
  }

  Future<void> _createFolder(String folderName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final folderId = _firestore.collection('folders').doc().id;
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final ownerName = userDoc.data()?['name'] ?? 'Unknown';

    final folderData = {
      'name': folderName,
      'createdAt': FieldValue.serverTimestamp(),
      'ownerId': user.uid,
      'ownerName': ownerName,
      'parentFolderId': _currentFolderId,
      'sharedWith': [],
    };
    
    CollectionReference foldersCollection;
    if (_currentFolderId == null) {
      foldersCollection = _firestore.collection('users').doc(user.uid).collection('folders');
    } else {
      foldersCollection = _firestore.collection('folders').doc(_currentFolderId).collection('folders');
    }

    await foldersCollection.doc(folderId).set(folderData);
    
    _showSnackbar('Folder "$folderName" created successfully!');
    _fetchAndCacheAllData();
  }

  Future<void> _deleteFile(String fileId, String fileName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      
      final storagePath = 'uploads/${user.uid}/${_currentFolderId ?? 'root'}/$fileName';
      final storageRef = _storage.ref().child(storagePath);
      
      // Check if file exists in storage before attempting deletion
      try {
        await storageRef.getDownloadURL(); // This will throw an error if the file doesn't exist
        await storageRef.delete();
      } catch (e) {
        debugPrint('File not found in storage or failed to delete: $e');
      }

      CollectionReference filesCollection;
      if (_currentFolderId == null) {
        filesCollection = _firestore.collection('users').doc(user.uid).collection('files');
      } else {
        filesCollection = _firestore.collection('folders').doc(_currentFolderId).collection('files');
      }
      
      await filesCollection.doc(fileId).delete();
      
      _showSnackbar('File deleted successfully!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to delete file: $e', success: false);
      debugPrint('Delete file error: $e');
    }
  }

  Future<void> _deleteFolder(String folderId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      
      final folderRef = _firestore.collection('folders').doc(folderId);

      // Recursive helper function to delete subcollections
      Future<void> _recursiveDelete(DocumentReference folderRef) async {
        final WriteBatch batch = _firestore.batch();
        
        // Delete all files in the current folder
        final filesSnapshot = await folderRef.collection('files').get();
        for (var fileDoc in filesSnapshot.docs) {
          batch.delete(fileDoc.reference);
        }
        
        // Delete all subfolders and their contents
        final foldersSnapshot = await folderRef.collection('folders').get();
        for (var subfolderDoc in foldersSnapshot.docs) {
          await _recursiveDelete(subfolderDoc.reference);
        }
        
        // After deleting contents, delete the folder document itself
        batch.delete(folderRef);
        await batch.commit();
      }

      // Start the recursive deletion from the specified folder
      await _recursiveDelete(folderRef);

      _showSnackbar('Folder and its contents deleted successfully!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to delete folder: $e', success: false);
      debugPrint('Delete folder error: $e');
    }
  }
  
  void _showSnackbar(String message, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
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
  
  void _openFolder(String folderId, String folderName) {
    context.push('/student_my_files/$folderId', extra: folderName);
  }
  
  void _goBack() {
    context.pop();
  }

  Future<void> _renameItem(String itemId, String oldName, String newName, String type) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      
      DocumentReference itemRef;
      if (type == 'File') {
        CollectionReference filesCollection = _currentFolderId == null
            ? _firestore.collection('users').doc(user.uid).collection('files')
            : _firestore.collection('folders').doc(_currentFolderId).collection('files');
        itemRef = filesCollection.doc(itemId);
      } else {
        CollectionReference foldersCollection = _currentFolderId == null
            ? _firestore.collection('users').doc(user.uid).collection('folders')
            : _firestore.collection('folders').doc(_currentFolderId).collection('folders');
        itemRef = foldersCollection.doc(itemId);
      }
      
      await itemRef.update({'name': newName});
      
      _showSnackbar('Successfully renamed!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to rename: $e', success: false);
    }
  }
  
  Future<void> _moveItem(String itemId, String itemType, String newParentFolderId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      
      DocumentSnapshot itemDoc;
      CollectionReference sourceCollection;
      
      if (itemType == 'File') {
        sourceCollection = _currentFolderId == null
            ? _firestore.collection('users').doc(user.uid).collection('files')
            : _firestore.collection('folders').doc(_currentFolderId).collection('files');
        itemDoc = await sourceCollection.doc(itemId).get();
      } else {
        sourceCollection = _currentFolderId == null
            ? _firestore.collection('users').doc(user.uid).collection('folders')
            : _firestore.collection('folders').doc(_currentFolderId).collection('folders');
        itemDoc = await sourceCollection.doc(itemId).get();
      }

      if (!itemDoc.exists) {
        _showSnackbar('Item not found.', success: false);
        return;
      }
      
      CollectionReference destinationCollection;
      if (newParentFolderId.isEmpty) {
        destinationCollection = itemType == 'File'
            ? _firestore.collection('users').doc(user.uid).collection('files')
            : _firestore.collection('users').doc(user.uid).collection('folders');
      } else {
        destinationCollection = itemType == 'File'
            ? _firestore.collection('folders').doc(newParentFolderId).collection('files')
            : _firestore.collection('folders').doc(newParentFolderId).collection('folders');
      }
      
      final Map<String, dynamic> data = itemDoc.data() as Map<String, dynamic>;
      data['parentFolderId'] = newParentFolderId.isEmpty ? null : newParentFolderId;
      
      await destinationCollection.doc(itemId).set(data);
      await sourceCollection.doc(itemId).delete();
      
      _showSnackbar('$itemType moved successfully!');
      _fetchAndCacheAllData();
    } catch (e) {
      _showSnackbar('Failed to move $itemType: $e', success: false);
      debugPrint('Move error: $e');
    }
  }

  Future<void> _showMoveDialog(String itemId, String itemType) async {
    String? currentDialogFolderId = '';
    String currentDialogFolderName = 'My Files';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text('Move to: $currentDialogFolderName'),
              content: StreamBuilder<QuerySnapshot>(
                stream: currentDialogFolderId == ''
                    ? _firestore.collection('users').doc(_auth.currentUser!.uid).collection('folders').snapshots()
                    : _firestore.collection('folders').doc(currentDialogFolderId).collection('folders').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Error loading folders.');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final folders = snapshot.data!.docs.map((doc) => FolderData.fromFirestore(doc)).toList();

                  return SizedBox(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: folders.length,
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.name),
                          onTap: () {
                            setState(() {
                              currentDialogFolderId = folder.id;
                              currentDialogFolderName = folder.name;
                            });
                          },
                        );
                      },
                    ),
                  );
                },
              ),
              actions: [
                if (currentDialogFolderId != '')
                  TextButton(
                    onPressed: () async {
                      final doc = await _firestore.collection('folders').doc(currentDialogFolderId).get();
                      final parentId = doc.data()?['parentFolderId'];
                      
                      setState(() {
                        currentDialogFolderId = parentId;
                        currentDialogFolderName = parentId == null 
                          ? 'My Files' 
                          : _allFolders.firstWhere((f) => f.id == parentId).name;
                      });
                    },
                    child: const Text('Back'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    _moveItem(itemId, itemType, currentDialogFolderId ?? '');
                    Navigator.of(context).pop();
                  },
                  child: const Text('Move Here'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  String _getItemPath(dynamic item) {
    String? parentId = item is FileData ? item.parentFolderId : (item as FolderData).parentFolderId;
    List<String> pathSegments = [];

    // This logic needs to traverse up the folder hierarchy, which is complex
    // with the new structure. A simplified version will be used here.
    // For full pathing, you would need to fetch all parent folders recursively.
    if (parentId == null) {
      return 'My Files';
    } else {
      return '.../${_currentFolderName}'; // A simplified, relative path
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
      trailing: _buildItemPopupMenu('Folder', folder.id, folder.name),
      onTap: () => _openFolder(folder.id, folder.name),
    );
  }

  Widget _buildFileTile(FileData file, String path) {
    return ListTile(
      leading: Icon(_getFileIcon(file.type), color: Colors.blue[800]),
      title: Text(file.name),
      subtitle: Text(path, style: const TextStyle(color: Colors.grey)),
      trailing: _buildItemPopupMenu('File', file.id, file.name, file),
      onTap: () {
        context.push('/file_viewer', extra: file);
      },
    );
  }

  Widget _buildItemPopupMenu(String type, String itemId, String itemName, [FileData? fileData]) {
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
                      _deleteFile(itemId, itemName);
                    } else {
                      _deleteFolder(itemId);
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
          _showMoveDialog(itemId, type);
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
}