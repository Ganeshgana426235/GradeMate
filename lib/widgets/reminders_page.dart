import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:math';

// Enum for filtering reminders
enum ReminderFilter { all, today, upcoming, completed }

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage>
    with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _userRole;
  
  // State for filtering and searching
  ReminderFilter _currentFilter = ReminderFilter.all;
  String _searchQuery = '';


  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchUserRole();
    _initializeNotifications();
    // Run the check when the page initializes
    _checkAndMarkPastReminders(); 
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _requestPermissions();
      // Run the check when the app resumes
      _checkAndMarkPastReminders(); 
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (e) {
      print("Error initializing timezone: $e");
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );

    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    var alarmStatus = await Permission.scheduleExactAlarm.status;
    if (alarmStatus.isDenied) {
      if (mounted) {
        await _showPermissionDialog(
          title: 'Alarm Permission Needed',
          content:
              'To ensure your reminders are perfectly on time, this app needs the "Alarms & Reminders" permission. Please tap "Open Settings" and enable it.',
        );
      }
    }
  }

  Future<void> _showPermissionDialog(
      {required String title, required String content}) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(content),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () async {
                await openAppSettings();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void onDidReceiveNotificationResponse(NotificationResponse response) async {
    if (response.payload != null && response.payload!.isNotEmpty) {
      await flutterTts.setPitch(1.0);
      await flutterTts.speak("Reminder: ${response.payload!}");
    }
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
  
  // NEW: Method to check all reminders and mark past ones as completed/missed
  Future<void> _checkAndMarkPastReminders() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    try {
      final snapshot = await _remindersCollection
          .where('isCompleted', isEqualTo: false)
          .where('recurrence', isEqualTo: 'Once')
          .get();

      final now = DateTime.now();
      final batch = _firestore.batch();
      
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final reminderTime = (data['reminderTime'] as Timestamp).toDate();
        
        // If the one-time reminder time is in the past, mark it as completed
        if (reminderTime.isBefore(now)) {
          print('Marking past reminder as completed: ${data['title']}');
          batch.update(doc.reference, {'isCompleted': true});
          
          // Also cancel the notification if it wasn't triggered/missed
          final notificationId = data['notificationId'] ?? 0;
          if (notificationId != 0) {
             flutterLocalNotificationsPlugin.cancel(notificationId);
          }
        }
      }

      await batch.commit();
    } catch (e) {
      print("Error checking and marking past reminders: $e");
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

  Future<void> _showReminderDialog({DocumentSnapshot? reminderDoc}) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    String recurrence = 'Once';

    if (reminderDoc != null) {
      final data = reminderDoc.data() as Map<String, dynamic>;
      titleController.text = data['title'];
      descriptionController.text = data['description'] ?? '';
      final reminderTime = (data['reminderTime'] as Timestamp).toDate();
      selectedDate = reminderTime;
      selectedTime = TimeOfDay.fromDateTime(reminderTime);
      recurrence = data['recurrence'] ?? 'Once';
    }

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
                        reminderDoc == null ? 'New Reminder' : 'Edit Reminder',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text("Reminder Title", style: TextStyle(color: Colors.grey[700])),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          hintText: "e.g., Doctor's appointment",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text("Description", style: TextStyle(color: Colors.grey[700])),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descriptionController,
                        decoration: InputDecoration(
                          hintText: "e.g., At the clinic on 5th Ave",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        maxLines: null,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            selectedDate == null ? 'No date chosen' : DateFormat('EEE, MMM d, yyyy').format(selectedDate!),
                            style: const TextStyle(fontSize: 16),
                          ),
                          TextButton(
                            onPressed: () async {
                              final now = DateTime.now();
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedDate ?? now,
                                // **FIX**: Allow picking today's date
                                firstDate: DateTime(now.year, now.month, now.day),
                                lastDate: DateTime(2101),
                              );
                              if (date != null) {
                                setDialogState(() => selectedDate = date);
                              }
                            },
                            child: const Text('Choose Date'),
                          ),
                        ],
                      ),
                      const Divider(),
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
                            child: const Text('Choose Time'),
                          ),
                        ],
                      ),
                       const Divider(),
                      const SizedBox(height: 8),
                       Text("Repeat", style: TextStyle(color: Colors.grey[700])),
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
                              backgroundColor: const Color(0xFF1B4370), // Use a deep blue color
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            onPressed: () async {
                               if (titleController.text.isNotEmpty &&
                        selectedDate != null &&
                        selectedTime != null) {
                      var status = await Permission.scheduleExactAlarm.status;
                      if (!status.isGranted) {
                        _requestPermissions();
                        return;
                      }

                      final reminderDateTime = DateTime(
                        selectedDate!.year,
                        selectedDate!.month,
                        selectedDate!.day,
                        selectedTime!.hour,
                        selectedTime!.minute,
                      );

                      // **FIX**: Only check for past time if it's a non-recurring reminder
                      if (recurrence == 'Once' && reminderDateTime.isBefore(DateTime.now())) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content:
                              Text('Cannot set a one-time reminder for a past time.'),
                          backgroundColor: Colors.orange,
                        ));
                        return;
                      }

                      if (reminderDoc == null) {
                        _addReminder(
                          titleController.text,
                          descriptionController.text,
                          reminderDateTime,
                          recurrence,
                        );
                      } else {
                        _updateReminder(
                          reminderDoc,
                          titleController.text,
                          descriptionController.text,
                          reminderDateTime,
                          recurrence,
                        );
                      }
                      Navigator.pop(context);
                    } else {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content:
                              Text('Please provide a title, date, and time.'),
                          backgroundColor: Colors.orange,
                        ));
                    }
                            },
                            child: const Text('Save', style: TextStyle(fontSize: 16)),
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

  void _addReminder(String title, String description, DateTime reminderTime,
      String recurrence) async {
    final notificationId = Random().nextInt(100000);
    try {
      await _remindersCollection.add({
        'title': title,
        'description': description,
        'reminderTime': Timestamp.fromDate(reminderTime),
        'recurrence': recurrence,
        'notificationId': notificationId,
        'isCompleted': false, // NEW: Added status field
        'createdAt': FieldValue.serverTimestamp(), // NEW: Added creation timestamp
      });

      _scheduleNotification(
          notificationId, title, description, reminderTime, recurrence);
    } catch (e) {
      print("Error adding reminder: $e");
    }
  }

  void _updateReminder(DocumentSnapshot doc, String title, String description,
      DateTime reminderTime, String recurrence) async {
    final data = doc.data() as Map<String, dynamic>;
    final int oldNotificationId =
        data['notificationId'] ?? Random().nextInt(100000);

    await flutterLocalNotificationsPlugin.cancel(oldNotificationId);

    final newNotificationId = Random().nextInt(100000);

    await doc.reference.update({
      'title': title,
      'description': description,
      'reminderTime': Timestamp.fromDate(reminderTime),
      'recurrence': recurrence,
      'notificationId': newNotificationId,
    });

    _scheduleNotification(
        newNotificationId, title, description, reminderTime, recurrence);
  }
  
  // NEW: Toggle completion status
  void _toggleCompletionStatus(DocumentSnapshot doc, bool currentStatus) async {
    try {
      await doc.reference.update({'isCompleted': !currentStatus});
      if (!currentStatus) {
        final data = doc.data() as Map<String, dynamic>;
        final int notificationId = data['notificationId'] ?? 0;
        flutterLocalNotificationsPlugin.cancel(notificationId);
      }
    } catch (e) {
      print("Error updating completion status: $e");
    }
  }


  Future<void> _scheduleNotification(int id, String title, String body,
      DateTime scheduledTime, String recurrence) async {
    var status = await Permission.scheduleExactAlarm.status;
    if (!status.isGranted) {
      print("Exact alarm permission not granted. Scheduling will fail.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Alarm permission is required for reminders.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        await _firestore
            .collection('users')
            .doc(user.email)
            .collection('notifications')
            .add({
          'title': title,
          'body': body,
          'timestamp': Timestamp.fromDate(scheduledTime),
          'type': 'reminder', 
          'isRead': false,
        });
      } catch (e) {
        print("Error saving notification to Firestore: $e");
      }
    }

    DateTimeComponents? dateTimeComponents;
    switch (recurrence) {
      case 'Daily':
        dateTimeComponents = DateTimeComponents.time;
        break;
      case 'Weekly':
        dateTimeComponents = DateTimeComponents.dayOfWeekAndTime;
        break;
      case 'Monthly':
        dateTimeComponents = DateTimeComponents.dayOfMonthAndTime;
        break;
      default:
        dateTimeComponents = null;
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'alarm_channel_id',
      'Alarms',
      channelDescription: 'Channel for reminder alarms',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('alarm'),
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
    );

    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    final tz.TZDateTime tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
    print('Scheduling notification for: $tzTime with ID: $id');

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        platformDetails,
        payload: body,
        matchDateTimeComponents: dateTimeComponents,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
      );
    } catch (e) {
      print("Error scheduling notification: $e");
    }
  }

  void _deleteReminder(String docId, int notificationId) {
    try {
      _remindersCollection.doc(docId).delete();
      flutterLocalNotificationsPlugin.cancel(notificationId);
    } catch (e) {
      print("Error deleting reminder: $e");
    }
  }

  // NEW: Filter logic to apply to the StreamBuilder data
  List<QueryDocumentSnapshot> _applyFilters(List<QueryDocumentSnapshot> reminders) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // 1. Apply Search
    List<QueryDocumentSnapshot> filteredList = reminders.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final title = data['title']?.toLowerCase() ?? '';
      final description = data['description']?.toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return title.contains(query) || description.contains(query);
    }).toList();

    // 2. Apply Filter Chips
    return filteredList.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final reminderTime = (data['reminderTime'] as Timestamp).toDate();
      final reminderDay = DateTime(reminderTime.year, reminderTime.month, reminderTime.day);
      final isCompleted = data['isCompleted'] ?? false;
      
      switch (_currentFilter) {
        case ReminderFilter.all:
          return true;
        case ReminderFilter.today:
          return reminderDay.isAtSameMomentAs(today) && !isCompleted;
        case ReminderFilter.upcoming:
          // Upcoming means the reminder is in the future and not completed
          return reminderTime.isAfter(now) && !isCompleted;
        case ReminderFilter.completed:
          return isCompleted;
      }
    }).toList();
  }
  
  // NEW: Widget builders for the filter chips
  Widget _buildFilterChip(ReminderFilter filter, String label, IconData icon) {
    bool isSelected = _currentFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        backgroundColor: isSelected ? const Color(0xFF1B4370) : Colors.grey[200],
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        side: isSelected ? BorderSide.none : BorderSide(color: Colors.grey.shade300),
        onPressed: () {
          setState(() {
            _currentFilter = filter;
          });
        },
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _navigateBack();
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: _navigateBack,
          ),
          title: const Text('Reminders'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.search, color: Colors.black),
              onPressed: () {}, // Search is handled by the search bar below
            ),
            IconButton(
              icon: const Icon(Icons.add, color: Colors.black),
              onPressed: () => _showReminderDialog(),
            ),
          ],
        ),
        body: Column(
          children: [
            // Top Section (Search and Filters)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 2,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Search Bar
                  TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search reminders',
                      prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(ReminderFilter.all, 'All', Icons.all_inclusive),
                        _buildFilterChip(ReminderFilter.today, 'Today', Icons.calendar_today_outlined),
                        _buildFilterChip(ReminderFilter.upcoming, 'Upcoming', Icons.schedule),
                        _buildFilterChip(ReminderFilter.completed, 'Completed', Icons.check_circle_outline),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Reminders List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _remindersCollection.orderBy('reminderTime', descending: false).snapshots(),
                builder: (context, snapshot) {
                  // **CRITICAL FIX**: Re-run the check when the data stream is available
                  if (snapshot.hasData && !snapshot.hasError && snapshot.data!.docs.isNotEmpty) {
                    // This ensures any newly missed reminders are marked before filtering/displaying
                    // Note: This check only runs on stream changes, the initState check handles initial load.
                    _checkAndMarkPastReminders(); 
                  }
                  
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(
                        child: Text("Error loading reminders. Please log in again."));
                  }
                  
                  final allReminders = snapshot.data?.docs ?? [];
                  final filteredReminders = _applyFilters(allReminders);
                  
                  if (filteredReminders.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.alarm_off_outlined, size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 24),
                          Text(
                            _searchQuery.isNotEmpty 
                            ? 'No results for "$_searchQuery".'
                            : 'No active reminders in this category.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          if (_searchQuery.isEmpty && _currentFilter == ReminderFilter.all)
                            Text(
                              'Tap the + button to add one.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                            ),
                        ],
                      ),
                    );
                  }
                  
                  // Scheduled Header
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Text(
                          'Scheduled (${filteredReminders.length})',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                      ...filteredReminders.map((reminder) {
                        final data = reminder.data() as Map<String, dynamic>;
                        final reminderTime = (data['reminderTime'] as Timestamp).toDate();
                        final notificationId = data['notificationId'] ?? 0;
                        final isCompleted = data['isCompleted'] ?? false;
                        final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

                        return _buildReminderCard(
                          context,
                          reminder,
                          data['title'],
                          data['description'] ?? '',
                          reminderTime,
                          data['recurrence'] ?? 'Once',
                          notificationId,
                          isCompleted,
                          createdAt,
                        );
                      }).toList(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // NEW: Refactored Reminder Card Widget
  Widget _buildReminderCard(
      BuildContext context,
      DocumentSnapshot doc,
      String title,
      String description,
      DateTime reminderTime,
      String recurrence,
      int notificationId,
      bool isCompleted,
      DateTime createdAt,
      ) {
    
    // Choose icon based on recurrence or presumed type (Assignment, Exam, etc.)
    IconData icon;
    if (title.toLowerCase().contains('assignment') || title.toLowerCase().contains('upload')) {
      icon = Icons.notifications_active_outlined;
    } else if (title.toLowerCase().contains('exam') || title.toLowerCase().contains('midterm')) {
      icon = Icons.calendar_today_outlined;
    } else if (title.toLowerCase().contains('payment') || title.toLowerCase().contains('fee')) {
      icon = Icons.monetization_on_outlined;
    } else if (recurrence != 'Once') {
       icon = Icons.access_time_filled;
    } else {
      icon = Icons.notifications_active_outlined;
    }
    
    Color iconColor = isCompleted ? Colors.green : const Color(0xFF1B4370);
    Color cardColor = isCompleted ? Colors.green.withOpacity(0.05) : Colors.white;

    // Determine recurrence display text
    String recurrenceText = recurrence == 'Once' ? 'One-time' : recurrence;

    return Card(
      elevation: 0,
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isCompleted ? Colors.green.shade200 : Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: isCompleted ? null : () => _showReminderDialog(reminderDoc: doc),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Icon, Title, Actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.grey[900],
                            decoration: isCompleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              description,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                                decoration: isCompleted ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Bottom Row: Date, Time, Recurrence/Created At
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Date and Time
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('d MMM yyyy').format(reminderTime),
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('h:mm a').format(reminderTime),
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  
                  // Recurrence / Created At
                  Row(
                    children: [
                       if (recurrence != 'Once' && !isCompleted)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B4370).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              recurrence,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF1B4370)),
                            ),
                          ),
                        ),
                      Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        'Created ${DateFormat('d MMM, h:mm a').format(createdAt)}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
              
              // Action Buttons (Only show if not completed)
              if (!isCompleted) ...[
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Mark Done Button
                    ActionChip(
                      avatar: const Icon(Icons.check, size: 18, color: Colors.white),
                      label: const Text('Mark done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      backgroundColor: Colors.green,
                      onPressed: () => _toggleCompletionStatus(doc, isCompleted),
                    ),
                    const Spacer(),
                    // Delete Button
                    TextButton.icon(
                      icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18),
                      label: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
                      onPressed: () => _deleteReminder(doc.id, notificationId),
                    ),
                  ],
                ),
              ],
               // Action Buttons (Only show if completed)
              if (isCompleted) ...[
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: Icon(Icons.undo, color: Colors.orange.shade400, size: 18),
                      label: Text('Undo Done', style: TextStyle(color: Colors.orange.shade400)),
                      onPressed: () => _toggleCompletionStatus(doc, isCompleted),
                    ),
                    const Spacer(),
                     // Delete Button
                    TextButton.icon(
                      icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18),
                      label: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
                      onPressed: () => _deleteReminder(doc.id, notificationId),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}