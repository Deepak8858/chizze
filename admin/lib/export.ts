import Papa from "papaparse";

/** Export an array of objects to CSV and trigger browser download */
export function exportCSV(data: Record<string, unknown>[], filename: string) {
  const csv = Papa.unparse(data);
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${filename}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

/** Export an element (or element ID) as PDF */
export async function exportPDF(el: HTMLElement | string, filename: string) {
  const { default: html2canvas } = await import("html2canvas");
  const { default: jsPDF } = await import("jspdf");

  const element = typeof el === "string" ? document.getElementById(el) : el;
  if (!element) return;

  const canvas = await html2canvas(element, {
    backgroundColor: "#0D0D0D",
    scale: 2,
  });

  const imgData = canvas.toDataURL("image/png");
  const pdf = new jsPDF({ orientation: "landscape", unit: "px", format: "a4" });
  const pdfWidth = pdf.internal.pageSize.getWidth();
  const pdfHeight = (canvas.height * pdfWidth) / canvas.width;

  pdf.addImage(imgData, "PNG", 0, 0, pdfWidth, pdfHeight);
  pdf.save(`${filename}.pdf`);
}

/** Flatten a financial report for CSV export */
export function flattenForCSV(obj: Record<string, unknown>): Record<string, unknown>[] {
  if (Array.isArray(obj)) return obj as Record<string, unknown>[];
  return [obj];
}
