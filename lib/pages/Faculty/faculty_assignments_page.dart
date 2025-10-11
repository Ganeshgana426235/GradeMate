import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// A simple model for an assignment
class Assignment {
  final String title;
  final String course;
  bool isCompleted;

  Assignment({
    required this.title,
    required this.course,
    this.isCompleted = false,
  });
}

class FacultyAssignmentsPage extends StatefulWidget {
  const FacultyAssignmentsPage({super.key});

  @override
  State<FacultyAssignmentsPage> createState() => _FacultyAssignmentsPageState();
}

class _FacultyAssignmentsPageState extends State<FacultyAssignmentsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Sample static data for the UI
  final List<Assignment> _allAssignments = [
    Assignment(title: 'Homework 1', course: 'Math 101'),
    Assignment(title: 'Lab Report', course: 'Physics 201'),
    Assignment(title: 'Essay', course: 'History 301'),
    Assignment(title: 'Project', course: 'Computer Science 401'),
    Assignment(title: 'Quiz 1', course: 'Chemistry 101', isCompleted: true),
  ];

  List<Assignment> _dueAssignments = [];
  List<Assignment> _completedAssignments = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _filterAssignments();
  }

  void _filterAssignments() {
    setState(() {
      _dueAssignments =
          _allAssignments.where((a) => !a.isCompleted).toList();
      _completedAssignments =
          _allAssignments.where((a) => a.isCompleted).toList();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        context.go('/faculty_home');
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => context.go('/faculty_home'),
          ),
          title: const Text(
            'Assignments',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: Colors.black),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Adding a new assignment is not available yet.'),
                    backgroundColor: Colors.blueAccent,
                  ),
                );
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.blue.shade800,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.blue.shade800,
            tabs: const [
              Tab(text: 'Due'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildAssignmentList(_dueAssignments),
            _buildAssignmentList(_completedAssignments),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentList(List<Assignment> assignments) {
    if (assignments.isEmpty) {
      return Center(
        child: Text(
          'No assignments here.',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: assignments.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final assignment = assignments[index];
        return _buildAssignmentTile(assignment);
      },
    );
  }

  Widget _buildAssignmentTile(Assignment assignment) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assignment.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                assignment.course,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          if (!assignment.isCompleted)
            ElevatedButton(
              onPressed: () {
                // In a real app, this would update the assignment's status
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('"${assignment.title}" marked as completed.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[200],
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Mark as Completed'),
            )
          else
            Icon(Icons.check_circle, color: Colors.green.shade600),
        ],
      ),
    );
  }
}