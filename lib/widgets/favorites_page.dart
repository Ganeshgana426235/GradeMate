import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:grademate/models/file_models.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  // Data is now stored as Map for easier caching
  List<Map<String, dynamic>> _favoriteItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String? _userRole;
  String _currentFilter = 'All';

  // Multi-selection
  bool _isSelectionMode = false;
  final Set<Map<String, dynamic>> _selectedItems = {};

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
    _loadFavorites(); // This now handles caching
    _searchController.addListener(_filterItems);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- Caching Logic ---

  Future<void> _loadFavorites() async {
    // Instantly load from cache to show data offline
    await _loadFavoritesFromCache();
    // Then, fetch from Firestore to get any updates in the background
    await _fetchFavoritesFromFirestore();
  }

  Future<void> _loadFavoritesFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('cached_favorites');
      if (cachedData != null) {
        final List<dynamic> decodedData = json.decode(cachedData);
        if (mounted) {
          setState(() {
            _favoriteItems = List<Map<String, dynamic>>.from(decodedData);
            _isLoading = false; // Show cached data immediately
          });
          _filterItems();
        }
      }
    } catch (e) {
      print("Error loading favorites from cache: $e");
    }
  }

  Future<void> _fetchFavoritesFromFirestore() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.email).get();
      if (!userDoc.exists) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final List<String> favoritePaths =
          List<String>.from(userDoc.data()?['favorites'] ?? []);
      if (favoritePaths.isEmpty) {
        if (mounted) {
          setState(() {
            _favoriteItems = [];
            _isLoading = false;
          });
          _filterItems();
        }
        await _saveFavoritesToCache([]); // Clear cache if favorites are empty
        return;
      }

      final List<Future<DocumentSnapshot>> futureDocs =
          favoritePaths.map((path) => _firestore.doc(path).get()).toList();
      final List<DocumentSnapshot> fetchedDocs = await Future.wait(futureDocs);

      final List<Map<String, dynamic>> itemsToCache = [];
      final existingDocs = fetchedDocs.where((doc) => doc.exists).toList();

      for (var doc in existingDocs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        data['path'] = doc.reference.path;
        if (data['timestamp'] is Timestamp) {
          data['timestamp'] =
              (data['timestamp'] as Timestamp).toDate().toIso8601String();
        }
        itemsToCache.add(data);
      }

      if (mounted) {
        setState(() {
          _favoriteItems = itemsToCache;
          _isLoading = false;
        });
        _filterItems();
      }
      await _saveFavoritesToCache(itemsToCache);
    } catch (e) {
      print("Error loading favorite items: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveFavoritesToCache(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = json.encode(items);
    await prefs.setString('cached_favorites', encodedData);
  }

  // --- End of Caching Logic ---

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

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _favoriteItems.where((item) {
        final itemName =
            (item['fileName'] ?? item['title'] ?? item['name'])?.toString().toLowerCase() ??
                '';

        final matchesQuery = itemName.contains(query);
        if (!matchesQuery) return false;

        if (_currentFilter == 'All') {
          return true;
        }
        final extension = (item['type'] ?? '').toLowerCase();
        final category = _getCategoryForExtension(extension);
        return category == _currentFilter;
      }).toList();
    });
  }

  String _getCategoryForExtension(String extension) {
    const docExtensions = [
      'pdf', 'doc', 'docx', 'txt', 'ppt', 'pptx', 'xls', 'xlsx'
    ];
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif'];
    const videoExtensions = ['mp4', 'mov', 'avi'];

    if (docExtensions.contains(extension)) return 'Documents';
    if (imageExtensions.contains(extension)) return 'Images';
    if (videoExtensions.contains(extension)) return 'Videos';
    if (extension == 'link') return 'Links';
    return 'Other';
  }

  Future<void> _shareItems(List<Map<String, dynamic>> items) async {
    try {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing items for sharing...')),
        );

      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final List<XFile> xFiles = [];

      for (var item in items) {
        if (item['type'] == 'link') {
          await Share.share('Check out this link: ${item['url']}');
          continue;
        }

        final url = item['fileURL'] ?? item['url'];
        final fileName = item['fileName'] ?? item['name'];
        final tempFilePath = '${tempDir.path}/$fileName';
        await dio.download(url, tempFilePath);
        xFiles.add(XFile(tempFilePath));
      }

      if (xFiles.isNotEmpty) {
        await Share.shareXFiles(xFiles, text: 'Shared from GradeMate');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to share items: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _removeItemsFromFavorites(List<Map<String, dynamic>> items) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${items.length} Item(s) from Favorites?'),
        content: const Text(
            'This will only remove them from your favorites list. The original files will not be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final userRef = _firestore.collection('users').doc(user.email);
        final pathsToRemove =
            items.map((item) => item['path'] as String).toList();

        await userRef.update({
          'favorites': FieldValue.arrayRemove(pathsToRemove),
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${items.length} item(s) removed from favorites'),
              backgroundColor: Colors.green),
        );
        _exitSelectionMode();
        // Instead of a full reload, just remove from local state for speed
        setState(() {
          _favoriteItems
              .removeWhere((item) => pathsToRemove.contains(item['path']));
        });
        _filterItems();
        // Update the cache
        await _saveFavoritesToCache(_favoriteItems);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to remove items: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _toggleSelection(Map<String, dynamic> item) {
    setState(() {
      if (_selectedItems.contains(item)) {
        _selectedItems.remove(item);
      } else {
        _selectedItems.add(item);
      }
      _isSelectionMode = _selectedItems.isNotEmpty;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedItems.clear();
    });
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
        appBar: _isSelectionMode
            ? _buildSelectionAppBar()
            : _buildDefaultAppBar(),
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
                    hintText: 'Search favorites...',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            _buildFilterChips(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.favorite_border,
                                  size: 80, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isEmpty
                                    ? 'No favorites yet.'
                                    : 'No items found.',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchFavoritesFromFirestore,
                          child: ListView.builder(
                            itemCount: _filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = _filteredItems[index];
                              return _buildItemTile(item);
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
      title: const Text('Favorites'),
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
      title: Text('${_selectedItems.length} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: () => _shareItems(_selectedItems.toList()),
        ),
        IconButton(
          icon: const Icon(Icons.favorite_border_rounded, color: Colors.red),
          onPressed: () =>
              _removeItemsFromFavorites(_selectedItems.toList()),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All', 'Documents', 'Images', 'Videos', 'Links', 'Other'];
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
                      _filterItems();
                    });
                  }
                },
                backgroundColor: Colors.grey[200],
                selectedColor: Colors.blue[100],
                labelStyle: TextStyle(
                  color: _currentFilter == filter
                      ? Colors.blue[800]
                      : Colors.black,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildItemTile(Map<String, dynamic> item) {
    final isLink = item['type'] == 'link';
    final itemName =
        item['fileName'] ?? item['title'] ?? item['name'] ?? 'Unknown';
    final itemType = item['type'] ?? 'unknown';
    final size = item['size'] != null ? _formatBytes(item['size']) : null;
    final ownerName = item['ownerName'] ?? 'Unknown';
    final isSelected = _selectedItems.contains(item);

    return Container(
      color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
      child: ListTile(
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(item);
          } else {
            if (isLink) {
              _openExternalUrl(item['url']);
            } else {
              final file = FileData(
                  id: item['id'],
                  name: itemName,
                  url: item['fileURL'] ?? item['url'] ?? '',
                  type: itemType,
                  size: item['size'] ?? 0,
                  uploadedAt: item['timestamp'] != null
                      ? Timestamp.fromDate(DateTime.parse(item['timestamp']))
                      : Timestamp.now(),
                  ownerId: item['ownerId'] ?? item['uploadedBy'] ?? '',
                  ownerName: ownerName,
                  sharedWith: List<String>.from(item['sharedWith'] ?? []));
              context.push('/file_viewer', extra: file);
            }
          }
        },
        onLongPress: () {
          _toggleSelection(item);
        },
        leading: isSelected
            ? Icon(Icons.check_circle, color: Colors.blue[800], size: 40)
            : Icon(
                isLink ? Icons.link : _getFileIcon(itemType),
                color: _getColorForFileType(itemType),
                size: 40,
              ),
        title: Text(itemName,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(size ?? ownerName),
        trailing: _isSelectionMode
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'share') {
                    _shareItems([item]);
                  } else if (value == 'remove') {
                    _removeItemsFromFavorites([item]);
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'share',
                    child: ListTile(
                      leading: Icon(Icons.share_outlined),
                      title: Text('Share'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'remove',
                    child: ListTile(
                      leading: Icon(Icons.favorite_border_rounded, color: Colors.red),
                      title: Text('Remove from Favorites',
                          style: TextStyle(color: Colors.red)),
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
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.video_file;
      case 'zip':
      case 'rar':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getColorForFileType(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return Colors.red.shade700;
      case 'doc':
      case 'docx':
        return Colors.blue.shade800;
      case 'ppt':
      case 'pptx':
        return Colors.orange.shade700;
      case 'xls':
      case 'xlsx':
        return Colors.green.shade700;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Colors.purple.shade600;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Colors.teal.shade600;
      case 'zip':
      case 'rar':
        return Colors.brown.shade600;
      case 'link':
        return Colors.indigo.shade600;
      default:
        return Colors.grey.shade700;
    }
  }

  String _formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  Future<void> _openExternalUrl(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not open URL: $url'),
              backgroundColor: Colors.red),
        );
    }
  }
}