import { BadRequestException } from "@nestjs/common";

/// Single normalization rule for customer phone numbers, shared by OTP login
/// and profile updates so the same typed number always compares equal.
export function normalizePhone(phone: string): string {
  const normalized = phone.replace(/[^\d+]/g, "");
  if (normalized.length < 8) {
    throw new BadRequestException("Phone number is invalid.");
  }
  return normalized;
}
