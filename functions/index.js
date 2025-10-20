const functions = require('firebase-functions/v2'); // Use v2 for latest syntax and runtime
const { onDocumentCreated } = require('firebase-functions/v2/firestore'); // Specific import for document trigger
const admin = require('firebase-admin');

// Ensure Firebase Admin SDK is initialized (required for Firestore and FCM)
admin.initializeApp();

const db = admin.firestore();
const fcm = admin.messaging();

/**
 * Helper function to query for and return a list of FCM tokens 
 * for students matching the course criteria.
 * * NOTE: The student data is now expected to be in 
 * 'colleges/{collegeId}/branches/{branchId}/regulations/{regId}/students/{studentId}'
 * and NOT the top-level 'users' collection.
 */
async function getStudentTokens(collegeId, branch, regulation, year) {
    const tokens = [];
    
    // Construct the base query path to the collection that holds student data
    const studentsRef = db.collection('colleges')
        .doc(collegeId)
        .collection('branches').doc(branch)
        .collection('regulations').doc(regulation)
        .collection('Students'); 
        // Assuming 'students' collection is indexed by year/semester/etc. or contains 
        // the year information within the document.

    // If 'year' filtering is needed, it must be applied here. 
    // Since the path structure you described (college/branch/reg/student) doesn't include 
    // 'year', we assume the student documents within this final 'students' collection 
    // are relevant to this course context.

    try {
        const snapshot = await studentsRef.get();
        
        snapshot.forEach(doc => {
            const student = doc.data();
            // Assuming the FCM token field is named 'fcmToken' and the year is 'year'
            if (student.fcmToken && student.year === year) { 
                tokens.push(student.fcmToken);
            }
        });

    } catch (error) {
        functions.logger.error("Error querying student tokens:", error);
    }
    
    return tokens;
}

/**
 * Cloud Function triggered when a new document is created in the 
 * notifications_queue subcollection of any college.
 * This function routes the request based on the 'type' field (file/link or reminder).
 */
exports.processNotificationQueue = onDocumentCreated(
  'colleges/{collegeId}/notifications_queue/{notificationId}',
  async (event) => {
    
    if (!event.data) {
      functions.logger.warn('No data found in event, returning.');
      return null;
    }
    
    const triggerData = event.data.data();
    const { collegeId, notificationId } = event.params;
    const type = triggerData.type || 'file'; // Default to file/link type
    
    functions.logger.info(`Processing notification type: ${type} for College ID: ${collegeId}, Doc ID: ${notificationId}`);

    try {
        if (type === 'REMINDER') {
            await sendReminderNotification(triggerData);
        } else {
            // Handles 'file' or 'link' types (New Material)
            await sendNewMaterialNotification(triggerData);
        }
    } catch (error) {
        functions.logger.error(`Error processing ${type} notification:`, error);
        // Do not return early, proceed to cleanup
    }
    
    // Clean up the trigger document regardless of success/failure of sending FCM
    await event.data.ref.delete();
    
    return null;
  });

/**
 * Handles notifications for new material (file or link).
 */
async function sendNewMaterialNotification(triggerData) {
    const { collegeId, branch, regulation, year, subject, title: fileName, uploaderName } = triggerData;
    
    if (!branch || !regulation || !year || !collegeId) {
        functions.logger.error(`FATAL ERROR (New Material): Missing critical path data. CollegeId: ${collegeId}, Branch: ${branch}, Regulation: ${regulation}, Year: ${year}.`);
        return null;
    }

    const studentTokens = await getStudentTokens(collegeId, branch, regulation, year);
    
    if (studentTokens.length === 0) {
        functions.logger.warn(`No student tokens found for criteria: ${branch}/${regulation}/${year}. Skipping FCM.`);
        return null;
    }
    
    const payload = {
        notification: {
            title: `📚 New ${subject} Material Added`,
            body: `A new study file/link (${fileName}) has been uploaded by ${uploaderName} for your course.`,
        },
        android: { notification: { channelId: 'new_file_channel', sound: 'default' }, priority: 'high' },
        data: {
            type: 'NEW_COURSE_FILE',
            collegeId, branch, regulation, year, subject,
        },
    };

    functions.logger.info(`Found ${studentTokens.length} students. Sending NEW MATERIAL FCM message.`);
    await fcm.sendEachForMulticast({ tokens: studentTokens, ...payload });
    functions.logger.info('New Material FCM Send complete.');
}


/**
 * Handles notifications for a specific faculty-sent reminder.
 */
async function sendReminderNotification(triggerData) {
    const { collegeId, branch, regulation, year, subject, title, body, uploaderName } = triggerData;

    if (!branch || !regulation || !year || !collegeId) {
        functions.logger.error(`FATAL ERROR (Reminder): Missing critical path data. CollegeId: ${collegeId}, Branch: ${branch}, Regulation: ${regulation}, Year: ${year}.`);
        return null;
    }

    const studentTokens = await getStudentTokens(collegeId, branch, regulation, year);
    
    if (studentTokens.length === 0) {
        functions.logger.warn(`No student tokens found for REMINDER criteria: ${branch}/${regulation}/${year}. Skipping FCM.`);
        return null;
    }

    // CRITICAL: The requested message format
    const payload = {
        notification: {
            // title: "A new reminder from faculty name"
            title: `⏰ A new reminder from ${uploaderName}`, 
            // body: reminder body
            body: body || title || `Reminder set for ${subject}.`,
        },
        android: { notification: { channelId: 'reminder_channel', sound: 'default' }, priority: 'high' },
        data: {
            type: 'FACULTY_REMINDER',
            collegeId, branch, regulation, year, subject,
        },
    };

    functions.logger.info(`Found ${studentTokens.length} students. Sending REMINDER FCM message.`);
    await fcm.sendEachForMulticast({ tokens: studentTokens, ...payload });
    functions.logger.info('Reminder FCM Send complete.');
}
