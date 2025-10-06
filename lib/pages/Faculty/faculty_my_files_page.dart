import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:grademate/widgets/bottom_nav_bar.dart';

class FacultyMyFilesPage extends StatefulWidget {
  const FacultyMyFilesPage({super.key});

  @override
  State<FacultyMyFilesPage> createState() => _FacultyMyFilesPageState();
}

class _FacultyMyFilesPageState extends State<FacultyMyFilesPage> {
  int _selectedIndex = 2; // Index for the 'My Notes' tab

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Add navigation logic for the bottom nav bar here
    // For example:
    if (index == 0) {
      context.go('/faculty_home');
    } else if (index == 1) {
      context.go('/faculty_courses');
    } else if (index == 2) {
      // This is the current page, so no navigation needed
    } else if (index == 3) {
      context.go('/faculty_profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Files', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.black),
            onPressed: () {
              // TODO: Implement 'add new file' functionality
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Search Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const TextField(
                decoration: InputDecoration(
                  icon: Icon(Icons.search, color: Colors.grey),
                  hintText: 'Search',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // File/Folder List
            _buildFolderTile(
              Icons.folder_outlined,
              'My Courses',
              '10 items',
            ),
            _buildFolderTile(
              Icons.folder_outlined,
              'Shared to Students',
              '7 items',
            ),
            _buildFolderTile(
              Icons.folder_outlined,
              'Syllabus',
              '3 items',
            ),
            _buildFolderTile(
              Icons.folder_outlined,
              'My Research',
              '2 items',
            ),
            _buildFolderTile(
              Icons.folder_outlined,
              'Drafts',
              '1 item',
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

  Widget _buildFolderTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue[800]),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
      trailing: const Icon(Icons.more_horiz),
      onTap: () {
        // TODO: Implement folder tap action
      },
    );
  }
}