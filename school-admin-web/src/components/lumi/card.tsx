import { HTMLAttributes } from 'react';

interface CardProps extends HTMLAttributes<HTMLDivElement> {
  hover?: boolean;
  padding?: 'none' | 'sm' | 'md' | 'lg';
}

const paddingClasses = {
  none: '',
  sm: 'p-4',
  md: 'p-5',
  lg: 'p-6',
};

export function Card({ hover, padding = 'md', className = '', children, ...props }: CardProps) {
  return (
    <div
      className={`bg-surface rounded-[var(--radius-lg)] shadow-card ${hover ? 'hover:shadow-card-hover transition-shadow cursor-pointer' : ''} ${paddingClasses[padding]} ${className}`}
      {...props}
    >
      {children}
    </div>
  );
}
