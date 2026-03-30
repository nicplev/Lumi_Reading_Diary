'use client';

// Type exports for dashboard data (used by server components that pass props)
export interface ClientDashboardStats {
  totalStudents: number;
  totalTeachers: number;
  totalClasses: number;
  activeStudentsToday: number;
}

export interface ClientWeeklyEngagement {
  day: string;
  count: number;
}

export interface ClientRecentActivity {
  id: string;
  studentName: string;
  action: string;
  time: string;
}
