import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

export function formatDate(input: string | Date | undefined | null): string {
  if (!input) return "\u2014"
  const d = typeof input === "string" ? new Date(input) : input
  if (isNaN(d.getTime())) return "\u2014"
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`
}

export function formatDateTime(input: string | Date | undefined | null): string {
  if (!input) return "\u2014"
  const d = typeof input === "string" ? new Date(input) : input
  if (isNaN(d.getTime())) return "\u2014"
  const h = d.getHours().toString().padStart(2, "0")
  const min = d.getMinutes().toString().padStart(2, "0")
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}, ${h}:${min}`
}

const BYTE_UNITS = ["B", "KB", "MB", "GB", "TB"]

export function formatBytes(input: number | undefined | null): string {
  const n = Math.max(0, input ?? 0)
  if (n < 1024) return `${n} B`
  let value = n
  let unit = 0
  while (value >= 1024 && unit < BYTE_UNITS.length - 1) {
    value /= 1024
    unit++
  }
  return `${value >= 100 ? Math.round(value) : value.toFixed(1)} ${BYTE_UNITS[unit]}`
}

export function formatRelative(input: string | Date | undefined | null): string {
  if (!input) return "\u2014"
  const d = typeof input === "string" ? new Date(input) : input
  if (isNaN(d.getTime())) return "\u2014"
  const diffMs = Date.now() - d.getTime()
  if (diffMs < 0) return formatDateTime(d)
  const mins = Math.floor(diffMs / 60_000)
  if (mins < 1) return "just now"
  if (mins < 60) return `${mins}m ago`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 14) return `${days}d ago`
  return formatDate(d)
}
