# Lumi Reading Diary

A comprehensive reading diary app for schools, teachers, parents, and students. Built with Flutter and Firebase.

## 🎯 Features Overview

### For Parents
- **Today Card**: One-tap reading log with customizable minutes
- **Child Management**: Support for multiple children
- **Reading History**: Track progress with weekly/monthly/all-time views
- **Visual Charts**: See reading trends and patterns
- **Streak Tracking**: Motivate consistent reading habits
- **Offline Support**: Log reading even without internet
- **Push Notifications**: Daily reminders at preferred time

### For Teachers
- **Class Dashboard**: Real-time overview of student progress
- **Smart Allocation**: Assign reading by level, specific books, or free choice
- **Student Monitoring**: Track individual and class-wide engagement
- **Quick Actions**: Send nudges to families, export reports
- **Visual Analytics**: Charts showing weekly trends and completion rates
- **CSV Export**: Generate reports for records

### For School Administrators
- **School-wide Dashboard**: Monitor overall engagement
- **User Management**: Control teacher and parent access
- **Policy Settings**: Configure reading levels and requirements
- **Data Analytics**: Track adoption and usage patterns
- **Subscription Management**: Handle billing and plans

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (>=3.0.0)
- Firebase account
- VS Code or Android Studio
- iOS/Android development setup

### Installation

1. **Clone the repository**
```bash
cd lumi_reading_tracker
```

2. **Install dependencies**
```bash
flutter pub get
```

3. **Firebase Setup**
Follow the detailed guide in `FIREBASE_SETUP.md`:
```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
flutterfire configure
```

4. **Run the app**
```bash
flutter run
```

## 📱 App Architecture

### Technology Stack
- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Firestore, Auth, Storage)
- **State Management**: Riverpod + Provider
- **Local Storage**: Hive
- **Charts**: fl_chart
- **Animations**: Lottie, flutter_animate
- **Navigation**: go_router

### Project Structure
```
lib/
├── core/
│   ├── theme/        # App colors, themes, typography
│   ├── widgets/      # Lumi mascot and shared widgets
│   └── utils/        # Utilities and helpers
├── data/
│   ├── models/       # Data models (User, Student, School, etc.)
│   └── repositories/ # Data access layer
├── services/         # Firebase, offline sync, notifications
├── screens/
│   ├── auth/         # Login, register, splash screens
│   ├── parent/       # Parent app screens
│   ├── teacher/      # Teacher dashboard and tools
│   └── admin/        # School admin portal
└── main.dart         # App entry point
```

## 🌟 Key Features

### Lumi Mascot System
- Animated character with multiple moods
- Provides encouragement and feedback
- Celebrates achievements
- Guides users through the app

### Flexible Reading System
- Adaptable to any school's reading level system (A-Z, PM Benchmark, Lexile, Custom)
- Support for specific book assignments or free choice
- Configurable minute targets
- Weekly/daily/fortnightly allocation options

### Offline-First Design
- Works without internet connection
- Automatic sync when reconnected
- Local data caching with Hive
- Conflict resolution for multi-device use

### Multi-Role Support
- Parent role: Log reading, track progress
- Teacher role: Manage classes, create allocations
- Admin role: School-wide management

## 📊 Data Models

### Core Entities
- **User**: Authentication and role management
- **Student**: Child profiles with reading stats
- **School**: Institution settings and policies
- **Class**: Groups of students with teachers
- **Allocation**: Reading assignments and requirements
- **ReadingLog**: Daily reading records
- **StudentStats**: Aggregated reading statistics

## 🔐 Security

### Firebase Security Rules
- Role-based access control (RBAC)
- School-scoped data isolation
- Parent-child relationship validation
- Teacher-class authorization

### Data Privacy
- Minimal data collection
- Consent management
- GDPR compliance ready
- Audit logging for sensitive actions

## 🎨 UI/UX Features

### Design System
- Material Design 3
- Custom color palette per role
- Consistent spacing and typography
- Responsive layouts

### Animations
- Flutter Animate for smooth transitions
- Lumi mascot animations
- Celebration effects
- Loading states

### Accessibility
- Clear contrast ratios
- Large touch targets
- Screen reader support
- Scalable text

## 📈 Analytics & Reporting

### For Teachers
- Class completion rates
- Individual student progress
- Weekly/monthly trends
- CSV export functionality

### For Parents
- Reading streaks
- Time tracking
- Book completion
- Visual progress charts

### For Administrators
- School-wide engagement
- Teacher activity
- Parent adoption rates
- Usage statistics

## 🔔 Notifications

### Types
- Daily reading reminders
- Achievement celebrations
- Teacher messages
- System announcements

### Configuration
- Customizable reminder times
- Quiet hours support
- School term awareness
- Per-child settings

## 🚧 Development Status

### ✅ Completed
- Core app structure
- Authentication system
- Parent experience (home, logging, history, profile)
- Teacher dashboard and allocation
- Admin dashboard
- Data models
- Offline sync service
- Theme system with Lumi mascot

### 🔄 In Progress
- Firebase integration
- Push notifications
- Data repositories

### 📋 Planned
- Cloud Functions for aggregation
- Advanced reporting
- School onboarding flow
- Multi-language support
- Parent-teacher messaging
- Achievement badges
- Reading recommendations

## 🤝 Contributing

This is a private project, but feedback and suggestions are welcome.

## 📄 License

Proprietary - All rights reserved

## 🆘 Support

For issues or questions:
- Technical: Check Firebase console logs
- App issues: Review error messages
- Setup help: See FIREBASE_SETUP.md

## 🎯 Next Steps

1. **Complete Firebase Setup**
   - Run `flutterfire configure`
   - Enable Authentication, Firestore, Storage
   - Configure security rules

2. **Test Core Features**
   - Create test accounts for each role
   - Verify reading log functionality
   - Test offline mode

3. **Customize for Your School**
   - Configure reading level system
   - Set up classes and students
   - Define allocation templates

4. **Deploy**
   - Build for iOS: `flutter build ios`
   - Build for Android: `flutter build apk`
   - Upload to app stores

## 📱 Screenshots

(Add screenshots of the app in action)

## 🏆 Acknowledgments

- Flutter team for the amazing framework
- Firebase for backend services
- The education community for inspiration

---

**Lumi Reading Tracker** - Making reading fun and trackable for every child 📚✨