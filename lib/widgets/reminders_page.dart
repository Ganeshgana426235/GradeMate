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

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchUserRole();
    _initializeNotifications();
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
                              backgroundColor: Colors.deepPurple,
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
          title: const Text('Reminders & Alarms'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          centerTitle: true,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _remindersCollection.orderBy('reminderTime').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                  child: Text("Error loading reminders. Please log in again."));
            }
            // **FIX**: Updated UI for when no reminders are found.
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.alarm_off_outlined, size: 80, color: Colors.grey[400]),
                     const SizedBox(height: 24),
                    Text(
                      'No reminders yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                     Text(
                      'Tap the + button to add one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                    ),
                  ],
                ),
              );
            }
            final reminders = snapshot.data!.docs;
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reminders.length,
              itemBuilder: (context, index) {
                final reminder = reminders[index];
                final data = reminder.data() as Map<String, dynamic>;
                final reminderTime =
                    (data['reminderTime'] as Timestamp).toDate();
                final notificationId = data['notificationId'] ?? 0;

                return Card(
                  elevation: 0,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: InkWell(
                    onTap: () => _showReminderDialog(reminderDoc: reminder),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(50)
                            ),
                            child: Icon(Icons.alarm, color: Colors.deepPurple, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['title'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17)),
                                const SizedBox(height: 6),
                                if (data['description'] != null && data['description'].isNotEmpty)
                                  Text(data['description'],
                                      style:
                                          TextStyle(color: Colors.grey[600], fontSize: 15)),
                                const SizedBox(height: 8),
                                Text(
                                  DateFormat('EEE, MMM d \'at\' hh:mm a')
                                      .format(reminderTime),
                                  style: TextStyle(
                                      color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: Colors.grey[500]),
                            onPressed: () =>
                                _deleteReminder(reminder.id, notificationId),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showReminderDialog(),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, size: 32),
        ),
      ),
    );
  }
}

