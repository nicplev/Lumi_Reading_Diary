'use client';

import { useQuery } from '@tanstack/react-query';

export interface SerializedAchievement {
  id: string;
  name: string;
  description: string;
  icon: string;
  category: string;
  rarity: string;
  earnedAt: string | null;
}

export function useStudentAchievements(studentId: string) {
  return useQuery<SerializedAchievement[]>({
    queryKey: ['achievements', studentId],
    queryFn: async () => {
      const res = await fetch(`/api/students/${studentId}/achievements`);
      if (!res.ok) throw new Error('Failed to load achievements');
      return res.json();
    },
    enabled: !!studentId,
    staleTime: 60 * 1000,
  });
}
