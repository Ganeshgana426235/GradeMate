// lib/widgets/my_notes_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:intl/intl.dart';

// --- Color Constants for UI/UX Consistency ---
const Color _kPrimaryColor = Color(0xFF6A67FE);
const Color _kLightPrimaryColor = Color(0xFFF0F5FF);
// ---

// ======================= MAIN NOTES PAGE ==========================
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
        debugPrint('Error fetching user role: $e');
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

  void _openNoteEditor({DocumentSnapshot? note}) {
    // Use pushNamed for better navigation if routes are defined, otherwise MaterialPageRoute
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NoteEditorPage(note: note),
      ),
    );
  }

  CollectionReference get _notesCollection => _firestore
      .collection('users')
      .doc(_auth.currentUser!.email)
      .collection('notes');

  Future<void> _confirmDeleteNote(String noteId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note?'),
        content:
            const Text('Are you sure you want to permanently delete this note?'),
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
        await _notesCollection.doc(noteId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note deleted.')),
          );
        }
      } catch (e) {
        debugPrint('Error deleting note: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete note.')),
          );
        }
      }
    }
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
          title: const Text('My Notes', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openNoteEditor(),
          backgroundColor: _kPrimaryColor, // UI FIX: Apply primary color
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)), // UI FIX: Rounded shape
          child: const Icon(Icons.add), // UI FIX: Simple + icon
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream:
              _notesCollection.orderBy('timestamp', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _kPrimaryColor)); // UI FIX: Apply primary color
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const NoNotesView();
            }
            final notes = snapshot.data!.docs;
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return _buildNoteCard(note);
              },
            );
          },
        ),
      ),
    );
  }

  // NEW WIDGET: Custom Note Card for improved UI/UX
  Widget _buildNoteCard(DocumentSnapshot note) {
    final data = note.data() as Map<String, dynamic>;
    String contentPreview = "Empty note";
    try {
      var decoded = jsonDecode(data['content']);
      final doc = quill.Document.fromJson(decoded);
      // Clean up preview: remove newlines and truncate
      contentPreview = doc.toPlainText().replaceAll('\n', ' ').trim();
      if (contentPreview.isEmpty) contentPreview = "Empty note";
    } catch (e) {
      contentPreview = (data['content'] ?? 'Empty note').toString().replaceAll('\n', ' ').trim();
    }

    String title = data['title']?.toString().trim() ?? 'Untitled Note';
    Timestamp? ts = data['timestamp'] as Timestamp?;
    String timeLabel = ts != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate())
        : 'No date';

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300), // UI FIX: Border for better definition
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openNoteEditor(note: note),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.article_outlined, color: _kPrimaryColor, size: 24), // UI FIX: Use primary color
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.grey[600]),
                    onPressed: () => _confirmDeleteNote(note.id),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const Divider(height: 16),
              Text(
                contentPreview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  timeLabel,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================= NOTE EDITOR PAGE ==========================
class NoteEditorPage extends StatefulWidget {
  final DocumentSnapshot? note;
  const NoteEditorPage({super.key, this.note});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final TextEditingController _titleController = TextEditingController();
  late quill.QuillController _quillController;
  final FocusNode _editorFocusNode = FocusNode();
  int _contentCharCount = 0;
  final int _maxContentChars = 5000;

  bool _isSaving = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadNoteContent();
    _updateCharCount();
    _quillController.addListener(_updateCharCount);
  }

  void _updateCharCount() {
    final length = _quillController.document.toPlainText().trim().length;
    if (mounted) {
      setState(() {
        _contentCharCount = length;
      });
    }
  }

  void _loadNoteContent() {
    if (widget.note != null) {
      final data = widget.note!.data() as Map<String, dynamic>;
      _titleController.text = data['title'] ?? '';

      try {
        final decoded = jsonDecode(data['content']);
        _quillController = quill.QuillController(
          document: quill.Document.fromJson(decoded),
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (e) {
        final plain = data['content'] ?? '';
        _quillController = quill.QuillController(
          document: quill.Document()..insert(0, plain),
          selection: const TextSelection.collapsed(offset: 0),
        );
      }
    } else {
      _quillController = quill.QuillController.basic();
    }
  }

  CollectionReference get _notesCollection => _firestore
      .collection('users')
      .doc(_auth.currentUser!.email)
      .collection('notes');

  // =========== MODIFIED: IMPROVED SAVE AND CLOSE LOGIC =============
  Future<void> _saveNote() async {
    if (_isSaving) return;

    final title = _titleController.text.trim();
    final plainTextContent = _quillController.document.toPlainText().trim();
    
    // Perform validation before attempting to save
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a title.')));
      return; 
    }
    if (plainTextContent.length > _maxContentChars) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Note cannot exceed $_maxContentChars characters.')));
      return; 
    }

    setState(() {
      _isSaving = true;
    });

    // Store the navigator before the async operation
    final navigator = Navigator.of(context);

    try {
      final contentJson =
          jsonEncode(_quillController.document.toDelta().toJson());

      final noteData = {
        'title': title,
        'content': contentJson,
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (widget.note == null) {
        await _notesCollection.add(noteData);
      } else {
        await _notesCollection.doc(widget.note!.id).update(noteData);
      }

      // On success, pop the screen
      if (mounted) navigator.pop();
    } catch (e) {
      debugPrint('Error saving note: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
  // 1. Hide the current snackbar (if one is showing)
  .hideCurrentSnackBar();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to save note.')));
        // On failure, re-enable the save button
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _confirmDeleteNote() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note?'),
        content:
            const Text('Are you sure you want to permanently delete this note?'),
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
        if (widget.note != null) {
          await _notesCollection.doc(widget.note!.id).delete();
        }
        if (mounted) Navigator.pop(context);
      } catch (e) {
        debugPrint('Error deleting note: $e');
      }
    }
  }

  @override
  void dispose() {
    _quillController.removeListener(_updateCharCount);
    _titleController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // UI FIX: Use white background
      appBar: AppBar(
        backgroundColor: Colors.white, // UI FIX: Use white app bar
        elevation: 1, // UI FIX: Slight elevation for separation
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.note == null ? 'New Note' : 'Edit Note',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (widget.note != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _confirmDeleteNote,
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // UI FIX: Align content left
                  children: [
                    // Title Field
                    TextField(
                      controller: _titleController,
                      maxLength: 100,
                      decoration: InputDecoration(
                        hintText: 'Title',
                        border: InputBorder.none,
                        filled: true,
                        fillColor: Colors.grey.shade50, // UI FIX: Light background fill
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kPrimaryColor, width: 2), // UI FIX: Primary color focus border
                        ),
                      ),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    
                    // Quill Editor Container
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300)),
                      child: Column(
                        children: [
                          // Toolbar
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100, // UI FIX: Light toolbar background
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
                              )
                            ),
                            child: quill.QuillSimpleToolbar(
                              controller: _quillController,
                              config: const quill.QuillSimpleToolbarConfig(
                                showBoldButton: true,
                                showItalicButton: true,
                                showUnderLineButton: true,
                                showColorButton: true,
                                showListBullets: true,
                                showListNumbers: true,
                                showQuote: true,
                                showClearFormat: true,
                                showUndo: true,
                                showRedo: true,
                              ),
                            ),
                          ),
                          const Divider(height: 1, thickness: 1),
                          
                          // Editor Body
                          SizedBox(
                            height: 300,
                            child: quill.QuillEditor.basic(
                              controller: _quillController,
                              focusNode: _editorFocusNode,
                              config: const quill.QuillEditorConfig(
                                placeholder: 'Write your note here...',
                                padding: EdgeInsets.all(16),
                              ),
                            ),
                          ),
                          
                          // Character Count
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 16.0, bottom: 8.0, top: 4.0),
                              child: Text(
                                '$_contentCharCount / $_maxContentChars',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _contentCharCount > _maxContentChars
                                      ? Colors.red
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Save/Cancel Buttons
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 5, offset: const Offset(0, -2))]
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: _kPrimaryColor), // UI FIX: Primary color border
                      foregroundColor: _kPrimaryColor, // UI FIX: Primary color text
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimaryColor, // UI FIX: Primary color fill
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _isSaving ? null : _saveNote,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.0,
                            ),
                          )
                        : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ======================= NO NOTES VIEW ==========================
class NoNotesView extends StatefulWidget {
  const NoNotesView({super.key});

  @override
  State<NoNotesView> createState() => _NoNotesViewState();
}

class _NoNotesViewState extends State<NoNotesView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: const Duration(seconds: 2), vsync: this)
          ..repeat(reverse: true);
    _animation = Tween<double>(begin: -5, end: 5)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) =>
              Transform.translate(offset: Offset(0, _animation.value), child: child),
          child:
              Icon(Icons.note_alt_outlined, size: 100, color: _kPrimaryColor.withOpacity(0.3)), // UI FIX: Use primary color opacity
        ),
        const SizedBox(height: 24),
        Text('No notes yet',
            style: TextStyle(fontSize: 22, color: Colors.grey[800], fontWeight: FontWeight.w600)), // UI FIX: Darker text
        const SizedBox(height: 8),
        Text('Tap the + button to add your first note.',
            style: TextStyle(fontSize: 16, color: Colors.grey[600])), // UI FIX: Better contrast text
      ]),
    );
  }
}