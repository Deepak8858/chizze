"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Phone, KeyRound, Loader2, ShieldCheck } from "lucide-react";
import { authApi } from "@/lib/api";
import { saveAuth, useRedirectIfAuthed } from "@/lib/auth";
import type { AdminUser } from "@/lib/auth";
import { cn } from "@/lib/utils";

export default function LoginPage() {
  useRedirectIfAuthed();

  const router = useRouter();
  const [step, setStep] = useState<"phone" | "otp">("phone");
  const [phone, setPhone] = useState("");
  const [otp, setOtp] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSendOtp = async () => {
    if (phone.length < 10) {
      toast.error("Enter a valid 10-digit phone number");
      return;
    }
    setLoading(true);
    try {
      await authApi.sendOtp(`+91${phone}`);
      toast.success("OTP sent!");
      setStep("otp");
    } catch {
      toast.error("Failed to send OTP. Check the phone number.");
    } finally {
      setLoading(false);
    }
  };

  const handleVerifyOtp = async () => {
    if (otp.length !== 6) {
      toast.error("Enter the 6-digit OTP");
      return;
    }
    setLoading(true);
    try {
      const res = await authApi.verifyOtp(`+91${phone}`, otp);
      const role = res.user?.role;
      if (!role || role === "customer" || role === "restaurant_owner" || role === "delivery_partner") {
        toast.error("Access denied. Admin accounts only.");
        setLoading(false);
        return;
      }
      saveAuth(res.token, res.user as unknown as AdminUser);
      toast.success("Welcome back!");
      router.replace("/");
    } catch {
      toast.error("Invalid OTP. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-bg-base flex items-center justify-center p-4">
      {/* Background gradient */}
      <div className="absolute inset-0 bg-gradient-to-br from-brand-500/5 via-transparent to-transparent pointer-events-none" />

      <div className="w-full max-w-sm relative">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center gap-2 mb-2">
            <span className="text-brand-500 font-extrabold text-4xl tracking-tight">chizze</span>
            <span className="text-xs font-semibold bg-brand-500/20 text-brand-400 px-2 py-1 rounded uppercase tracking-widest self-end mb-1">
              admin
            </span>
          </div>
          <p className="text-text-muted text-sm">Sign in to your admin account</p>
        </div>

        {/* Card */}
        <div className="card">
          <div className="flex items-center gap-2 mb-6">
            <div className="w-8 h-8 bg-brand-500/20 rounded-lg flex items-center justify-center">
              <ShieldCheck size={16} className="text-brand-400" />
            </div>
            <div>
              <p className="text-sm font-semibold text-white">
                {step === "phone" ? "Enter your phone" : "Verify OTP"}
              </p>
              <p className="text-xs text-text-muted">
                {step === "phone"
                  ? "We'll send a 6-digit code"
                  : `Code sent to +91 ${phone}`}
              </p>
            </div>
          </div>

          {step === "phone" ? (
            <div className="space-y-4">
              <div>
                <label className="text-xs text-text-secondary mb-1.5 block">Phone number</label>
                <div className="flex items-center gap-2 h-10 bg-bg-elevated border border-white/10 rounded-lg px-3 focus-within:border-brand-500 transition-colors">
                  <Phone size={14} className="text-text-muted flex-shrink-0" />
                  <div className="text-text-muted text-sm">+91</div>
                  <div className="w-px h-4 bg-white/10" />
                  <input
                    type="tel"
                    maxLength={10}
                    placeholder="98765 43210"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value.replace(/\D/g, ""))}
                    onKeyDown={(e) => e.key === "Enter" && handleSendOtp()}
                    className="flex-1 bg-transparent text-white placeholder-text-muted text-sm outline-none"
                  />
                </div>
              </div>

              <button
                onClick={handleSendOtp}
                disabled={loading}
                className={cn(
                  "w-full h-10 bg-brand-500 hover:bg-brand-600 text-bg-base font-semibold text-sm rounded-lg transition-colors flex items-center justify-center gap-2",
                  loading && "opacity-60 cursor-not-allowed"
                )}
              >
                {loading && <Loader2 size={14} className="animate-spin" />}
                Send OTP
              </button>
            </div>
          ) : (
            <div className="space-y-4">
              <div>
                <label className="text-xs text-text-secondary mb-1.5 block">6-digit OTP</label>
                <div className="flex items-center gap-2 h-10 bg-bg-elevated border border-white/10 rounded-lg px-3 focus-within:border-brand-500 transition-colors">
                  <KeyRound size={14} className="text-text-muted flex-shrink-0" />
                  <input
                    type="text"
                    maxLength={6}
                    placeholder="000000"
                    value={otp}
                    onChange={(e) => setOtp(e.target.value.replace(/\D/g, ""))}
                    onKeyDown={(e) => e.key === "Enter" && handleVerifyOtp()}
                    className="flex-1 bg-transparent text-white placeholder-text-muted text-sm outline-none tracking-[0.3em] font-mono"
                    autoFocus
                  />
                </div>
              </div>

              <button
                onClick={handleVerifyOtp}
                disabled={loading}
                className={cn(
                  "w-full h-10 bg-brand-500 hover:bg-brand-600 text-bg-base font-semibold text-sm rounded-lg transition-colors flex items-center justify-center gap-2",
                  loading && "opacity-60 cursor-not-allowed"
                )}
              >
                {loading && <Loader2 size={14} className="animate-spin" />}
                Verify & Sign In
              </button>

              <button
                onClick={() => { setStep("phone"); setOtp(""); }}
                className="w-full text-center text-xs text-text-muted hover:text-white transition-colors"
              >
                ← Change phone number
              </button>
            </div>
          )}
        </div>

        <p className="text-center text-xs text-text-muted mt-4">
          Chizze Admin Panel · Restricted Access
        </p>
      </div>
    </div>
  );
}
