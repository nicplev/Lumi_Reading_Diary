interface SkeletonProps {
  className?: string;
}

export function Skeleton({ className = '' }: SkeletonProps) {
  return (
    <div className={`animate-pulse bg-divider/60 rounded-[var(--radius-md)] ${className}`} />
  );
}

export function StatCardSkeleton() {
  return (
    <div className="bg-surface rounded-[var(--radius-lg)] shadow-card p-5">
      <Skeleton className="h-4 w-24 mb-3" />
      <Skeleton className="h-8 w-16 mb-2" />
      <Skeleton className="h-3 w-20" />
    </div>
  );
}

export function CardSkeleton() {
  return (
    <div className="bg-surface rounded-[var(--radius-lg)] shadow-card p-5">
      <Skeleton className="h-5 w-32 mb-3" />
      <Skeleton className="h-4 w-48 mb-2" />
      <Skeleton className="h-4 w-40" />
    </div>
  );
}
