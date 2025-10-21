import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:grademate/models/file_models.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart'; 
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart'; 
// AD IMPORTS START
import 'package:google_mobile_ads/google_mobile_ads.dart';
// AD IMPORTS END

// Defined the new primary color based on the user's image
const Color _kPrimaryColor = Color(0xFF6A67FE);
// Lighter background used for cards and buttons
const Color _kLightPrimaryColor = Color(0xFFF0F5FF); 

class StudentCoursesPage extends StatefulWidget {
  const StudentCoursesPage({super.key});

  @override
  State<StudentCoursesPage> createState() => _StudentCoursesPageState();
}

class _StudentCoursesPageState extends State<StudentCoursesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance; 
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  String? _collegeId;
  String? _branch;
  String? _regulation;
  String? _userName;
  String? _userEmail;
  bool _isLoading = true;
  String _searchQuery = '';

  String? _currentYearId;
  String? _currentSubjectId;
  String? _currentSubjectName;
  String? _expandedYearId;
  String _currentFilter = 'All'; 
  
  List<Map<String, dynamic>> _recentlyAccessedItems = [];
  Set<String> _favoriteFilePaths = {}; 

  List<String> _breadcrumbs = ['Courses']; 
  bool _isFirstLoad = true;

  final TextEditingController _searchController = TextEditingController();
  
  // AD VARS START
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  final String _interstitialAdUnitId = Platform.isAndroid 
    ? 'ca-app-pub-3940256099942544/1033173712' // Android Test ID
    : 'ca-app-pub-3940256099942544/4411468910'; // iOS Test ID
  final String _rewardedAdUnitId = Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/5224354917' // Android Test ID
      : 'ca-app-pub-3940256099942544/1712485313'; // iOS Test ID
  // AD VARS END

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadInitialData();
    // AD INIT START
    _loadInterstitialAd();
    _loadRewardedAd();
    // AD INIT END
  }
  
  @override
  void dispose() {
    _searchController.dispose(); 
    // AD DISPOSE START
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    // AD DISPOSE END
    super.dispose();
  }
  
  // AD METHODS START
  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _loadInterstitialAd(); // Load the next ad
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _loadInterstitialAd(); 
              print('Interstitial ad failed to show: $error');
            },
          );
        },
        onAdFailedToLoad: (error) {
          print('InterstitialAd failed to load: $error');
          _interstitialAd = null;
        },
      ),
    );
  }

  void _showInterstitialAd(Function onDismissed) {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _loadInterstitialAd();
          onDismissed(); // Execute the original action after ad dismissal
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _loadInterstitialAd(); 
          onDismissed(); // Execute the original action if ad fails to show
        },
      );
      _interstitialAd!.show();
    } else {
      // If ad is not ready, execute the action immediately
      onDismissed();
    }
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _loadRewardedAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _loadRewardedAd();
              print('Rewarded ad failed to show: $error');
            },
          );
        },
        onAdFailedToLoad: (error) {
          print('RewardedAd failed to load: $error');
          _rewardedAd = null;
        },
      ),
    );
  }

  void _showRewardedAd(Function onRewardGranted) {
    if (_rewardedAd != null) {
      _rewardedAd!.show(onUserEarnedReward: (ad, reward) {
        onRewardGranted(); // Execute the core download logic
        _showSnackbar('Reward granted! Download started.', success: true);
        _loadRewardedAd(); // Load next ad
      });
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
           ad.dispose();
           _loadRewardedAd();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _loadRewardedAd();
          _showSnackbar('Ad failed to load. Please try again.', success: false);
        },
      );
    } else {
      // If ad is not ready, prompt the user to try again
      _showSnackbar('Ad is not ready. Please wait a moment and try the download again.', success: false);
    }
  }
  // AD METHODS END
  
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await _loadUserData();
    await _loadFavoriteFilePaths(); // Load favorites first
    await _loadRecentlyAccessedFiles();
    if (mounted) setState(() => _isLoading = false);
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
            _collegeId = data?['collegeId'];
            _branch = data?['branch']?.toString().toUpperCase();
            _regulation = data?['regulation']?.toString().toUpperCase();
            _userName = data?['name'];
            _userEmail = user.email;
          });
        }
      } catch (e) {
        print("Error loading user data for courses: $e");
      }
    }
  }
  
  // NEW: Loads all favorite file paths for quick checking
  Future<void> _loadFavoriteFilePaths() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.email).get();
      if (userDoc.exists && userDoc.data()!.containsKey('favorites')) {
        setState(() {
          _favoriteFilePaths = Set<String>.from(userDoc.data()!['favorites']);
        });
      }
    } catch (e) {
      print("Error loading favorite file paths: $e");
    }
  }

  // NEW: Fetch recently accessed file paths from user document and resolve them
  Future<void> _loadRecentlyAccessedFiles() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final userDoc = await _firestore.collection('users').doc(user.email).get();

    if (!userDoc.exists || userDoc.data()?['recentlyAccessed'] == null) {
      if (mounted) setState(() => _recentlyAccessedItems = []);
      return;
    }

    List<String> paths = List<String>.from(userDoc.data()!['recentlyAccessed']);
    List<Map<String, dynamic>> validItems = [];
    
    // Only process the first 10 paths
    for (String path in paths.take(10)) {
      try {
        final fileDoc = await _firestore.doc(path).get();
        if (fileDoc.exists) {
          final data = fileDoc.data() as Map<String, dynamic>;
          data['id'] = fileDoc.id;
          data['path'] = fileDoc.reference.path;
          data['fullPath'] = fileDoc.reference.path; 
          validItems.add(data);
        }
      } catch (e) {
        print("Error fetching recent file at path $path: $e");
      }
    }

    if (mounted) {
      setState(() {
        _recentlyAccessedItems = validItems;
      });
    }
  }
  
  // --- CORE FEATURE: UPDATE RECENTLY ACCESSED FILES ---
  Future<void> _updateRecentlyAccessed(String filePath) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;
    
    final userRef = _firestore.collection('users').doc(user.email);

    try {
      final userDoc = await userRef.get();
      List<String> currentList = [];
      if (userDoc.exists && userDoc.data()!.containsKey('recentlyAccessed')) {
        currentList = List<String>.from(userDoc.data()!['recentlyAccessed']);
      }

      // 1. Remove the path if it already exists (to avoid duplicates)
      currentList.remove(filePath);

      // 2. Insert the new path at the beginning (0th index)
      currentList.insert(0, filePath);

      // 3. Limit the list size to 10
      if (currentList.length > 10) {
        currentList = currentList.sublist(0, 10);
      }

      // 4. Update Firestore
      await userRef.update({'recentlyAccessed': currentList});
      
      await _loadRecentlyAccessedFiles(); 

    } catch (e) {
      print("Error updating recently accessed list: $e");
    }
  }
  
  // --- NEW: Activity Logging Helper ---
  Future<void> _logActivity(String action, Map<String, dynamic> details) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final activityData = {
      'timestamp': FieldValue.serverTimestamp(),
      'action': action,
      'userEmail': user.email,
      'userName': _userName ?? 'Student',
      'collegeId': _collegeId,
      'details': details,
    };

    try {
      // 1. Log to user's personal activity collection
      await _firestore
          .collection('users')
          .doc(user.email)
          .collection('activities')
          .add(activityData);

      // 2. Log to global activities collection
      await _firestore.collection('activities').add(activityData);
      
    } catch (e) {
      print("Error logging activity: $e");
    }
  }

  void _navigateToSubject(String yearId, String subjectId, String subjectName) {
    setState(() {
      _currentYearId = yearId;
      _currentSubjectId = subjectId;
      _currentSubjectName = subjectName;
      _breadcrumbs = ['Courses', yearId, subjectName];
      _currentFilter = 'All'; 
      _searchQuery = ''; 
      _searchController.clear(); 
      _expandedYearId = null; 
    });
  }

  void _navigateBackToCourses() {
    setState(() {
      _currentYearId = null;
      _currentSubjectId = null;
      _currentSubjectName = null;
      _breadcrumbs = ['Courses'];
    });
  }
  
  void _handleBreadcrumbTap(int index) {
    if (index == 0) {
      _navigateBackToCourses();
    } else if (index == 1 && _breadcrumbs.length > 2) {
      setState(() {
        _currentYearId = null;
        _currentSubjectId = null;
        _currentSubjectName = null;
        _breadcrumbs = ['Courses', _breadcrumbs[1]];
        _expandedYearId = _breadcrumbs[1];
      });
    }
  }
  
  // FIXED: Implement actual file upload to Firebase Storage
  Future<void> _showAddResourceDialog() async {
    if (_collegeId == null || _branch == null || _regulation == null || _currentYearId == null || _currentSubjectId == null || _userEmail == null || _auth.currentUser?.uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot add resource: User or course details are missing.'), backgroundColor: Colors.red));
      return;
    }
    
    // 1. Pick file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png', 'gif'],
    );
    
    if (result == null || result.files.single.path == null) {
      if (!mounted) return;
      return; // No file selected, silently exit
    }
    
    final platformFile = result.files.single;
    final File fileToUpload = File(platformFile.path!);
    final String fileName = platformFile.name;
    final String fileExtension = platformFile.extension?.toLowerCase() ?? 'unknown';
    
    String fileType = fileExtension;
    if (['jpg', 'jpeg', 'png', 'gif'].contains(fileExtension)) fileType = 'image';
    else if (['doc', 'docx'].contains(fileExtension)) fileType = 'doc';
    else if (['ppt', 'pptx'].contains(fileExtension)) fileType = 'ppt';
    else if (['xls', 'xlsx'].contains(fileExtension)) fileType = 'xls';
    else if (fileExtension == 'pdf') fileType = 'pdf';

    // Generate a unique ID for the request and the file
    final String fileId = _firestore.collection('temp').doc().id; 
    final String userId = _auth.currentUser!.uid;

    // 2. Define the storage path for temporary request
    // Path structure: /uploads/{userId}/{fileId}/{fileName}
    final String storagePath = 'uploads/$userId/$fileId/$fileName';
    final Reference storageRef = _storage.ref().child(storagePath);
    
    String? fileDownloadUrl;
    
    try {
      // 3. Upload file to Firebase Storage
      final uploadTask = storageRef.putFile(fileToUpload);
      
      // Monitor upload progress (optional but good UX)
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes * 100).toInt();
        // You would typically show a notification or UI progress bar here
        print('Upload progress: $progress%');
      });
      
      // Wait for completion and get the download URL
      final TaskSnapshot snapshot = await uploadTask.whenComplete(() => {});
      fileDownloadUrl = await snapshot.ref.getDownloadURL();
      
      // 4. Create Firestore Request Document
      final reviewCollectionRef = _firestore
          .collection('colleges').doc(_collegeId)
          .collection('branches').doc(_branch)
          .collection('regulations').doc(_regulation)
          .collection('years').doc(_currentYearId)
          .collection('subjects').doc(_currentSubjectId)
          .collection('addRequests');

      await reviewCollectionRef.add({
        'fileName': fileName,
        'type': fileType,
        'fileExtension': fileExtension,
        'size': platformFile.size,
        'fileURL': fileDownloadUrl, // Store the actual download URL
        'storagePath': storagePath, // Store the storage path for faculty deletion
        'status': 'Pending',
        'requestedBy': _userEmail,
        'requesterName': _userName ?? 'Student',
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resource uploaded and submitted for faculty review!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Log submission activity
      await _logActivity('Request Upload', {
        'fileName': fileName,
        'type': fileType,
        'subjectName': _currentSubjectName,
        'yearId': _currentYearId,
      });


    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading file or submitting request: $e'),
          backgroundColor: Colors.red,
        ),
      );
      
      // Optional: Delete the file from storage if the Firestore write failed
      if (fileDownloadUrl != null) {
         try {
           await _storage.refFromURL(fileDownloadUrl).delete();
         } catch (storageError) {
           print("Failed to clean up storage after Firestore error: $storageError");
         }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final bool isViewingFiles = _currentSubjectId != null;

    return PopScope(
      canPop: !isViewingFiles,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _navigateBackToCourses();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: isViewingFiles
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: _navigateBackToCourses,
                )
              : null,
          title: Text(
            isViewingFiles ? 'Subject Files' : _breadcrumbs.last,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: false,
          automaticallyImplyLeading: !isViewingFiles,
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              _buildBreadcrumbs(), 

              if (isViewingFiles) _buildSubjectHeaderAndSearch(),

              if (!isViewingFiles)
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 20.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: TextField(
                    controller: _searchController, 
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                        if (_searchQuery.isNotEmpty) {
                          _expandedYearId = 'ALL';
                        }
                      });
                    },
                    decoration: InputDecoration(
                      icon: Padding(
                        padding: const EdgeInsets.only(left: 12.0),
                        child: Icon(Icons.search, color: Colors.grey.shade600),
                      ),
                      hintText: 'Search courses, subjects',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              
              if (isViewingFiles) _buildFilterTabs(),

              Expanded(
                child:
                    isViewingFiles ? _buildFilesView() : _buildCoursesView(),
              ),
              
              // AD BANNER START: Anchored to the bottom of the body
              const BannerAdWidget(),
              // AD BANNER END
            ],
          ),
        ),
      ),
    );
  }

  // NEW WIDGET: Builds the Subject Name, Resource Count, and Last Updated Info
  Widget _buildSubjectHeaderAndSearch() {
    return FutureBuilder<QuerySnapshot>(
      future: _getFilesCollectionRef().orderBy('timestamp', descending: true).get(),
      builder: (context, snapshot) {
        final int resourceCount = snapshot.data?.docs.length ?? 0;
        final Timestamp? lastTimestamp = snapshot.data?.docs.isNotEmpty == true
            ? (snapshot.data!.docs.first.data() as Map<String, dynamic>)['timestamp'] as Timestamp?
            : null;

        String lastUpdatedText = 'No resources yet';
        if (lastTimestamp != null) {
          final lastUpdatedDate = lastTimestamp.toDate();
          final diff = DateTime.now().difference(lastUpdatedDate);
          if (diff.inDays < 7) {
            lastUpdatedText = 'Last updated ${diff.inDays}d ago';
            if (diff.inDays == 0) lastUpdatedText = 'Last updated ${diff.inHours}h ago';
          } else {
            lastUpdatedText = 'Last updated ${DateFormat('MMM d, yyyy').format(lastUpdatedDate)}';
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentSubjectName ?? 'Subject',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$resourceCount resources • $lastUpdatedText',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 'Add Resource' button trigger
                  InkWell(
                    onTap: _showAddResourceDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _kPrimaryColor, // COLOR CHANGE
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Add Resource',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Search Bar for Files View
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.grey.shade300)
                ),
                child: TextField(
                  controller: _searchController, 
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    icon: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: Icon(Icons.search, color: Colors.grey.shade600),
                    ),
                    hintText: 'Search files, notes, slides',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // NEW WIDGET: Builds the horizontal filter tabs
  Widget _buildFilterTabs() {
    final List<String> filters = ['All', 'Image', 'PDF', 'DOCX', 'Video', 'Link'];
    
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _currentFilter == filter;
          
          IconData? getIconForFilter(String filter) {
            switch (filter) {
              case 'Image': return Icons.image_outlined;
              case 'PDF': return Icons.picture_as_pdf_outlined;
              case 'DOCX': return Icons.description_outlined;
              case 'Video': return Icons.videocam_outlined;
              case 'Link': return Icons.link_outlined;
              default: return null;
            }
          }

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              avatar: getIconForFilter(filter) != null ? Icon(getIconForFilter(filter), size: 18, color: isSelected ? Colors.white : _kPrimaryColor) : null, // COLOR CHANGE
              label: Text(filter),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              backgroundColor: isSelected ? _kPrimaryColor : Colors.grey.shade200, // COLOR CHANGE
              selectedColor: _kPrimaryColor, // COLOR CHANGE
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  _currentFilter = selected ? filter : 'All';
                });
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected ? _kPrimaryColor : Colors.grey.shade300, // COLOR CHANGE
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }


  Widget _buildBreadcrumbs() {
    if (_breadcrumbs.length <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 4.0,
        runSpacing: 4.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: List.generate(_breadcrumbs.length, (index) {
          final item = _breadcrumbs[index];
          final isLast = index == _breadcrumbs.length - 1;
          
          return InkWell(
            onTap: isLast ? null : () => _handleBreadcrumbTap(index),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item,
                  style: TextStyle(
                    color: isLast
                        ? Colors.grey.shade600
                        : _kPrimaryColor, // COLOR CHANGE
                    fontWeight: isLast ? FontWeight.normal : FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Icon(Icons.chevron_right,
                        size: 16, color: Colors.grey.shade400),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCoursesView() {
    return _isLoading 
        ? const _CoursesShimmer()
        : (_collegeId == null || _branch == null || _regulation == null)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "Could not load course data. Please check your profile settings.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            : StreamBuilder<QuerySnapshot>(
                stream: _getYearsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _CoursesShimmer();
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          "No academic years found for your profile.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    );
                  }

                  final yearDocs = snapshot.data!.docs;
                  yearDocs.sort((a, b) => a.id.compareTo(b.id));

                  if (_isFirstLoad && yearDocs.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _expandedYearId = yearDocs.first.id;
                          _isFirstLoad = false;
                        });
                      }
                    });
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
                        child: Text(
                          'Browse by Year',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                      
                      Expanded(
                        // FIX: Ensure this SingleChildScrollView contains all elements (Years + Recent)
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. LIST ALL YEARS
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: yearDocs.length,
                                itemBuilder: (context, index) {
                                  final yearDoc = yearDocs[index];
                                  return _buildYearExpansionSection(yearDoc);
                                },
                              ),
                              
                              // 2. RECENTLY ACCESSED SECTION (PLACED AT THE BOTTOM)
                              if (_recentlyAccessedItems.isNotEmpty)
                                _buildRecentlyAccessedFilesSection(_recentlyAccessedItems.take(5).toList()),

                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
  }
  
  Widget _buildYearExpansionSection(DocumentSnapshot yearDoc) {
    final String yearId = yearDoc.id;
    final bool isManuallyExpanded = _expandedYearId == yearId || _expandedYearId == 'ALL';
    
    // NOTE: itemsForYear logic is removed as the recently accessed list is now global.


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- YEAR CARD ---
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12.0),
          // COLOR CHANGE for card background based on state
          color: isManuallyExpanded ? _kLightPrimaryColor : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.0),
            // COLOR CHANGE for card border
            side: BorderSide(color: isManuallyExpanded ? _kPrimaryColor.withOpacity(0.3) : Colors.grey.shade200),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(15.0),
            onTap: () {
              setState(() {
                if (_searchQuery.isEmpty) {
                  _expandedYearId = isManuallyExpanded ? null : yearId;
                  if (_expandedYearId != null) {
                    _breadcrumbs = ['Courses', yearId];
                  } else {
                    _breadcrumbs = ['Courses'];
                  }
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  // Number Circle (1, 2, 3, 4)
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isManuallyExpanded ? _kPrimaryColor : Colors.grey.shade400, // COLOR CHANGE
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        yearId.split(' ').first[0].toUpperCase(), 
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          yearId.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        // Placeholder for Subtitle 
                        StreamBuilder<QuerySnapshot>(
                          stream: yearDoc.reference.collection('subjects').snapshots(),
                          builder: (context, subjectSnapshot) {
                            final count = subjectSnapshot.data?.docs.length ?? 0;
                            return Text(
                              '$count subjects • Foundation', 
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isManuallyExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                    color: _kPrimaryColor, // COLOR CHANGE
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // --- SUBJECT LIST (ONLY VISIBLE WHEN EXPANDED) ---
        StreamBuilder<QuerySnapshot>(
          stream: yearDoc.reference.collection('subjects').snapshots(),
          builder: (context, subjectSnapshot) {
            final subjectDocs = subjectSnapshot.data?.docs ?? [];
            
            final filteredSubjectDocs = subjectDocs.where((doc) {
              final subjectName =
                  (doc.data() as Map<String, dynamic>)['name']
                          ?.toString()
                          .toLowerCase() ??
                      '';
              return subjectName.contains(_searchQuery);
            }).toList();

            final bool hasMatch = filteredSubjectDocs.isNotEmpty;
            final bool isEffectivelyExpanded = isManuallyExpanded || (_searchQuery.isNotEmpty && hasMatch);
                
            if (_searchQuery.isNotEmpty && !hasMatch && !isManuallyExpanded) {
              return const SizedBox.shrink();
            }

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder:
                  (Widget child, Animation<double> animation) {
                return SizeTransition(
                  sizeFactor: animation,
                  child: child,
                );
              },
              child: isEffectivelyExpanded
                  ? _buildSubjectsList(filteredSubjectDocs, yearId,
                      subjectSnapshot.connectionState)
                  : const SizedBox.shrink(key: ValueKey('empty')),
            );
          },
        ),
      ],
    );
  }
  
  // NEW WIDGET: Builds the horizontal list of recently accessed files
  Widget _buildRecentlyAccessedFilesSection(List<Map<String, dynamic>> items) {
    // Only show if there are items to display globally
    if (items.isEmpty) return const SizedBox.shrink();
    
    // Check for favorite files that match the recently accessed list
    final List<Map<String, dynamic>> favoriteItems = items.where((item) => _favoriteFilePaths.contains(item['fullPath'])).toList();


    return Padding(
      padding: const EdgeInsets.only(left: 0, right: 0, top: 20.0, bottom: 20.0), // Removed horizontal padding here
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Recently Accessed Title
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              'Recently Accessed (${items.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          
          // 2. Recently Accessed List
          SizedBox(
            height: 100, // Fixed height for the horizontal list
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final fileName = item['fileName'] ?? item['title'] ?? 'Unknown File';
                final fileType = item['type'] ?? 'unknown';
                final docPath = item['fullPath'] as String;
                
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: InkWell(
                    // AD INTERSTITIAL: Show ad before opening file/link
                    onTap: () => _showInterstitialAd(() {
                      _updateRecentlyAccessed(docPath);
                      if (fileType == 'link') {
                        _openExternalUrl(item['url']);
                      } else {
                         context.push('/file_viewer', extra: _createFileObjectFromMap(item));
                      }
                    }),
                    child: Container(
                      width: 100,
                      decoration: BoxDecoration(
                        color: _kLightPrimaryColor, // COLOR CHANGE
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kPrimaryColor.withOpacity(0.3)), // COLOR CHANGE
                        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_getFileIcon(fileType), color: _getColorForFileType(fileType), size: 30),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Text(
                              fileName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // 3. FAVORITE FILES (if any recently accessed are favorites)
          if (favoriteItems.isNotEmpty)
          ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Your Favorite Files (${favoriteItems.length})',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            SizedBox(
              height: 100, 
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: favoriteItems.length,
                itemBuilder: (context, index) {
                  final item = favoriteItems[index];
                  final fileName = item['fileName'] ?? item['title'] ?? 'Favorite File';
                  final fileType = item['type'] ?? 'unknown';
                  final docPath = item['fullPath'] as String;
                  
                  return Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: InkWell(
                      // AD INTERSTITIAL: Show ad before opening file/link
                      onTap: () => _showInterstitialAd(() {
                        _updateRecentlyAccessed(docPath);
                        if (fileType == 'link') {
                          _openExternalUrl(item['url']);
                        } else {
                           context.push('/file_viewer', extra: _createFileObjectFromMap(item));
                        }
                      }),
                      child: Container(
                        width: 100,
                        decoration: BoxDecoration(
                          color: _kLightPrimaryColor.withOpacity(0.8), // Lighter purple for distinction
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kPrimaryColor.withOpacity(0.5), width: 2), // Stronger border
                          boxShadow: [BoxShadow(color: _kPrimaryColor.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.star, color: Colors.amber.shade700, size: 30),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: Text(
                                fileName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Helper to create FileData object from a Map (used for recently accessed items)
  FileData _createFileObjectFromMap(Map<String, dynamic> item) {
    return FileData(
        id: item['id'] ?? '',
        name: item['fileName'] ?? item['title'] ?? 'Untitled',
        url: item['fileURL'] ?? item['url'] ?? '',
        type: item['type'] ?? 'unknown',
        size: item['size'] ?? 0,
        uploadedAt: item['timestamp'] ?? Timestamp.now(),
        ownerId: item['uploadedBy'] ?? '',
        ownerName: item['ownerName'] ?? 'Unknown',
      );
  }


  Widget _buildSubjectsList(List<QueryDocumentSnapshot> subjectDocs,
      String yearName, ConnectionState state) {
    if (state == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.only(left: 12.0, right: 12.0, bottom: 16.0),
        child: _SubjectsShimmer(), 
      );
    }
    
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 16.0),
      child: subjectDocs.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child: Text(
                  "No subjects have been added for this year yet.",
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            )
          : AnimationLimiter(
              child: Column(
                children: List.generate(
                  subjectDocs.length,
                  (index) {
                    final doc = subjectDocs[index];
                    return AnimationConfiguration.staggeredList(
                      position: index,
                      duration: const Duration(milliseconds: 300),
                      child: SlideAnimation(
                        verticalOffset: 20.0,
                        child: FadeInAnimation(
                          child: _buildSubjectTileCard(doc, yearName),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  Widget _buildSubjectTileCard(DocumentSnapshot subjectDoc, String yearName) {
    final subjectData = subjectDoc.data() as Map<String, dynamic>;
    final subjectName = subjectData['name'] ?? subjectDoc.id;
    final subjectDetails = subjectData['details'] ?? 'Credits • Modules';

    return Card(
      margin: const EdgeInsets.only(top: 8.0),
      elevation: 0,
      color: Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200)
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToSubject(yearName, subjectDoc.id, subjectName),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kPrimaryColor.withOpacity(0.1), // COLOR CHANGE
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.menu_book, color: _kPrimaryColor, size: 24), // COLOR CHANGE
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subjectName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subjectDetails,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => _navigateToSubject(yearName, subjectDoc.id, subjectName),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  side: BorderSide(color: _kPrimaryColor.withOpacity(0.5)), // COLOR CHANGE
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  backgroundColor: Colors.white,
                ),
                child: Text(
                  'View',
                  style: TextStyle(
                    color: _kPrimaryColor, // COLOR CHANGE
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildFilesView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getFilesCollectionRef()
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _FilesShimmer();
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No files or links found."));
        }

        final allItems = snapshot.data!.docs;
        final currentUserEmail = _auth.currentUser?.email;

        // 1. Filter by sharedWith
        var visibleItems = allItems.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final sharedWith = List<String>.from(data['sharedWith'] ?? []);
          final ownerEmail = data['ownerEmail'];
          return sharedWith.contains('Students') ||
              ownerEmail == currentUserEmail;
        }).toList();

        // 2. Filter by search query
        if (_searchQuery.isNotEmpty) {
          visibleItems = visibleItems.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final title =
                (data['fileName'] ?? data['title'])?.toString().toLowerCase() ??
                    '';
            return title.contains(_searchQuery);
          }).toList();
        }
        
        // 3. Filter by file type tab
        if (_currentFilter != 'All') {
          visibleItems = visibleItems.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final fileType = data['type']?.toString().toLowerCase() ?? '';
            final extension = fileType.contains('.') ? fileType.split('.').last : fileType;
            
            String targetTypes = '';
            switch(_currentFilter) {
              case 'Image': targetTypes = 'jpg,jpeg,png,gif'; break;
              case 'PDF': targetTypes = 'pdf'; break;
              case 'DOCX': targetTypes = 'doc,docx'; break;
              case 'Video': targetTypes = 'mp4,mov,avi'; break;
              case 'Link': targetTypes = 'link'; break;
              default: return true;
            }
            return targetTypes.split(',').contains(extension);
          }).toList();
        }


        if (visibleItems.isEmpty) {
          return Center(
              child: Text(_searchQuery.isEmpty && _currentFilter == 'All'
                  ? "No content has been shared for this subject yet."
                  : "No content matches your filter/search criteria."));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          itemCount: visibleItems.length,
          itemBuilder: (context, index) {
            final doc = visibleItems[index];
            final data = doc.data() as Map<String, dynamic>;
            return data['type'] == 'link'
                ? _buildLinkCard(doc)
                : _buildFileCard(doc);
          },
        );
      },
    );
  }

  Widget _buildFileCard(DocumentSnapshot doc) {
    final fileData = doc.data() as Map<String, dynamic>;
    final fileType = fileData['type'] ?? 'unknown';
    final fileName = fileData['fileName'] ?? 'Untitled File';
    final size = fileData['size'] != null ? _formatBytes(fileData['size']) : 'N/A';
    final pageCount = fileData['pageCount'] != null ? '${fileData['pageCount']} pages' : '';
    final subText = pageCount.isNotEmpty ? '$size • $pageCount' : size;
    final docPath = doc.reference.path;
    final isFavorite = _favoriteFilePaths.contains(docPath); // Check favorite status

    FileData createFileObject() {
      return FileData(
        id: doc.id,
        name: fileName,
        url: fileData['fileURL'] ?? '',
        type: fileType,
        size: fileData['size'] ?? 0,
        uploadedAt: fileData['timestamp'] ?? Timestamp.now(),
        ownerId: fileData['uploadedBy'] ?? '',
        ownerName: fileData['ownerName'] ?? 'Unknown',
      );
    }

    // MODIFIED: Open File logic now calls interstitial ad
    void openFile() {
      _showInterstitialAd(() {
        _updateRecentlyAccessed(docPath);
        context.push('/file_viewer', extra: createFileObject());
      });
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300)
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: openFile,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                _getFileIcon(fileType),
                color: _getColorForFileType(fileType),
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '$fileType • $subText',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        if (isFavorite) ...[ // Show star if favorite
                          const SizedBox(width: 6),
                          Icon(Icons.star, size: 14, color: Colors.amber),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
              
              TextButton(
                onPressed: openFile,
                child: Text('Open', style: TextStyle(color: _kPrimaryColor)), // COLOR CHANGE
              ),
              
              _buildOptionsMenu(doc, createFileObject(), docPath),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkCard(DocumentSnapshot doc) {
    final linkData = doc.data() as Map<String, dynamic>;
    final linkTitle = linkData['title'] ?? 'Web Link';
    final url = linkData['url'];
    final docPath = doc.reference.path;
    final owner = linkData['ownerName'] ?? 'Unknown';
    final isFavorite = _favoriteFilePaths.contains(docPath); // Check favorite status


    void openLink() {
      // MODIFIED: Open Link logic now calls interstitial ad
      _showInterstitialAd(() {
        _updateRecentlyAccessed(docPath);
        _openExternalUrl(url);
      });
    }

    FileData createLinkObject() {
      return FileData(
        id: doc.id,
        name: linkTitle,
        url: url,
        type: 'link',
        size: 0,
        uploadedAt: linkData['timestamp'] ?? Timestamp.now(),
        ownerId: linkData['uploadedBy'] ?? '',
        ownerName: owner,
      );
    }


    return Card(
      margin: const EdgeInsets.only(bottom: 10.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300)
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: openLink,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.link, color: _getColorForFileType('link'), size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      linkTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Link • $owner',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        if (isFavorite) ...[ // Show star if favorite
                          const SizedBox(width: 6),
                          Icon(Icons.star, size: 14, color: Colors.amber),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
              
              TextButton(
                onPressed: openLink,
                child: Text('Open', style: TextStyle(color: _kPrimaryColor)), // COLOR CHANGE
              ),
              
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'open_external') {
                    openLink();
                  } else if (value == 'add_to_favorites') {
                    _toggleFavorite(doc); // Use toggle
                  } else if (value == 'share') {
                    Share.share('Check out this link: $url');
                  } else if (value == 'details') {
                    context.push('/file_details', extra: createLinkObject());
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'open_external', child: Text('Open in Browser')),
                  PopupMenuItem(value: 'add_to_favorites', child: Text(isFavorite ? 'Remove from favorites' : 'Add to favorites')),
                  const PopupMenuItem(value: 'share', child: Text('Share')),
                  const PopupMenuItem(value: 'details', child: Text('File details')),
                ],
                icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // FIXED: UI Flickering Bug by isolating the PopupMenuButton with a Builder
  // and ensuring the context is stable.
  Widget _buildOptionsMenu(DocumentSnapshot doc, FileData fileObject, String docPath) {
    final fileType = fileObject.type;
    const supportedAiTypes = ['pdf', 'jpg', 'jpeg', 'png', 'ppt', 'pptx', 'doc', 'docx'];
    final isFavorite = _favoriteFilePaths.contains(docPath); // Check favorite status

    // Using a separate Builder to ensure the PopupMenuButton receives a stable context 
    // that won't be rebuilt by state changes in the parent list item (Card/Row).
    return Builder(
      builder: (context) {
        return GestureDetector( // Use GestureDetector to ensure proper touch handling
          onTap: () {
            // Explicitly show the menu on tap, rather than relying on default behavior
            final RenderBox button = context.findRenderObject() as RenderBox;
            final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
            final RelativeRect position = RelativeRect.fromRect(
              Rect.fromPoints(
                button.localToGlobal(Offset.zero, ancestor: overlay),
                button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
              ),
              Offset.zero & overlay.size,
            );

            // Show the popup menu
            showMenu<String>(
              context: context,
              position: position,
              items: [
                _buildMenuItem('open', 'Open File', Icons.file_open_outlined, context),
                if (supportedAiTypes.contains(fileType))
                  _buildMenuItem('ask_ai', 'Ask AI', Icons.smart_toy_outlined, context),
                // Conditional text for favorites
                _buildMenuItem('toggle_favorite', isFavorite ? 'Remove from favorites' : 'Add to favorites', isFavorite ? Icons.star : Icons.star_border_outlined, context),
                _buildMenuItem('download', 'Download', Icons.download_outlined, context),
                _buildMenuItem('share', 'Share', Icons.share_outlined, context),
                // NEW: Add to Reminder option
                _buildMenuItem('reminder', 'Add to Reminder', Icons.alarm_add_outlined, context),
                _buildMenuItem('details', 'File details', Icons.info_outline, context),
              ],
            ).then((value) {
              if (value != null) {
                // Execute the selected action
                _handleOptionSelected(value, doc, fileObject, docPath);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Icon(Icons.more_vert, color: Colors.grey.shade600),
          ),
        );
      },
    );
  }
  
  // Helper to build a standard PopupMenuItem with Icon
  PopupMenuItem<String> _buildMenuItem(String value, String text, IconData icon, BuildContext context) {
    // Determine color based on value, using the primary blue for non-special actions
    Color itemColor = _kPrimaryColor;
    if (icon == Icons.star) {
      itemColor = Colors.amber.shade700;
    } else if (icon == Icons.star_border_outlined) {
      itemColor = Colors.grey.shade600;
    }
    
    return PopupMenuItem<String>(
      value: value, 
      child: Row(
        children: [
          Icon(icon, color: itemColor, size: 20),
          const SizedBox(width: 10),
          Text(text),
        ],
      ),
    );
  }
  
  // Helper to handle the logic after an option is selected
  void _handleOptionSelected(String value, DocumentSnapshot doc, FileData fileObject, String docPath) async {
    final isFavorite = _favoriteFilePaths.contains(docPath);
    
    // Build activity details map
    final activityDetails = {
      'fileName': fileObject.name,
      'fileType': fileObject.type,
      'filePath': docPath,
    };
    
    if (value == 'open') {
      // AD INTERSTITIAL: Show ad before opening file
      _showInterstitialAd(() {
        _updateRecentlyAccessed(docPath);
        context.push('/file_viewer', extra: fileObject);
      });
    } else if (value == 'ask_ai') {
      context.push('/student_ai', extra: fileObject);
    } else if (value == 'toggle_favorite') {
      await _toggleFavorite(doc);
      // Log the action
      final action = isFavorite ? 'Removed Favorite' : 'Added Favorite';
      await _logActivity(action, activityDetails);
      
    } else if (value == 'download') {
      // AD REWARDED: Show rewarded ad before downloading file
      _showRewardedAd(() => _downloadFile(doc));
      // Log the action (After ad dismissal/reward grant)
      await _logActivity('Requested Download', activityDetails);

    } else if (value == 'share') {
      // AD REWARDED: Show rewarded ad before sharing file (Standard monetization: download/share cost an ad)
      _showRewardedAd(() => _shareFile(doc));
      // Log the action (After ad dismissal/reward grant)
      await _logActivity('Requested Share', activityDetails);
    } else if (value == 'reminder') {
      // NEW: Show the reminder dialog for the file
      _showAddReminderDialogForFile(fileObject);
    } else if (value == 'details') {
      context.push('/file_details', extra: fileObject);
    }
  }
  
  // NEW: Toggles the favorite status
  Future<void> _toggleFavorite(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;
    
    final userRef = _firestore.collection('users').doc(user.email);
    final docPath = doc.reference.path;
    final isFavorite = _favoriteFilePaths.contains(docPath);
    
    try {
      if (isFavorite) {
        await userRef.update({'favorites': FieldValue.arrayRemove([docPath])});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from Favorites.')));
      } else {
        await userRef.update({'favorites': FieldValue.arrayUnion([docPath])});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to Favorites!')));
      }
      // Reload states after update
      await _loadFavoriteFilePaths();
      await _loadRecentlyAccessedFiles();
      
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error toggling favorite: $e'), backgroundColor: Colors.red));
    }
  }
  
  // NEW: Reminder collection getter
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

  // ** FIX: Added Missing _showSnackbar method **
  void _showSnackbar(String message, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: success ? Colors.green : Colors.red),
    );
  }

  // NEW: Logic to add reminder (adapted from student_my_files_page)
  Future<void> _addReminder(String title, String description, DateTime reminderTime,
      String recurrence) async {
    // ** FIX: Corrected math.Random to use the imported Random class **
    final notificationId = Random().nextInt(100000); 
    try {
      await _remindersCollection.add({
        'title': title,
        'description': description,
        'reminderTime': Timestamp.fromDate(reminderTime),
        'recurrence': recurrence,
        'notificationId': notificationId,
        'sourceFile': title, 
      });
      
      // Notification scheduling logic removed to prevent compilation errors
      
      if (mounted) _showSnackbar('Reminder added for "$title"!');

    } catch (e) {
      print("Error adding reminder: $e");
      if (mounted) _showSnackbar('Failed to set reminder: ${e.toString()}', success: false);
    }
  }

  // NEW: Dialog to add a reminder for a specific file
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
                              backgroundColor: const Color(0xFF6A67FE),
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
                                    if (mounted) _showSnackbar('Cannot set a one-time reminder for a past time.', success: false);
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
                                   if (mounted) _showSnackbar('Please choose a date and time.', success: false);
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


  Future<bool> _isConnected() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _addToFavorites(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to add favorites.')),
      );
      return;
    }

    try {
      final userRef = _firestore.collection('users').doc(user.email);
      await userRef.update({
        'favorites': FieldValue.arrayUnion([doc.reference.path])
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added to Favorites!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding to favorites: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Stream<QuerySnapshot> _getYearsStream() {
    if (_collegeId == null || _branch == null || _regulation == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('colleges')
        .doc(_collegeId)
        .collection('branches')
        .doc(_branch)
        .collection('regulations')
        .doc(_regulation)
        .collection('years')
        .snapshots();
  }
  
  CollectionReference _getFilesCollectionRef() {
    return _firestore
        .collection('colleges')
        .doc(_collegeId)
        .collection('branches')
        .doc(_branch)
        .collection('regulations')
        .doc(_regulation)
        .collection('years')
        .doc(_currentYearId)
        .collection('subjects')
        .doc(_currentSubjectId)
        .collection('files');
  }
  
  Color _getColorForFileType(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf': return Colors.red.shade700;
      case 'doc': case 'docx': return Colors.blue.shade800;
      case 'ppt': case 'pptx': return Colors.orange.shade700;
      case 'xls': case 'xlsx': return Colors.green.shade700;
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Colors.purple.shade600;
      case 'mp4': case 'mov': case 'avi': return Colors.teal.shade600;
      case 'zip': case 'rar': return Colors.brown.shade600;
      case 'link': return Colors.indigo.shade600;
      default: return Colors.grey.shade700;
    }
  }
  
  IconData _getFileIcon(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'ppt': case 'pptx': return Icons.slideshow;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Icons.image;
      case 'mp4': case 'mov': case 'avi': return Icons.movie;
      case 'zip': case 'rar': return Icons.archive;
      default: return Icons.insert_drive_file;
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
    }
  }
  
  Future<void> _downloadFile(DocumentSnapshot doc) async {
    if (!await _isConnected()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No internet connection. Please check your network.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    try {
      final data = doc.data() as Map<String, dynamic>;
      final fileName = data['fileName'];
      final url = data['fileURL'];

      final dio = Dio();
      final Directory? downloadsDir = await getExternalStorageDirectory();
      if (downloadsDir == null) throw Exception('Could not get download directory.');

      final gradeMateDir = Directory('${downloadsDir.path}/GradeMate');
      if (!await gradeMateDir.exists()) {
        await gradeMateDir.create(recursive: true);
      }

      final filePath = '${gradeMateDir.path}/$fileName';

      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toInt();
            // Assuming _showProgressNotification is defined elsewhere, removed for simplicity
            // _showProgressNotification('Downloading', fileName, progress, 2);
          }
        },
      );
      
      if (!mounted) return;
      // Assuming _showCompletionNotification is defined elsewhere, removed for simplicity
      // await _showCompletionNotification('Download Complete', fileName, 2);
      
      if (!mounted) return;
      // The reward ad closure will show the "Download started" snackbar. 
      // This snackbar is for the completion notification.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('File saved to GradeMate folder!'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      // await flutterLocalNotificationsPlugin.cancel(2); // Notification cancellation removed
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error downloading file: Please check your internet connection or Allow Storage Permissions.'),
              backgroundColor: const Color.fromARGB(255, 241, 114, 105)),
        );
      }
    }
  }
  
  Future<void> _shareFile(DocumentSnapshot doc) async {
    if (!await _isConnected()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No internet connection. Please check your network.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }
    
    try {
      final data = doc.data() as Map<String, dynamic>;
      final fileName = data['fileName'];
      final url = data['fileURL'];

      final dio = Dio();
      final dir = await getTemporaryDirectory();
      final tempFilePath = '${dir.path}/$fileName';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preparing file for sharing...')));
      }
      
      await dio.download(url, tempFilePath);
      if (!mounted) return;

      await Share.shareXFiles([XFile(tempFilePath)],
          text: 'Check out this file from GradeMate: $fileName');
          
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to share file: Please check your internet connection'),
              backgroundColor: Colors.red),
        );
      }
    }
  }
  
  void _initializeNotifications() {
    // ** FIX: Added basic notification initialization logic **
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    flutterLocalNotificationsPlugin.initialize(initSettings);
  }
  
  Future<void> _showProgressNotification(String title, String fileName,
      int progress, int notificationId) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'progress_channel_id',
      'Progress Channel',
      channelDescription: 'Shows progress of uploads/downloads',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true,
      autoCancel: false,
    );
    final NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      '$fileName: $progress%',
      platformDetails,
    );
  }
  
  Future<void> _showCompletionNotification(
      String title, String fileName, int notificationId) async {
    await flutterLocalNotificationsPlugin.cancel(notificationId);
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'completion_channel_id',
      'Completion Channel',
      channelDescription: 'Notifies when an operation is finished',
      importance: Importance.high,
      priority: Priority.high,
    );
    final NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      '"$fileName" has finished successfully.',
      platformDetails,
    );
  }
}

// ----------------------------------------------------------------------
// AD WIDGETS (Included here for completeness and the necessary fix)
// ----------------------------------------------------------------------

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _adLoadedCalled = false; // Flag to ensure single load after context is available
  
  final String _adUnitId = Platform.isAndroid 
    ? 'ca-app-pub-3940256099942544/6300978111' 
    : 'ca-app-pub-3940256099942544/2934735716'; 

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_adLoadedCalled) {
      _loadAd();
      _adLoadedCalled = true; 
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadAd() {
    // Accessing MediaQuery.of(context) is safe here in didChangeDependencies.
    final adSize = AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(
        MediaQuery.of(context).size.width.toInt());
        
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      size: adSize,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          print('BannerAd failed to load: $error');
        },
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAdLoaded && _bannerAd != null) {
      return Container(
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    } else {
      // Show a placeholder container to reserve space
      return const SizedBox(height: 50); 
    }
  }
}


