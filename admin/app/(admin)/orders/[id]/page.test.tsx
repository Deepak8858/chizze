import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import OrderDetailPage from "./page";

const mockUseQuery = vi.fn();
const mockUseMutation = vi.fn();
const mockUseQueryClient = vi.fn();

vi.mock("next/navigation", () => ({
  useParams: () => ({ id: "order_1" }),
}));

vi.mock("next/link", () => ({
  default: ({ href, children }: { href: string; children: ReactNode }) => (
    <a href={href}>{children}</a>
  ),
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

function makeBaseOrder(overrides: Record<string, unknown> = {}) {
  return {
    $id: "order_1",
    order_number: "CHZ-1001",
    customer_id: "cust_1",
    restaurant_id: "rest_1",
    restaurant_name: "Test Restaurant",
    delivery_address_id: "addr_1",
    items: JSON.stringify([
      { name: "Paneer Roll", quantity: 2, price: 120, is_veg: true },
    ]),
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
    status: "placed",
    special_instructions: "",
    delivery_instructions: "Call before arrival",
    estimated_delivery_min: 35,
    placed_at: "2026-04-03T10:30:00Z",
    ...overrides,
  };
}

describe("OrderDetailPage", () => {
  beforeEach(() => {
    mockUseQuery.mockReset();
    mockUseMutation.mockReset();
    mockUseQueryClient.mockReset();
    mockUseMutation.mockReturnValue({ mutate: vi.fn(), isPending: false });
    mockUseQueryClient.mockReturnValue({ invalidateQueries: vi.fn() });
  });

  it("renders customer identity and location details when enriched fields are present", () => {
    const order = makeBaseOrder({
      customer_name: "Alice Customer",
      customer_phone: "+919999999999",
      delivery_address_line: "221B Baker Street",
      delivery_city: "Bengaluru",
      delivery_latitude: 12.9831,
      delivery_longitude: 77.6401,
    });

    mockUseQuery
      .mockReturnValueOnce({ data: { data: order }, isLoading: false })
      .mockReturnValueOnce({ data: { data: [] }, isLoading: false });

    render(<OrderDetailPage />);

    expect(screen.getByText("Alice Customer")).toBeInTheDocument();
    expect(screen.getByText("+919999999999")).toBeInTheDocument();
    expect(screen.getByText("221B Baker Street, Bengaluru")).toBeInTheDocument();
    expect(screen.getByText("12.983100, 77.640100")).toBeInTheDocument();
  });

  it("shows Not available fallback values when enriched fields are missing", () => {
    const order = makeBaseOrder();

    mockUseQuery
      .mockReturnValueOnce({ data: { data: order }, isLoading: false })
      .mockReturnValueOnce({ data: { data: [] }, isLoading: false });

    render(<OrderDetailPage />);

    expect(screen.queryByText("Alice Customer")).not.toBeInTheDocument();
    expect(screen.queryByText("221B Baker Street, Bengaluru")).not.toBeInTheDocument();
    expect(screen.getAllByText("Not available").length).toBeGreaterThanOrEqual(4);
  });
});
