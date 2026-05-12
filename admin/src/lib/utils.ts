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
