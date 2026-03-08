import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Stub data provider for teacher features that lack backend implementation.
/// Used for Library screen, Student Detail assigned books, and parent comments.
class TeacherStubData {
  /// Returns stub books organized by decodable tier.
  /// Each book has: title, tier level, type ('decodable'/'library'), coverGradient.
  static List<Map<String, dynamic>> getStubBooks() {
    return [
      // Level 1 - CVC Words
      _book('Sam the Cat', 1, 'decodable', [AppColors.levelCVC, const Color(0xFFEF5350)]),
      _book('Hop on Top', 1, 'decodable', [AppColors.levelCVC, const Color(0xFFE57373)]),
      _book('Big Pig Dig', 1, 'decodable', [AppColors.levelCVC, const Color(0xFFF44336)]),
      _book('Run, Pup, Run!', 1, 'decodable', [AppColors.levelCVC, const Color(0xFFEF9A9A)]),
      _book('The Red Hen', 1, 'decodable', [AppColors.levelCVC, const Color(0xFFE53935)]),
      // Level 2 - Digraphs
      _book('Ship Trip', 2, 'decodable', [AppColors.levelDigraphs, const Color(0xFFFF9800)]),
      _book('Chip and Chad', 2, 'decodable', [AppColors.levelDigraphs, const Color(0xFFFFB74D)]),
      _book('Fish Wish', 2, 'decodable', [AppColors.levelDigraphs, const Color(0xFFFFA726)]),
      _book('The Thin Path', 2, 'decodable', [AppColors.levelDigraphs, const Color(0xFFFFCC80)]),
      // Level 3 - Blends
      _book('Frog on a Log', 3, 'decodable', [AppColors.levelBlends, const Color(0xFFFDD835)]),
      _book('Drum Fun', 3, 'decodable', [AppColors.levelBlends, const Color(0xFFFFEE58)]),
      _book('Clap and Snap', 3, 'decodable', [AppColors.levelBlends, const Color(0xFFFFF176)]),
      _book('Swim to Win', 3, 'decodable', [AppColors.levelBlends, const Color(0xFFFFF59D)]),
      // Level 4 - CVCE
      _book('Cake by the Lake', 4, 'decodable', [AppColors.levelCVCE, const Color(0xFF66BB6A)]),
      _book('Bike Ride', 4, 'decodable', [AppColors.levelCVCE, const Color(0xFF81C784)]),
      _book('Home Alone Gnome', 4, 'decodable', [AppColors.levelCVCE, const Color(0xFF4CAF50)]),
      // Level 5 - Vowel Teams
      _book('Rain on the Train', 5, 'decodable', [AppColors.levelVowelTeams, const Color(0xFF42A5F5)]),
      _book('Boat Float', 5, 'decodable', [AppColors.levelVowelTeams, const Color(0xFF64B5F6)]),
      _book('Team Dream', 5, 'decodable', [AppColors.levelVowelTeams, const Color(0xFF1E88E5)]),
      // Level 6 - R-Controlled
      _book('Car Star', 6, 'decodable', [AppColors.levelRControlled, const Color(0xFFAB47BC)]),
      _book('Her Bird', 6, 'decodable', [AppColors.levelRControlled, const Color(0xFFCE93D8)]),
      _book('The Torn Horn', 6, 'decodable', [AppColors.levelRControlled, const Color(0xFF9C27B0)]),
      // Library books
      _book('Where the Wild Things Are', 0, 'library', [const Color(0xFF81C784), const Color(0xFF388E3C)]),
      _book('The Very Hungry Caterpillar', 0, 'library', [const Color(0xFF81C784), const Color(0xFF66BB6A)]),
      _book('Goodnight Moon', 0, 'library', [const Color(0xFFA5D6A7), const Color(0xFF4CAF50)]),
      _book('Brown Bear, Brown Bear', 0, 'library', [const Color(0xFFC8E6C9), const Color(0xFF81C784)]),
    ];
  }

  static Map<String, dynamic> _book(
    String title,
    int tierLevel,
    String type,
    List<Color> coverGradient,
  ) {
    return {
      'title': title,
      'tierLevel': tierLevel,
      'type': type,
      'coverGradient': coverGradient,
    };
  }

  /// Returns stub assigned books for a student.
  static List<Map<String, dynamic>> getStubAssignedBooks(String studentId) {
    return [
      {
        'title': 'Sam the Cat',
        'subtitle': 'Level 1 - CVC',
        'type': 'decodable',
        'status': 'completed',
        'coverGradient': [AppColors.levelCVC, const Color(0xFFEF5350)],
      },
      {
        'title': 'The Big Fish',
        'subtitle': 'Level 2 - Digraphs',
        'type': 'decodable',
        'status': 'in_progress',
        'coverGradient': [AppColors.levelDigraphs, const Color(0xFFFF9800)],
      },
      {
        'title': 'Where the Wild Things Are',
        'subtitle': 'Maurice Sendak',
        'type': 'library',
        'status': 'new',
        'coverGradient': [const Color(0xFF81C784), const Color(0xFF388E3C)],
      },
    ];
  }

  /// Returns a stub parent comment for a student.
  static Map<String, dynamic> getStubLatestComment(String studentId) {
    return {
      'comment':
          'Read beautifully tonight! Sounded out all the tricky words and was very proud of finishing the book.',
      'author': 'Parent',
      'date': 'Yesterday',
    };
  }

  /// Returns stub dashboard stats when no real data is available.
  static Map<String, dynamic> getStubDashboardStats() {
    return {
      'totalStudents': 24,
      'readLastNight': 18,
      'onStreak': 12,
      'totalBooks': 47,
      'weeklyEngagement': [20, 22, 18, 21, 19, 15, 0],
    };
  }
}
