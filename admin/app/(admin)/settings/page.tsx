"use client";
import { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { settingsApi } from "@/lib/api";
import { toast } from "sonner";
import { Save, Settings } from "lucide-react";

type SettingsData = {
  platform_name: string;
  platform_fee_percentage: number;
  min_order_amount: number;
  max_delivery_radius_km: number;
  otp_expiry_minutes: number;
  razorpay_live_mode: boolean;
  maintenance_mode: boolean;
  gold_subscription_monthly_price: number;
  gold_subscription_yearly_price: number;
  referral_reward_amount: number;
  referral_min_orders: number;
  free_delivery_above_amount: number;
  support_email: string;
  support_phone: string;
};

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="card p-5 space-y-4">
      <h2 className="text-sm font-semibold text-white border-b border-white/5 pb-3">{title}</h2>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">{children}</div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="text-xs text-text-muted mb-1 block">{label}</label>
      {children}
    </div>
  );
}

function TextInput({ value, onChange, type = "text" }: { value: string | number; onChange: (v: string) => void; type?: string }) {
  return (
    <input
      type={type}
      value={value}
      onChange={e => onChange(e.target.value)}
      className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
    />
  );
}

function Toggle({ label, checked, onChange }: { label: string; checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <div className="flex items-center justify-between p-3 rounded-lg bg-surface-200 col-span-1 sm:col-span-2">
      <span className="text-sm text-text-secondary">{label}</span>
      <button
        onClick={() => onChange(!checked)}
        className={`relative w-10 h-5 rounded-full transition-colors ${checked ? "bg-brand-500" : "bg-white/10"}`}
      >
        <span className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${checked ? "translate-x-5" : ""}`} />
      </button>
    </div>
  );
}

export default function SettingsPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["platform-settings"],
    queryFn: () => settingsApi.get() as Promise<{ data: SettingsData }>,
  });

  const [form, setForm] = useState<SettingsData | null>(null);
  useEffect(() => { if (data?.data) setForm(data.data); }, [data]);

  const saveMutation = useMutation({
    mutationFn: (body: SettingsData) => settingsApi.update(body),
    onSuccess: () => toast.success("Settings saved"),
    onError: () => toast.error("Failed to save"),
  });

  const set = (k: keyof SettingsData, v: unknown) => setForm(f => f ? { ...f, [k]: v } : f);

  if (isLoading || !form) {
    return (
      <div className="space-y-6">
        <div className="skeleton h-8 w-40 rounded-lg" />
        {[...Array(4)].map((_, i) => <div key={i} className="skeleton h-48 rounded-xl" />)}
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Settings size={20} className="text-brand-400" /> Platform Settings
          </h1>
          <p className="text-sm text-text-muted">Global configuration for Chizze</p>
        </div>
        <button
          onClick={() => saveMutation.mutate(form)}
          disabled={saveMutation.isPending}
          className="flex items-center gap-2 px-4 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium disabled:opacity-50 transition-colors"
        >
          <Save size={14} /> {saveMutation.isPending ? "Saving…" : "Save Changes"}
        </button>
      </div>

      <Section title="General">
        <Field label="Platform Name">
          <TextInput value={form.platform_name} onChange={v => set("platform_name", v)} />
        </Field>
        <Field label="Support Email">
          <TextInput value={form.support_email} onChange={v => set("support_email", v)} type="email" />
        </Field>
        <Field label="Support Phone">
          <TextInput value={form.support_phone} onChange={v => set("support_phone", v)} />
        </Field>
        <Toggle label="Maintenance Mode" checked={form.maintenance_mode} onChange={v => set("maintenance_mode", v)} />
      </Section>

      <Section title="Pricing & Fees">
        <Field label="Platform Fee (%)">
          <TextInput value={form.platform_fee_percentage} onChange={v => set("platform_fee_percentage", +v)} type="number" />
        </Field>
        <Field label="Min Order Amount (₹)">
          <TextInput value={form.min_order_amount} onChange={v => set("min_order_amount", +v)} type="number" />
        </Field>
        <Field label="Free Delivery Above (₹)">
          <TextInput value={form.free_delivery_above_amount} onChange={v => set("free_delivery_above_amount", +v)} type="number" />
        </Field>
        <Field label="Max Delivery Radius (km)">
          <TextInput value={form.max_delivery_radius_km} onChange={v => set("max_delivery_radius_km", +v)} type="number" />
        </Field>
        <Toggle label="Razorpay Live Mode" checked={form.razorpay_live_mode} onChange={v => set("razorpay_live_mode", v)} />
      </Section>

      <Section title="Gold Subscription">
        <Field label="Monthly Price (₹)">
          <TextInput value={form.gold_subscription_monthly_price} onChange={v => set("gold_subscription_monthly_price", +v)} type="number" />
        </Field>
        <Field label="Yearly Price (₹)">
          <TextInput value={form.gold_subscription_yearly_price} onChange={v => set("gold_subscription_yearly_price", +v)} type="number" />
        </Field>
      </Section>

      <Section title="Referrals & OTP">
        <Field label="Referral Reward (₹)">
          <TextInput value={form.referral_reward_amount} onChange={v => set("referral_reward_amount", +v)} type="number" />
        </Field>
        <Field label="Min Orders for Reward">
          <TextInput value={form.referral_min_orders} onChange={v => set("referral_min_orders", +v)} type="number" />
        </Field>
        <Field label="OTP Expiry (minutes)">
          <TextInput value={form.otp_expiry_minutes} onChange={v => set("otp_expiry_minutes", +v)} type="number" />
        </Field>
      </Section>
    </div>
  );
}
