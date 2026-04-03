import { beforeEach, describe, expect, it, vi, type Mock } from "vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import OrdersPage from "./page";
import { ordersApi } from "@/lib/api";

const mockUseQuery = vi.fn();
const mockUseMutation = vi.fn();
const mockUseQueryClient = vi.fn();
const mockInvalidateQueries = vi.fn();
let previewData = makePreviewData();
let ordersData = [makeOrder()];

vi.mock("next/link", () => ({
  default: ({ href, children }: { href: string; children: ReactNode }) => <a href={href}>{children}</a>,
}));

vi.mock("@/components/data-table", () => ({
  DataTable: ({ data }: { data: unknown[] }) => <div data-testid="orders-table">rows:{data.length}</div>,
}));

vi.mock("@tanstack/react-query", () => ({
  useQuery: (...args: unknown[]) => mockUseQuery(...args),
  useMutation: (...args: unknown[]) => mockUseMutation(...args),
  useQueryClient: (...args: unknown[]) => mockUseQueryClient(...args),
}));

vi.mock("sonner", () => ({
  toast: {
    success: vi.fn(),
    error: vi.fn(),
  },
}));

vi.mock("@/lib/api", () => ({
  ordersApi: {
    list: vi.fn(),
    get: vi.fn(),
    getActive: vi.fn(),
    cancel: vi.fn(),
    reassign: vi.fn(),
    previewStuck: vi.fn(),
    deleteStuck: vi.fn(),
  },
}));

function makeOrder(overrides: Record<string, unknown> = {}) {
  return {
    $id: "order_1",
    order_number: "CHZ-9001",
    customer_id: "cust_1",
    restaurant_id: "rest_1",
    restaurant_name: "Test Restaurant",
    delivery_address_id: "addr_1",
    items: "[]",
    item_total: 240,
    delivery_type: "standard",
    delivery_fee: 20,
    platform_fee: 5,
    gst: 12,
    discount: 0,
    tip: 0,
    grand_total: 277,
    payment_method: "cod",
    payment_status: "pending",
    status: "cancelled",
    special_instructions: "",
    delivery_instructions: "",
    estimated_delivery_min: 35,
    placed_at: "2026-04-03T10:30:00Z",
    ...overrides,
  };
}

function makePreviewData(overrides: Record<string, unknown> = {}) {
  return {
    orders: [makeOrder()],
    eligible_count: 2,
    blocked_count: 1,
    min_age_minutes: 180,
    cutoff_time: "2026-04-03T07:30:00Z",
    filters: {
      requested_statuses: ["delivered", "cancelled"],
      effective_statuses: ["delivered", "cancelled"],
      blocked_statuses: ["placed"],
      ignored_statuses: [],
    },
    pagination: {
      page: 1,
      per_page: 100,
      total: 2,
    },
    ...overrides,
  };
}

describe("OrdersPage stuck-order cleanup", () => {
  beforeEach(() => {
    mockUseQuery.mockReset();
    mockUseMutation.mockReset();
    mockUseQueryClient.mockReset();
    mockInvalidateQueries.mockReset();

    (ordersApi.deleteStuck as Mock).mockReset();

    mockUseQueryClient.mockReturnValue({
      invalidateQueries: mockInvalidateQueries,
    });

    mockUseQuery.mockImplementation((options: { queryKey: unknown[] }) => {
      const key = String(options.queryKey?.[0] ?? "");

      if (key === "admin-orders") {
        return {
          data: { data: ordersData },
          isLoading: false,
        };
      }

      if (key === "admin-orders-stuck-preview") {
        return {
          data: { data: previewData },
          isFetching: false,
          refetch: vi.fn(),
        };
      }

      return {
        data: undefined,
        isLoading: false,
      };
    });

    mockUseMutation.mockImplementation((config: { mutationFn: () => Promise<unknown> | unknown }) => ({
      mutate: () => {
        void config.mutationFn();
      },
      isPending: false,
    }));
  });

  it("renders preview summary and enforces explicit confirmation before deletion", () => {
    ordersData = [makeOrder()];
    previewData = makePreviewData();

    render(<OrdersPage />);

    expect(screen.getByText("Eligible: 2")).toBeInTheDocument();
    expect(screen.getByText("Blocked: 1")).toBeInTheDocument();

    const deleteButton = screen.getByRole("button", { name: "Delete Stuck Orders" });
    expect(deleteButton).toBeDisabled();

    const confirmationInput = screen.getByPlaceholderText("DELETE 2");
    fireEvent.change(confirmationInput, { target: { value: "DELETE 1" } });
    expect(deleteButton).toBeDisabled();

    fireEvent.change(confirmationInput, { target: { value: "DELETE 2" } });
    expect(deleteButton).toBeEnabled();
  });

  it("calls deleteStuck with normalized default filters once confirmed", async () => {
    (ordersApi.deleteStuck as Mock).mockResolvedValue({
      data: {
        examined_count: 2,
        eligible_count: 2,
        deleted_count: 2,
        failed_count: 0,
        blocked_count: 0,
        failed_orders: [],
        blocked_orders: [],
        min_age_minutes: 180,
        limit: 200,
        cutoff_time: "2026-04-03T07:30:00Z",
        filters: {
          requested_statuses: ["delivered", "cancelled"],
          effective_statuses: ["delivered", "cancelled"],
          blocked_statuses: [],
          ignored_statuses: [],
        },
      },
    });

    ordersData = [makeOrder()];
    previewData = makePreviewData({
      blocked_count: 0,
      filters: {
        requested_statuses: ["delivered", "cancelled"],
        effective_statuses: ["delivered", "cancelled"],
        blocked_statuses: [],
        ignored_statuses: [],
      },
    });

    render(<OrdersPage />);

    fireEvent.change(screen.getByPlaceholderText("DELETE 2"), {
      target: { value: "DELETE 2" },
    });

    fireEvent.click(screen.getByRole("button", { name: "Delete Stuck Orders" }));

    await waitFor(() => {
      expect(ordersApi.deleteStuck).toHaveBeenCalledWith({
        statuses: ["delivered", "cancelled"],
        min_age_minutes: 180,
        limit: 200,
      });
    });
  });
});
