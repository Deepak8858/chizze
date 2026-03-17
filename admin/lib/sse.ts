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

/** Generic SSE hook */
export function useSSE<T>(
  path: string,
  onMessage: (data: T) => void,
  enabled = true
) {
  const esRef = useRef<EventSource | null>(null);
  const retryRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [connected, setConnected] = useState(false);

  const connect = useCallback(() => {
    if (!enabled) return;
    const token = getToken();
    const url = `${BASE_URL}${path}${token ? `?token=${token}` : ""}`;
    const es = new EventSource(url, { withCredentials: true });
    esRef.current = es;

    es.onopen = () => setConnected(true);

    es.onmessage = (e) => {
      try {
        onMessage(JSON.parse(e.data) as T);
      } catch {
        // skip malformed
      }
    };

    es.onerror = () => {
      setConnected(false);
      es.close();
      // exponential backoff retry
      retryRef.current = setTimeout(connect, 5000);
    };
  }, [path, onMessage, enabled]);

  useEffect(() => {
    connect();
    return () => {
      esRef.current?.close();
      if (retryRef.current) clearTimeout(retryRef.current);
    };
  }, [connect]);

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

  const { connected } = useSSE<LiveStats>(
    "/admin/live/stats",
    (data) => setStats(data),
    enabled
  );

  return { stats, connected };
}

// ─── Live riders hook ─────────────────────────────────────────────────────────
export function useRiderLocations(enabled = true) {
  const [riders, setRiders] = useState<Map<string, LiveRider>>(new Map());

  const handleMessage = useCallback((data: LiveRider | LiveRider[]) => {
    setRiders((prev) => {
      const next = new Map(prev);
      const updates = Array.isArray(data) ? data : [data];
      for (const r of updates) {
        next.set(r.rider_id, r);
      }
      return next;
    });
  }, []);

  const { connected } = useSSE<LiveRider | LiveRider[]>(
    "/admin/live/riders",
    handleMessage,
    enabled
  );

  return { riders: Array.from(riders.values()), connected };
}

// ─── Live orders hook ─────────────────────────────────────────────────────────
export function useLiveOrders(enabled = true) {
  const [orders, setOrders] = useState<Map<string, LiveOrder>>(new Map());

  const handleMessage = useCallback((data: LiveOrder | LiveOrder[]) => {
    setOrders((prev) => {
      const next = new Map(prev);
      const updates = Array.isArray(data) ? data : [data];
      for (const o of updates) {
        if (o.status === "delivered" || o.status === "cancelled") {
          next.delete(o.order_id);
        } else {
          next.set(o.order_id, o);
        }
      }
      return next;
    });
  }, []);

  const { connected } = useSSE<LiveOrder | LiveOrder[]>(
    "/admin/live/orders",
    handleMessage,
    enabled
  );

  return { orders: Array.from(orders.values()), connected };
}