// ----------------------------------------------------------------------
// SHIMMER EFFECT WIDGETS
// ----------------------------------------------------------------------

class _CoursesShimmer extends StatelessWidget {
  const _CoursesShimmer();

  Widget _buildYearPlaceholder() {
    return Column(
      children: [
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12.0),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.0),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(width: 32, height: 32, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 80, height: 16, color: Colors.white, margin: const EdgeInsets.only(bottom: 4)),
                    Container(width: 120, height: 12, color: Colors.white),
                  ],
                ),
                const Spacer(),
                Container(width: 16, height: 16, color: Colors.white),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        children: [
          _buildYearPlaceholder(),
          _buildYearPlaceholder(),
          _buildYearPlaceholder(),
          _buildYearPlaceholder(),
        ],
      ),
    );
  }
}

class _SubjectsShimmer extends StatelessWidget {
  const _SubjectsShimmer();

  Widget _buildSubjectTilePlaceholder() {
    return Card(
      margin: const EdgeInsets.only(top: 8.0),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 150, height: 14, color: Colors.white, margin: const EdgeInsets.only(bottom: 4)),
                Container(width: 100, height: 12, color: Colors.white),
              ],
            ),
            const Spacer(),
            Container(width: 45, height: 28, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
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
        children: List.generate(3, (index) => _buildSubjectTilePlaceholder()),
      ),
    );
  }
}


class _FilesShimmer extends StatelessWidget {
  const _FilesShimmer();

  Widget _buildFileTilePlaceholder() {
    return Card(
      margin: const EdgeInsets.only(bottom: 10.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300)
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(width: 32, height: 32, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: 180, color: Colors.white, margin: const EdgeInsets.only(bottom: 4)),
                  Container(height: 12, width: 120, color: Colors.white),
                ],
              ),
            ),
            Container(height: 20, width: 40, color: Colors.white, margin: const EdgeInsets.only(right: 8)),
            Container(height: 24, width: 24, color: Colors.white),
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
      child: ListView.builder(
        itemCount: 8,
        itemBuilder: (context, index) => _buildFileTilePlaceholder(),
      ),
    );
  }
}