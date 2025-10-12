import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:open_filex/open_filex.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<File> _downloadedFiles = [];
  List<File> _filteredFiles = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String? _userRole;
  String _currentFilter = 'All';

  // Multi-selection
  bool _isSelectionMode = false;
  final Set<File> _selectedFiles = {};

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
    _loadDownloadedFiles();
    _searchController.addListener(_filterFiles);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserRole() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        final doc = await _firestore.collection('users').doc(user.email).get();
        if (mounted && doc.exists) {
          setState(() {
            _userRole = doc.data()?['role'];
          });
        }
      } catch (e) {
        print('Error fetching user role: $e');
      }
    }
  }

  void _navigateBack() {
    if (_isSelectionMode) {
      _exitSelectionMode();
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      if (_userRole == 'Faculty') {
        context.go('/faculty_home');
      } else if (_userRole == 'Student') {
        context.go('/student_home');
      } else {
        context.go('/login');
      }
    }
  }

  Future<void> _loadDownloadedFiles() async {
    setState(() => _isLoading = true);
    try {
      final Directory? baseDir = await getExternalStorageDirectory();
      if (baseDir == null) {
        throw Exception('Could not get external storage directory');
      }
      final gradeMateDir = Directory('${baseDir.path}/GradeMate');

      if (await gradeMateDir.exists()) {
        final files = gradeMateDir.listSync().whereType<File>().toList();
        files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        setState(() {
          _downloadedFiles = files;
        });
      }
    } catch (e) {
      print("Error loading downloaded files: $e");
    } finally {
      if (mounted) {
        _filterFiles();
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterFiles() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredFiles = _downloadedFiles.where((file) {
        final fileName = p.basename(file.path).toLowerCase();
        final matchesQuery = fileName.contains(query);
        if (!matchesQuery) return false;

        if (_currentFilter == 'All') {
          return true;
        }
        final extension = p.extension(fileName);
        final category = _getCategoryForExtension(extension);
        return category == _currentFilter;
      }).toList();
    });
  }

  String _getCategoryForExtension(String extension) {
    const docExtensions = ['.pdf', '.doc', '.docx', '.txt', '.ppt', '.pptx', '.xls', '.xlsx'];
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif'];
    const videoExtensions = ['.mp4', '.mov', '.avi'];

    if (docExtensions.contains(extension)) return 'Documents';
    if (imageExtensions.contains(extension)) return 'Images';
    if (videoExtensions.contains(extension)) return 'Videos';
    return 'Other';
  }

  Future<void> _shareFiles(List<File> files) async {
    try {
      final xFiles = files.map((file) => XFile(file.path)).toList();
      if (xFiles.isNotEmpty) {
        await Share.shareXFiles(xFiles, text: 'Shared from GradeMate');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share files: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // *** FIX: Updated _openFile function to include MIME type ***
  Future<void> _openFile(File file) async {
    final mimeType = _getMimeTypeForFile(file.path);
    final result = await OpenFilex.open(file.path, type: mimeType);

    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open file: ${result.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // *** NEW: Helper function to get MIME type from file extension ***
  String? _getMimeTypeForFile(String path) {
    final extension = p.extension(path).toLowerCase();
    switch (extension) {
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.ppt':
        return 'application/vnd.ms-powerpoint';
      case '.pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.mp4':
        return 'video/mp4';
      case '.txt':
        return 'text/plain';
      default:
        return null; // Let the OS try to figure it out
    }
  }

  Future<void> _deleteFiles(List<File> files) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${files.length} File(s)?'),
        content: const Text(
            'Are you sure you want to permanently delete these files? This action cannot be undone.'),
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

    if (confirm == true) {
      try {
        for (var file in files) {
          await file.delete();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${files.length} file(s) deleted successfully'), backgroundColor: Colors.green),
        );
        _exitSelectionMode();
        _loadDownloadedFiles();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete files: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _toggleSelection(File file) {
    setState(() {
      if (_selectedFiles.contains(file)) {
        _selectedFiles.remove(file);
      } else {
        _selectedFiles.add(file);
      }
      _isSelectionMode = _selectedFiles.isNotEmpty;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedFiles.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvoked: (didPop) {
        if (!didPop) {
           _navigateBack();
        }
      },
      child: Scaffold(
        appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildDefaultAppBar(),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search, color: Colors.grey),
                    hintText: 'Search downloads...',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            _buildFilterChips(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredFiles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.download_done, size: 80, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isEmpty
                                ? 'No downloads yet.'
                                : 'No files found.',
                                style: TextStyle(color: Colors.grey[600], fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadDownloadedFiles,
                          child: ListView.builder(
                            itemCount: _filteredFiles.length,
                            itemBuilder: (context, index) {
                              final file = _filteredFiles[index];
                              return _buildFileTile(file);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildDefaultAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: _navigateBack,
      ),
      title: const Text('Downloads'),
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 1,
      centerTitle: true,
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('${_selectedFiles.length} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: () => _shareFiles(_selectedFiles.toList()),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => _deleteFiles(_selectedFiles.toList()),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All', 'Documents', 'Images', 'Videos', 'Other'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: filters.map((filter) {
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(filter),
                selected: _currentFilter == filter,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _currentFilter = filter;
                      _filterFiles();
                    });
                  }
                },
                backgroundColor: Colors.grey[200],
                selectedColor: Colors.blue[100],
                labelStyle: TextStyle(
                  color: _currentFilter == filter ? Colors.blue[800] : Colors.black,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFileTile(File file) {
    final fileName = p.basename(file.path);
    final fileExtension = p.extension(fileName).replaceFirst('.', '');
    final fileSize = file.lengthSync();
    final isSelected = _selectedFiles.contains(file);

    return Container(
      color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
      child: ListTile(
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(file);
          } else {
            _openFile(file);
          }
        },
        onLongPress: () {
          _toggleSelection(file);
        },
        leading: isSelected
            ? Icon(Icons.check_circle, color: Colors.blue[800], size: 40)
            : Icon(_getFileIcon(fileExtension), color: Colors.blue[800], size: 40),
        title: Text(fileName, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(_formatBytes(fileSize)),
        trailing: _isSelectionMode
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'share') {
                    _shareFiles([file]);
                  } else if (value == 'delete') {
                    _deleteFiles([file]);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'share',
                    child: ListTile(
                      leading: Icon(Icons.share_outlined),
                      title: Text('Share'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
              ),
      ),
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

  String _formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}