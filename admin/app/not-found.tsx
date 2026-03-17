import Link from "next/link";

export default function NotFound() {
  return (
    <div className="min-h-screen bg-bg-base flex items-center justify-center p-4">
      <div className="text-center max-w-md">
        {/* Big 404 */}
        <p className="text-[120px] font-extrabold leading-none text-white/[0.04] select-none">
          404
        </p>

        {/* Icon + heading */}
        <div className="-mt-6 mb-6">
          <div className="w-16 h-16 bg-brand-500/10 rounded-2xl flex items-center justify-center mx-auto mb-4">
            <span className="text-brand-400 text-2xl font-bold">?</span>
          </div>
          <h1 className="text-2xl font-bold text-white mb-2">Page not found</h1>
          <p className="text-text-muted text-sm">
            The page you&apos;re looking for doesn&apos;t exist or has been moved.
          </p>
        </div>

        <Link
          href="/dashboard"
          className="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg bg-brand-500 hover:bg-brand-600 text-white font-semibold text-sm transition-colors"
        >
          ← Back to Dashboard
        </Link>
      </div>
    </div>
  );
}
