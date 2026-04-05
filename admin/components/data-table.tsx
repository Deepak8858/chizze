"use client";
import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  getPaginationRowModel,
  flexRender,
  type ColumnDef,
  type SortingState,
} from "@tanstack/react-table";
import { useMemo, useState } from "react";
import { ChevronUp, ChevronDown, ChevronsUpDown, ChevronLeft, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";

interface DataTableProps<TData> {
  columns: ColumnDef<TData, unknown>[];
  data: TData[];
  pageSize?: number;
  loading?: boolean;
  emptyMessage?: string;
  searchColumn?: string;
  searchPlaceholder?: string;
}

export function DataTable<TData>({
  columns,
  data,
  pageSize = 20,
  loading = false,
  emptyMessage = "No data found.",
  searchColumn,
  searchPlaceholder = "Search…",
}: DataTableProps<TData>) {
  const [sorting, setSorting] = useState<SortingState>([]);
  const [searchValue, setSearchValue] = useState("");

  const normalizedSearch = searchValue.trim().toLowerCase();

  const filteredData = useMemo(() => {
    if (!searchColumn || normalizedSearch === "") {
      return data;
    }

    return data.filter((row) => {
      const value = (row as Record<string, unknown>)[searchColumn];
      if (value === null || value === undefined) {
        return false;
      }

      return String(value).toLowerCase().includes(normalizedSearch);
    });
  }, [data, normalizedSearch, searchColumn]);

  const table = useReactTable({
    data: filteredData,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    autoResetPageIndex: true,
    initialState: { pagination: { pageSize } },
  });

  return (
    <div className="space-y-3">
      {/* Search */}
      {searchColumn && (
        <input
          type="text"
          placeholder={searchPlaceholder}
          value={searchValue}
          onChange={(e) => setSearchValue(e.target.value)}
          className="h-9 w-full max-w-xs bg-bg-elevated border border-white/10 rounded-lg px-3 text-sm text-white placeholder-text-muted outline-none focus:border-brand-500 transition-colors"
        />
      )}

      {/* Table */}
      <div className="card !p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              {table.getHeaderGroups().map((hg) => (
                <tr
                  key={hg.id}
                  className="bg-bg-elevated border-b border-white/[0.06]"
                >
                  {hg.headers.map((header) => (
                    <th
                      key={header.id}
                      onClick={header.column.getToggleSortingHandler()}
                      className={cn(
                        "px-4 py-3 text-left text-[11px] font-semibold text-text-secondary uppercase tracking-wider whitespace-nowrap",
                        header.column.getCanSort() &&
                          "cursor-pointer select-none hover:text-white",
                      )}
                    >
                      <div className="flex items-center gap-1">
                        {flexRender(
                          header.column.columnDef.header,
                          header.getContext(),
                        )}
                        {header.column.getCanSort() && (
                          <span className="text-text-muted">
                            {header.column.getIsSorted() === "asc" ? (
                              <ChevronUp size={12} />
                            ) : header.column.getIsSorted() === "desc" ? (
                              <ChevronDown size={12} />
                            ) : (
                              <ChevronsUpDown size={12} />
                            )}
                          </span>
                        )}
                      </div>
                    </th>
                  ))}
                </tr>
              ))}
            </thead>
            <tbody>
              {loading ? (
                Array.from({ length: 5 }).map((_, i) => (
                  <tr key={i} className="border-b border-white/[0.04]">
                    {columns.map((_, j) => (
                      <td key={j} className="px-4 py-3">
                        <div className="skeleton h-4 w-full" />
                      </td>
                    ))}
                  </tr>
                ))
              ) : table.getRowModel().rows.length === 0 ? (
                <tr>
                  <td
                    colSpan={columns.length}
                    className="px-4 py-12 text-center text-text-muted text-sm"
                  >
                    {emptyMessage}
                  </td>
                </tr>
              ) : (
                table.getRowModel().rows.map((row) => (
                  <tr
                    key={row.id}
                    className="border-b border-white/[0.04] hover:bg-bg-hover transition-colors duration-100"
                  >
                    {row.getVisibleCells().map((cell) => (
                      <td
                        key={cell.id}
                        className="px-4 py-3 text-sm text-white"
                      >
                        {flexRender(
                          cell.column.columnDef.cell,
                          cell.getContext(),
                        )}
                      </td>
                    ))}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Pagination */}
      {filteredData.length > pageSize && (
        <div className="flex items-center justify-between text-sm text-text-secondary">
          <span>
            Page {table.getState().pagination.pageIndex + 1} of{" "}
            {table.getPageCount()}
          </span>
          <div className="flex items-center gap-1">
            <button
              onClick={() => table.previousPage()}
              disabled={!table.getCanPreviousPage()}
              title="Previous page"
              aria-label="Previous page"
              className="h-7 w-7 flex items-center justify-center rounded bg-bg-elevated text-text-muted hover:text-white disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              <ChevronLeft size={14} />
            </button>
            {Array.from({ length: Math.min(5, table.getPageCount()) }).map(
              (_, i) => {
                const page =
                  i + Math.max(0, table.getState().pagination.pageIndex - 2);
                if (page >= table.getPageCount()) return null;
                return (
                  <button
                    key={page}
                    onClick={() => table.setPageIndex(page)}
                    className={cn(
                      "h-7 w-7 flex items-center justify-center rounded text-xs font-medium transition-colors",
                      table.getState().pagination.pageIndex === page
                        ? "bg-brand-500 text-bg-base"
                        : "bg-bg-elevated text-text-muted hover:text-white",
                    )}
                  >
                    {page + 1}
                  </button>
                );
              },
            )}
            <button
              onClick={() => table.nextPage()}
              disabled={!table.getCanNextPage()}
              title="Next page"
              aria-label="Next page"
              className="h-7 w-7 flex items-center justify-center rounded bg-bg-elevated text-text-muted hover:text-white disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              <ChevronRight size={14} />
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
