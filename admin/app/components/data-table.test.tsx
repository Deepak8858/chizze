import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type { ColumnDef } from "@tanstack/react-table";

import { DataTable } from "@/components/data-table";

type Row = {
  name: string;
  partner_id: string;
  amount: number;
};

const columns: ColumnDef<Row, unknown>[] = [
  {
    accessorKey: "name",
    header: "Name",
    cell: ({ getValue }) => <span>{getValue() as string}</span>,
  },
  {
    accessorKey: "amount",
    header: "Amount",
    cell: ({ getValue }) => <span>{getValue() as number}</span>,
  },
];

describe("DataTable", () => {
  it("filters rows using raw search column data even when the field is not displayed", () => {
    render(
      <DataTable
        columns={columns}
        data={[
          { name: "Alpha", partner_id: "partner_1", amount: 10 },
          { name: "Beta", partner_id: "partner_2", amount: 20 },
        ]}
        searchColumn="partner_id"
        searchPlaceholder="Search partner"
      />
    );

    expect(screen.getByText("Alpha")).toBeInTheDocument();
    expect(screen.getByText("Beta")).toBeInTheDocument();

    fireEvent.change(screen.getByPlaceholderText("Search partner"), {
      target: { value: "partner_2" },
    });

    expect(screen.queryByText("Alpha")).not.toBeInTheDocument();
    expect(screen.getByText("Beta")).toBeInTheDocument();
  });
});