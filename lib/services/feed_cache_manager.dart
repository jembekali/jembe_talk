import 'dart:developer';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class FeedCacheManager {
  // 1. Gusiga posts 5 gusa muri Database (Pruning)
  static Future<void> pruneCacheToFive() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      // Siba posts zose zitari mu mibare 5 ya mbere nshya
      await db.execute('''
        DELETE FROM ${DatabaseHelper.tableStealthPosts} 
        WHERE ${DatabaseHelper.colPostId} NOT IN (
          SELECT ${DatabaseHelper.colPostId} FROM ${DatabaseHelper.tableStealthPosts} 
          ORDER BY ${DatabaseHelper.colTimestamp} DESC LIMIT 5
        )
      ''');
      log("FeedCacheManager: Zasize 5 gusa, izindi zasibwe neza.");
    } catch (e) {
      log("FeedCacheManager Error: $e");
    }
  }

  // 2. Gusiba byose umukoresha asohotse (Full Cleanup)
  static Future<void> clearAllExceptLastFive() async {
    // Hamagara ya function yo hejuru
    await pruneCacheToFive();
    
    // Hano ushobora no kongeramo uburyo bwo gusiba Video Cache 
    // niba plugin ukoresha ibyemera (Optional)
    log("FeedCacheManager: Session isuku yarangiye.");
  }
}