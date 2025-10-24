// job_updates_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart'; 
import 'package:google_mobile_ads/google_mobile_ads.dart'; // AdMob Import
import 'dart:io' show Platform; // Platform check for Ad Unit IDs
import 'package:flutter/foundation.dart'; // For kDebugMode

// Helper function to safely convert Timestamp or dynamic to a formatted String
String _formatDate(dynamic data, {bool isTimeAgo = false}) {
  if (data is Timestamp) {
    final DateTime date = data.toDate();
    
    if (isTimeAgo) {
        final Duration difference = DateTime.now().difference(date);
        
        if (difference.inHours < 24) {
            if (difference.inMinutes < 60) {
                return "${difference.inMinutes}m ago";
            } else {
                return "${difference.inHours}h ago";
            }
        } else if (difference.inDays < 7) {
            return "${difference.inDays}d ago";
        }
    }
    // Standard format for deadlines or older posts
    return DateFormat('MMM dd, yyyy').format(date); 
    
  } else if (data is String) {
    // If it's already a string, return it
    return data;
  }
  return 'N/A';
}

// --------------------------------------------------------------------------
// I. Data Model (JobModel) 
// --------------------------------------------------------------------------

class JobModel {
  final String eligibility;
  final String experience;
  final String jobDescription;
  final String jobTitle;
  final String jobType;
  final String lastDateToApply; 
  final String linkToApply;
  final String location;
  final String recruiter;
  final String salary;
  final String uploadedTime; 
  final String workMode;
  final String skills;

  JobModel({
    required this.eligibility,
    required this.experience,
    required this.jobDescription,
    required this.jobTitle,
    required this.jobType,
    required this.lastDateToApply,
    required this.linkToApply,
    required this.location,
    required this.recruiter,
    required this.salary,
    required this.uploadedTime, 
    required this.workMode,
    required this.skills,
  });

  factory JobModel.fromMap(Map<String, dynamic> data) {
    
    // Convert Dates
    final String formattedUploadedTime = _formatDate(data['uploadedTime'], isTimeAgo: true);
    final String formattedLastDate = _formatDate(data['lastDateToApply']);

    return JobModel(
      eligibility: data['eligibility'] ?? 'N/A',
      experience: data['experience'] ?? 'Fresher',
      jobDescription: data['jobDescription'] ?? 'No description provided.',
      jobTitle: data['jobTitle'] ?? 'Job Title Not Specified',
      jobType: data['jobType'] ?? 'Full-Time',
      lastDateToApply: formattedLastDate, 
      linkToApply: data['linkToApply'] ?? 'https://www.google.com', 
      location: data['location'] ?? 'Anywhere',
      recruiter: data['recruiter'] ?? 'Confidential',
      salary: data['salary'] ?? 'Not Disclosed',
      uploadedTime: formattedUploadedTime, 
      workMode: data['workMode'] ?? 'WFO',
      skills: data['skills'] ?? 'Skills are not given'
    );
  }
}

// --------------------------------------------------------------------------
// II. Job Updates Page (Listing View with Search & Filters)
// --------------------------------------------------------------------------

class JobUpdatesPage extends StatefulWidget {
  const JobUpdatesPage({super.key});

  @override
  State<JobUpdatesPage> createState() => _JobUpdatesPageState();
}

class _JobUpdatesPageState extends State<JobUpdatesPage> {
  static const Color _primaryColor = Color(0xFF6A67FE);
  String _searchQuery = '';
  String? _selectedJobType;
  String? _selectedWorkMode;

  final TextEditingController _searchController = TextEditingController();

