import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class MyNotesPage extends StatefulWidget {
  const MyNotesPage({super.key});

  @override
  State<MyNotesPage> createState() => _MyNotesPageState();
}

class _MyNotesPageState extends State<MyNotesPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
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

  Future<void> _showNoteDialog({DocumentSnapshot? note}) async {
    final titleController = TextEditingController(text: note?['title']);
    final contentController = TextEditingController(text: note?['content']);

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note == null ? 'New Note' : 'Edit Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: contentController,
              decoration: const InputDecoration(labelText: 'Content'),
              maxLines: 5,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final title = titleController.text;
              final content = contentController.text;
              if (title.isNotEmpty && content.isNotEmpty) {
                if (note == null) {
                  _addNote(title, content);
                } else {
                  _updateNote(note.id, title, content);
                }
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  CollectionReference get _notesCollection => _firestore
      .collection('users')
      .doc(_auth.currentUser!.email)
      .collection('notes');

  void _addNote(String title, String content) {
    _notesCollection.add({
      'title': title,
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  void _updateNote(String docId, String title, String content) {
    _notesCollection.doc(docId).update({
      'title': title,
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  void _deleteNote(String docId) {
    _notesCollection.doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _navigateBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: _navigateBack,
          ),
          title: const Text('My Notes'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _notesCollection.orderBy('timestamp', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('No notes yet.'));
            }
            final notes = snapshot.data!.docs;
            return ListView.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                final timestamp = note['timestamp'] as Timestamp?;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(note['title']),
                    subtitle: Text(
                      note['content'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      timestamp != null
                          ? DateFormat('MMM d, yyyy').format(timestamp.toDate())
                          : '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    onTap: () => _showNoteDialog(note: note),
                     onLongPress: () => _deleteNote(note.id),
                  ),
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showNoteDialog(),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
