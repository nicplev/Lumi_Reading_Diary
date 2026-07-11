interface LumiMascotProps {
  color?: string;
  cheek?: string;
  highlightOpacity?: number;
  className?: string;
  style?: React.CSSProperties;
}

export function LumiMascot({
  color = "#EC4544",
  cheek = "#F5A1C5",
  highlightOpacity = 0.16,
  className,
  style,
}: LumiMascotProps) {
  return (
    <svg
      viewBox="0 0 140 150"
      width="100%"
      height="100%"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      style={{ display: "block", overflow: "visible", ...style }}
    >
      <path
        d="M86 20 C88 33 95 41 104 52 C114 64 115 84 110 100 C104 122 88 134 68 134 C46 134 30 122 28 100 C25 83 31 67 45 53 C58 40 80 36 86 20 Z"
        fill={color}
      />
      <ellipse cx="52" cy="60" rx="12" ry="16" fill="#ffffff" opacity={highlightOpacity} />
      <ellipse cx="50" cy="103" rx="8.5" ry="5.5" fill={cheek} opacity="0.78" />
      <ellipse cx="90" cy="103" rx="8.5" ry="5.5" fill={cheek} opacity="0.78" />
      <ellipse cx="58" cy="89" rx="8.5" ry="11.5" fill="#ffffff" />
      <ellipse cx="82" cy="89" rx="8.5" ry="11.5" fill="#ffffff" />
      <circle cx="59" cy="91" r="4.3" fill="#211C16" />
      <circle cx="81" cy="91" r="4.3" fill="#211C16" />
      <path
        d="M63 107 Q70 115 78 107"
        stroke="#211C16"
        strokeWidth="3.4"
        strokeLinecap="round"
        fill="none"
      />
    </svg>
  );
}
