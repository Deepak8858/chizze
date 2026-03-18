"use client";
import { useEffect, useRef, useState, useCallback } from "react";
import type { LiveStats, LiveRider, LiveOrder } from "@/types";

const BASE_URL =
  typeof window !== "undefined"
    ? (process.env.NEXT_PUBLIC_API_URL ?? "https://api.devdeepak.me/api/v1")
    : "";

function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem("chizze_admin_token");
}

/** Unwrap backend { success, data } envelope */
function unwrap<T>(body: unknown): T {
  if (body && typeof body === "object" && "success" in body && "data" in body) {
    return (body as Record<string, unknown>).data as T;
  }
  return body as T;
}

/** Generic polling hook — replaces the old SSE EventSource hook */
export function usePolling<T>(
  path: string,
  onData: (data: T) => void,
  intervalMs = 5000,
  enabled = true
) {
  const [connected, setConnected] = useState(false);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const onDataRef = useRef(onData);
  onDataRef.current = onData;

  const fetchData = useCallback(async () => {
    if (!enabled) return;
    const token = getToken();
    if (!token) return;
    try {
      const res = await fetch(`${BASE_URL}${path}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) { setConnected(false); return; }
      const body = await res.json();
      onDataRef.current(unwrap<T>(body));
      setConnected(true);
    } catch {
      setConnected(false);
    }
  }, [path, enabled]);

  useEffect(() => {
    if (!enabled) return;
    fetchData();
    intervalRef.current = setInterval(fetchData, intervalMs);
    return () => { if (intervalRef.current) clearInterval(intervalRef.current); };
  }, [fetchData, intervalMs, enabled]);

  return { connected };
}

// ─── Live stats hook ──────────────────────────────────────────────────────────
export function useLiveStats(enabled = true) {
  const [stats, setStats] = useState<LiveStats>({
    active_orders: 0,
    online_riders: 0,
    connected_users: 0,
    orders_per_minute: 0,
    connected_by_role: { customer: 0, restaurant_owner: 0, delivery_partner: 0 },
  });

  const { connected } = usePolling<LiveStats>(
    "/admin/live/stats",
    (data) => setStats((prev) => ({ ...prev, ...data })),
    10_000,
    enabled
  );

  return { stats, connected };
}

// ─── Live riders hook ─────────────────────────────────────────────────────────
export function useRiderLocations(enabled = true) {
  const [riders, setRiders] = useState<LiveRider[]>([]);

  const { connected } = usePolling<LiveRider[]>(
    "/admin/live/riders",
    (data) => setRiders(Array.isArray(data) ? data : []),
    5_000,
    enabled
  );

  return { riders, connected };
}

// ─── Live orders hook ─────────────────────────────────────────────────────────
export function useLiveOrders(enabled = true) {
  const [orders, setOrders] = useState<LiveOrder[]>([]);

  const { connected } = usePolling<LiveOrder[]>(
    "/admin/live/orders",
    (data) => setOrders(Array.isArray(data) ? data : []),
    5_000,
    enabled
  );

  return { orders, connected };
}