  // --- AD MOB INTERSTITIAL VARIABLES ---
  InterstitialAd? _interstitialAd;
  final String _adUnitId = Platform.isAndroid 
    ? 'ca-app-pub-3940256099942544/1033173712' // Android Test ID
    : 'ca-app-pub-3940256099942544/4411468910'; // iOS Test ID
  // --- END AD MOB VARIABLES ---


  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadInterstitialAd(); // Load the interstitial ad on init
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _interstitialAd?.dispose(); // Dispose the ad
    super.dispose();
  }

  // --- MODIFIED AD MOB METHODS ---
  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          if (kDebugMode) //print('InterstitialAd failed to load: $error');
          _interstitialAd = null;
        },
      ),
    );
  }
  
  // Method to show ad and then execute URL launch (used by 'Apply Job')
  void _showAdAndLaunchUrl(BuildContext context, String url) {
    final Uri uri = Uri.parse(url);
    
    // Function to launch the URL after ad dismissal/failure
    Future<void> launch() async {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
  // 1. Hide the current snackbar (if one is showing)
  .hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the application link.')),
          );
        }
      }
    }

    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _loadInterstitialAd(); // Load the next ad
          launch(); // Execute the action after dismissal
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _loadInterstitialAd(); // Load the next ad
          if (kDebugMode) //print('Interstitial ad failed to show: $error');
          launch(); // Execute the action even if the ad fails to show
        },
      );
      _interstitialAd!.show();
    } else {
      // If ad is not ready, launch the URL directly and try to load a new ad.
      if (kDebugMode) //print('Ad not loaded, launching URL directly.');
      launch();
      _loadInterstitialAd(); 
    }
  }

  // NOTE: The _showAdAndNavigate method has been removed as it is no longer needed.
  // --- END AD MOB METHODS ---


  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedJobType = null;
      _selectedWorkMode = null;
    });
  }

  bool _jobMatchesFilters(JobModel job) {
    final titleMatch = job.jobTitle.toLowerCase().contains(_searchQuery);
    final recruiterMatch = job.recruiter.toLowerCase().contains(_searchQuery);
    final locationMatch = job.location.toLowerCase().contains(_searchQuery);
    
    final searchMatch = titleMatch || recruiterMatch || locationMatch;

    final typeMatch = _selectedJobType == null || job.jobType == _selectedJobType;
    final modeMatch = _selectedWorkMode == null || job.workMode == _selectedWorkMode;

    return searchMatch && typeMatch && modeMatch;
  }

  // New direct navigation function (without ad)
  void _navigateToJobDetails(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '💼 Job Updates',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _clearFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by job title, company, or location...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          // Filters (Horizontal Scrollable Chips)
          _buildFilterChips(),

          // Job Listing Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('job_updates')
                  .orderBy('uploadedTime', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const JobListingShimmer();
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading jobs: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No job updates available at the moment.',
                      style: GoogleFonts.inter(color: Colors.grey[600]),
                    ),
                  );
                }

                final allJobs = snapshot.data!.docs.map((doc) {
                  return JobModel.fromMap(doc.data() as Map<String, dynamic>);
                }).toList();

                final filteredJobs = allJobs.where(_jobMatchesFilters).toList();

                if (filteredJobs.isEmpty) {
                  return Center(
                    child: Text(
                      'No jobs match your search and filter criteria.',
                      style: GoogleFonts.inter(color: Colors.grey[600]),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                  itemCount: filteredJobs.length,
                  itemBuilder: (context, index) {
                    final job = filteredJobs[index];
                    // Pass the new direct navigation method
                    return JobCard(
                      job: job, 
                      primaryColor: _primaryColor, 
                      showAdAndLaunchUrl: _showAdAndLaunchUrl, 
                      navigateToJobDetails: _navigateToJobDetails, // MODIFIED
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // Widget to build the horizontal filter chips
  Widget _buildFilterChips() {
    const jobTypes = ['Full-Time', 'Internship', 'Contract'];
    const workModes = ['WFO', 'WFH', 'Hybrid'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        children: [
          // Job Type Filters
          ...jobTypes.map((type) => Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(type),
              selected: _selectedJobType == type,
              onSelected: (selected) {
                setState(() {
                  _selectedJobType = selected ? type : null;
                });
              },
              backgroundColor: Colors.grey.shade100,
              selectedColor: _primaryColor.withOpacity(0.2),
              labelStyle: GoogleFonts.inter(
                color: _selectedJobType == type ? _primaryColor : Colors.black87,
                fontWeight: _selectedJobType == type ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          )),
          const VerticalDivider(width: 20),
          // Work Mode Filters
          ...workModes.map((mode) => Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(mode),
              selected: _selectedWorkMode == mode,
              onSelected: (selected) {
                setState(() {
                  _selectedWorkMode = selected ? mode : null;
                });
              },
              backgroundColor: Colors.grey.shade100,
              selectedColor: _primaryColor.withOpacity(0.2),
              labelStyle: GoogleFonts.inter(
                color: _selectedWorkMode == mode ? _primaryColor : Colors.black87,
                fontWeight: _selectedWorkMode == mode ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          )),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// III. Job Card Widget (Listing Summary)
// --------------------------------------------------------------------------

class JobCard extends StatelessWidget {
  final JobModel job;
  final Color primaryColor;
  final Function(BuildContext context, String url) showAdAndLaunchUrl; 
  // Renamed and changed signature from showAdAndNavigate
  final Function(BuildContext context, Widget page) navigateToJobDetails; 
  
  const JobCard({
    required this.job, 
    required this.primaryColor,
    required this.showAdAndLaunchUrl, 
    required this.navigateToJobDetails, // MODIFIED
    super.key
  });

  // Use the passed function for URL launch (with ad)
  void _onApplyPressed(BuildContext context) {
    showAdAndLaunchUrl(context, job.linkToApply);
  }

  // Use the passed function for navigation (now direct)
  void _onViewJobPressed(BuildContext context) {
    // Calling the direct navigation method
    navigateToJobDetails(
      context,
      JobDetailsPage(
        job: job, 
        primaryColor: primaryColor, 
        showAdAndLaunchUrl: showAdAndLaunchUrl, // Still needed for Apply button on details page
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      margin: const EdgeInsets.only(bottom: 10.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Job Title and Recruiter
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.jobTitle,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        job.recruiter,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Uploaded Time
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text(
                    job.uploadedTime,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
            
            const Divider(height: 16, thickness: 1),

            // Summarized Details (Chips)
            Wrap(
              spacing: 6.0,
              runSpacing: 6.0,
              children: [
                _buildDetailChip(Icons.location_on_outlined, job.location, Colors.blue),
                _buildDetailChip(Icons.work_outline, job.workMode, Colors.green),
                _buildDetailChip(Icons.money, job.salary, Colors.orange),
                _buildDetailChip(Icons.calendar_month, 'Apply by: ${job.lastDateToApply}', Colors.red),
                _buildDetailChip(Icons.school_outlined, job.eligibility , const Color.fromARGB(255, 171, 54, 244)),
              ],
            ),
            
            const SizedBox(height: 10),
            
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 1. View Job Button - NOW USES DIRECT NAVIGATION
                TextButton(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: () => _onViewJobPressed(context), // MODIFIED to call the direct navigation function
                  child: Text('View Job', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                const SizedBox(width: 4),
                // 2. Apply Job Button (Opens Link with Ad)
                ElevatedButton.icon(
                  onPressed: () => _onApplyPressed(context), // Retains ad-then-launchUrl
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: const Text('Apply Job', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget for detail chips
  Widget _buildDetailChip(IconData icon, String label, Color color) {
    return Chip(
      label: Text(
        label,
        style: GoogleFonts.inter(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
      avatar: Icon(icon, size: 14, color: color),
      backgroundColor: color.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    );
  }
}


// --------------------------------------------------------------------------
// IV. Job Details Page (Full Description)
// --------------------------------------------------------------------------

class JobDetailsPage extends StatelessWidget {
  final JobModel job;
  final Color primaryColor;
  final Function(BuildContext context, String url) showAdAndLaunchUrl; 
  
  const JobDetailsPage({
    required this.job, 
    required this.primaryColor, 
    required this.showAdAndLaunchUrl, 
    super.key
  });

  // Use the passed function instead of direct URL launch (with ad)
  void _onApplyPressed(BuildContext context) {
    showAdAndLaunchUrl(context, job.linkToApply);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        // Set AppBar title to the Recruiter name to prevent overflow here
        title: Text(
          job.recruiter, 
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Job Title
            Text(
              job.jobTitle,
              style: GoogleFonts.inter(fontSize: 22, color: primaryColor, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),

            // Info Cards Layout
            Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildInfoCard('Location', job.location, Icons.pin_drop_outlined, primaryColor)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildInfoCard('Salary', job.salary, Icons.currency_rupee, primaryColor)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildInfoCard('Work Mode', job.workMode, Icons.laptop_chromebook, primaryColor)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildInfoCard('Job Type', job.jobType, Icons.schedule_outlined, primaryColor)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildInfoCard('Experience', job.experience, Icons.badge_outlined, primaryColor)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildInfoCard('Eligibility', job.eligibility, Icons.school_outlined, primaryColor)),
                  ],
                ),
              ],
            ),
            
            const Divider(height: 32, thickness: 1),

            // Job Description Section
            _buildSectionHeader('📄 Job Description'),
            Text(
              job.jobDescription,
              style: GoogleFonts.inter(fontSize: 16, height: 1.5, color: Colors.black87),
            ),
            const SizedBox(height: 20),

            // Skills Section
            _buildSectionHeader('🛠️ Required Skills & Qualifications'),
            Text(
              job.skills,
              style: GoogleFonts.inter(fontSize: 16, height: 1.5, color: Colors.black87),
            ),

            // Application Deadline Section
            _buildSectionHeader('📅 Application Deadline'),
            Row(
              children: [
                Icon(Icons.date_range, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  job.lastDateToApply,
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      // Persistent Apply Button at the bottom
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: () => _onApplyPressed(context), // Retains ad-then-launchUrl
            icon: const Icon(Icons.open_in_new),
            label: const Text('Go to Application Link', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }

  // Helper widget for the flexible Info Card
  Widget _buildInfoCard(String title, String subtitle, IconData icon, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: primaryColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Subtitle expands vertically as needed
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  // Helper widget for section headers
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 10.0),
      child: Text(
        title,
        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  // Helper widget for placeholder bullet points (kept for completeness)
  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6.0, right: 8.0),
            child: Icon(Icons.circle, size: 8, color: Colors.black54),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 15, color: Colors.black87, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// V. Job Listing Shimmer
// --------------------------------------------------------------------------

class JobListingShimmer extends StatelessWidget {
  const JobListingShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Placeholder
                  Container(height: 18, width: double.infinity, color: Colors.white, margin: const EdgeInsets.only(bottom: 4)),
                  // Recruiter Placeholder
                  Container(height: 14, width: 150, color: Colors.white),
                  const Divider(height: 20, thickness: 1),
                  // Chips Placeholder
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(height: 28, width: 80, color: Colors.white),
                      Container(height: 28, width: 90, color: Colors.white),
                      Container(height: 28, width: 100, color: Colors.white),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Buttons Placeholder
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(height: 36, width: 80, color: Colors.white),
                      const SizedBox(width: 8),
                      Container(height: 36, width: 100, color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}