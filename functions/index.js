const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// A. Igikorwa #1: Gusiba Posts Zisanzwe Zishaje (Uburyo bwa v1)
exports.deleteOldRegularPosts = functions.pubsub
  .schedule("every 1 hours")
  .onRun(async (context) => {
    console.log("Checking for old regular posts to delete...");
    const twentyFourHoursAgo = new Date();
    twentyFourHoursAgo.setHours(twentyFourHoursAgo.getHours() - 24);
    const oldPostsQuery = db
      .collection("posts")
      .where("isStar", "==", false)
      .where("timestamp", "<", admin.firestore.Timestamp.fromDate(twentyFourHoursAgo));
    const snapshot = await oldPostsQuery.get();
    if (snapshot.empty) {
      console.log("No old regular posts found to delete.");
      return null;
    }
    const batch = db.batch();
    snapshot.docs.forEach((doc) => {
      console.log(`Deleting post: ${doc.id}`);
      batch.delete(doc.ref);
    });
    await batch.commit();
    console.log(`Successfully deleted ${snapshot.size} old regular posts.`);
    return null;
  });

// B. Igikorwa #2: Guharura no Gutoranya "Stars of the Day" (Uburyo bwa v1)
exports.calculateAndAssignStars = functions.pubsub
  .schedule("every day 18:00")
  .timeZone("Africa/Bujumbura")
  .onRun(async (context) => {
    console.log("Starting to calculate and assign Stars of the Day...");
    const now = new Date();
    const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    const endOfDay = new Date(now);
    endOfDay.setHours(17, 59, 59, 999);
    const postsQuery = db
      .collection("posts")
      .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(twentyFourHoursAgo))
      .where("timestamp", "<=", admin.firestore.Timestamp.fromDate(endOfDay));
    const snapshot = await postsQuery.get();
    if (snapshot.empty) {
      console.log("No posts found in the last 24 hours.");
      return null;
    }
    const postsWithRatio = snapshot.docs.map((doc) => {
      const data = doc.data();
      const likes = data.likes || 0;
      const views = data.views || 1;
      const ratio = likes / views;
      return { id: doc.id, ...data, ratio: ratio };
    });
    postsWithRatio.sort((a, b) => b.ratio - a.ratio);
    const top5Stars = postsWithRatio.slice(0, 5);
    if (top5Stars.length === 0) {
      console.log("No posts qualified to be stars.");
      return null;
    }
    const batch = db.batch();
    const expiryDate = new Date(now.getTime() + 24 * 60 * 60 * 1000);
    const starExpiryTimestamp = admin.firestore.Timestamp.fromDate(expiryDate);
    top5Stars.forEach((post) => {
      console.log(`Promoting post ${post.id} to Star.`);
      const postRef = db.collection("posts").doc(post.id);
      batch.update(postRef, {
        isStar: true,
        starExpiryTimestamp: starExpiryTimestamp,
      });
    });
    await batch.commit();
    console.log(`Successfully assigned ${top5Stars.length} Stars of the Day.`);
    return null;
  });

// C. Igikorwa #3: Kumenyesha Abatsinze (Uburyo bwa v1)
exports.sendStarNotification = functions.firestore
  .document("posts/{postId}")
  .onUpdate(async (change, context) => {
    const dataBefore = change.before.data();
    const dataAfter = change.after.data();
    if (dataBefore.isStar === false && dataAfter.isStar === true) {
      const userId = dataAfter.userId;
      const postId = context.params.postId;
      if (!userId) {
        console.error(`Post ${postId} has no userId!`);
        return null;
      }
      console.log(`Sending notification to user ${userId} for post ${postId}.`);
      const notificationTitle = "Wakoze Neza, Wabaye Star Wacu ⭐!";
      const notificationBody = "Ijambo ryawe ryakoze kumitima y’abenshi. Post yawe yabaye muri zitanu nziza mumasaha 24 aheze! Igiye rero kumara ayandi masaha 24 mu kibanza categekanirijwe aba Stars ⭐ kugira n’abandi babone iciyumviro cawe kidasanzwe. TURAGUKEJE RERO STAR WACU ⭐! Jembe Talk yemerewe kwifashisha iyi post yawe mu kwamamaza ibikorwa vyayo. (TANGAZA STAR⭐)";
      await db.collection("notifications").add({
        userId: userId,
        title: notificationTitle,
        body: notificationBody,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
        relatedPostId: postId,
      });
      return null;
    }
    return null;
  });