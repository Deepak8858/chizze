"use client";
import { useEffect } from "react";
import { useRouter } from "next/navigation";

const USER_KEY = "chizze_admin_user";

export interface AdminUser {
  id: string;
  name: string;
  phone: string;
  role: string;
  permission?: string;
}

export function saveAuth(user: AdminUser) {
  if (typeof window === "undefined") return;
  localStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function clearAuth() {
  if (typeof window === "undefined") return;
  localStorage.removeItem(USER_KEY);
}

export function getUser(): AdminUser | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(USER_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

export function isAuthenticated(): boolean {
  const user = getUser();
  return !!user?.role;
}

/** Hook: redirect to /login if not authenticated */
export function useAuthGuard() {
  const router = useRouter();
  useEffect(() => {
    if (!isAuthenticated()) {
      router.replace("/login");
    }
  }, [router]);
  return { user: getUser() };
}

/** Hook: redirect to / if already authenticated (for login page) */
export function useRedirectIfAuthed() {
  const router = useRouter();
  useEffect(() => {
    if (isAuthenticated()) {
      router.replace("/");
    }
  }, [router]);
}
