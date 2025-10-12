import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// A simple model to represent a student
class Student {
  final String name;
  final String rollNumber;
  final String branch;
  final String imageUrl;

  Student({
    required this.name,
    required this.rollNumber,
    required this.branch,
    required this.imageUrl,
  });
}

class ManageStudentsPage extends StatefulWidget {
  const ManageStudentsPage({super.key});

  @override
  State<ManageStudentsPage> createState() => _ManageStudentsPageState();
}

class _ManageStudentsPageState extends State<ManageStudentsPage> {
  final TextEditingController _searchController = TextEditingController();

  // Sample static data for the UI
  final List<Student> _allStudents = [
    Student(name: 'Ganesh Yerranagula', rollNumber: '21CE1A0501', branch: 'Computer Science', imageUrl: 'https://placehold.co/100x100/EFEFEF/333333?text=GY'),
    Student(name: 'Jane Doe', rollNumber: '21ME1A0305', branch: 'Mechanical', imageUrl: 'https://placehold.co/100x100/EFEFEF/333333?text=JD'),
    Student(name: 'Peter Jones', rollNumber: '21EC1A0410', branch: 'Electronics', imageUrl: 'https://placehold.co/100x100/EFEFEF/333333?text=PJ'),
    Student(name: 'Mary Jane', rollNumber: '21CE1A0515', branch: 'Computer Science', imageUrl: 'https://placehold.co/100x100/EFEFEF/333333?text=MJ'),
    Student(name: 'Chris Lee', rollNumber: '21CV1A0120', branch: 'Civil', imageUrl: 'https://placehold.co/100x100/EFEFEF/333333?text=CL'),
  ];

  List<Student> _filteredStudents = [];

  @override
  void initState() {
    super.initState();
    _filteredStudents = _allStudents;
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterStudents() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStudents = _allStudents.where((student) {
        final nameLower = student.name.toLowerCase();
        final rollLower = student.rollNumber.toLowerCase();
        return nameLower.contains(query) || rollLower.contains(query);
      }).toList();
    });
  }

  void _showRemoveConfirmation(Student student) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Remove Student?'),
          content: Text('Are you sure you want to remove ${student.name}?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Remove', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${student.name} removed. (UI Demo)'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => context.go('/faculty_home'),
          ),
          title: const Text('Manage Students', style: TextStyle(color: Colors.black)),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 1,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name or roll number...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _filteredStudents.isEmpty
                  ? Center(
                      child: Text(
                        'No students found.',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: _filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = _filteredStudents[index];
                        return _buildStudentTile(student);
                      },
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Add new student functionality is not yet available.'),
                backgroundColor: Colors.blueAccent,
              ),
            );
          },
          backgroundColor: Colors.blue.shade800,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildStudentTile(Student student) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: Colors.grey.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 28,
          backgroundImage: NetworkImage(student.imageUrl),
          backgroundColor: Colors.grey[200],
        ),
        title: Text(
          student.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${student.branch} - ${student.rollNumber}',
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: IconButton(
          icon: Icon(Icons.person_remove_outlined, color: Colors.red.shade400),
          onPressed: () => _showRemoveConfirmation(student),
        ),
      ),
    );
  }
}