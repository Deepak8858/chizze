"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { settingsApi } from "@/lib/api";
import { toast } from "sonner";
import { AxiosError } from "axios";
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
  allow_restaurant_partner_signup: boolean;
  allow_delivery_partner_signup: boolean;
};

const defaultSettings: SettingsData = {
  platform_name: "Chizze",
  platform_fee_percentage: 15,
  min_order_amount: 99,
  max_delivery_radius_km: 10,
  otp_expiry_minutes: 5,
  razorpay_live_mode: false,
  maintenance_mode: false,
  gold_subscription_monthly_price: 199,
  gold_subscription_yearly_price: 1999,
  referral_reward_amount: 50,
  referral_min_orders: 1,
  free_delivery_above_amount: 299,
  support_email: "supportchizze@gmail.com",
  support_phone: "7376389133",
  allow_restaurant_partner_signup: true,
  allow_delivery_partner_signup: true,
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

function TextInput({
  value,
  onChange,
  type = "text",
  title = "Setting value",
  placeholder = "Enter value",
}: {
  value: string | number;
  onChange: (v: string) => void;
  type?: string;
  title?: string;
  placeholder?: string;
}) {
  return (
    <input
      type={type}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      title={title}
      placeholder={placeholder}
      className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
    />
  );
}

function Toggle({ label, checked, onChange }: { label: string; checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <div className="flex items-center justify-between p-3 rounded-lg bg-surface-200 col-span-1 sm:col-span-2">
      <span className="text-sm text-text-secondary">{label}</span>
      <button
        type="button"
        title={label}
        aria-label={label}
        onClick={() => onChange(!checked)}
        className={`relative w-10 h-5 rounded-full transition-colors ${checked ? "bg-brand-500" : "bg-white/10"}`}
      >
        <span
          className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${checked ? "translate-x-5" : ""}`}
        />
      </button>
    </div>
  );
}

export default function SettingsPage() {
  const qc = useQueryClient();
  const { data, isLoading, isError } = useQuery<{
    data: Partial<SettingsData>;
  }>({
    queryKey: ["platform-settings"],
    queryFn: () =>
      settingsApi.get() as Promise<{ data: Partial<SettingsData> }>,
    retry: 1,
  });

  const remoteSettings: SettingsData = {
    ...defaultSettings,
    ...(data?.data ?? {}),
  };

  const [draftForm, setDraftForm] = useState<SettingsData | null>(null);
  const form = draftForm ?? remoteSettings;

  const toNumberOr = (value: string, fallback: number) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  };

  const saveMutation = useMutation({
    mutationFn: (body: SettingsData) => settingsApi.update(body),
    onSuccess: async () => {
      toast.success("Settings saved");
      setDraftForm(null);
      await qc.invalidateQueries({ queryKey: ["platform-settings"] });
    },
    onError: (error: unknown) => {
      const axiosError = error as AxiosError<{
        error?: string;
        message?: string;
      }>;
      const serverMessage =
        axiosError?.response?.data?.error ??
        axiosError?.response?.data?.message;
      toast.error(serverMessage || "Failed to save settings");
    },
  });

  const set = (k: keyof SettingsData, v: unknown) =>
    setDraftForm((f) => ({ ...(f ?? remoteSettings), [k]: v }) as SettingsData);

  if (isLoading) {
    return (
      <div className="space-y-6">
        <div className="skeleton h-8 w-40 rounded-lg" />
        {[...Array(4)].map((_, i) => <div key={i} className="skeleton h-48 rounded-xl" />)}
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex flex-col items-center justify-center h-64 gap-4">
        <p className="text-text-muted text-sm">
          Failed to load platform settings.
        </p>
        <button
          onClick={() =>
            qc.invalidateQueries({ queryKey: ["platform-settings"] })
          }
          className="px-4 py-2 rounded-lg bg-brand-500/10 text-brand-400 text-sm hover:bg-brand-500/20 transition-colors"
        >
          Retry
        </button>
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
          <p className="text-sm text-text-muted">
            Global configuration for Chizze
          </p>
        </div>
        <button
          onClick={() => saveMutation.mutate(form)}
          disabled={saveMutation.isPending}
          className="flex items-center gap-2 px-4 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium disabled:opacity-50 transition-colors"
        >
          <Save size={14} />{" "}
          {saveMutation.isPending ? "Saving…" : "Save Changes"}
        </button>
      </div>

      <Section title="General">
        <Field label="Platform Name">
          <TextInput
            value={form.platform_name}
            onChange={(v) => set("platform_name", v)}
          />
        </Field>
        <Field label="Support Email">
          <TextInput
            value={form.support_email}
            onChange={(v) => set("support_email", v)}
            type="email"
          />
        </Field>
        <Field label="Support Phone">
          <TextInput
            value={form.support_phone}
            onChange={(v) => set("support_phone", v)}
          />
        </Field>
        <Toggle
          label="Maintenance Mode"
          checked={form.maintenance_mode}
          onChange={(v) => set("maintenance_mode", v)}
        />
        <Toggle
          label="Allow New Restaurant Partner Signups"
          checked={form.allow_restaurant_partner_signup}
          onChange={(v) => set("allow_restaurant_partner_signup", v)}
        />
        <Toggle
          label="Allow New Delivery Partner Signups"
          checked={form.allow_delivery_partner_signup}
          onChange={(v) => set("allow_delivery_partner_signup", v)}
        />
      </Section>

      <Section title="Pricing & Fees">
        <Field label="Platform Fee (%)">
          <TextInput
            value={form.platform_fee_percentage}
            onChange={(v) =>
              set(
                "platform_fee_percentage",
                toNumberOr(v, form.platform_fee_percentage),
              )
            }
            type="number"
          />
        </Field>
        <Field label="Min Order Amount (₹)">
          <TextInput
            value={form.min_order_amount}
            onChange={(v) =>
              set("min_order_amount", toNumberOr(v, form.min_order_amount))
            }
            type="number"
          />
        </Field>
        <Field label="Free Delivery Above (₹)">
          <TextInput
            value={form.free_delivery_above_amount}
            onChange={(v) =>
              set(
                "free_delivery_above_amount",
                toNumberOr(v, form.free_delivery_above_amount),
              )
            }
            type="number"
          />
        </Field>
        <Field label="Max Delivery Radius (km)">
          <TextInput
            value={form.max_delivery_radius_km}
            onChange={(v) =>
              set(
                "max_delivery_radius_km",
                toNumberOr(v, form.max_delivery_radius_km),
              )
            }
            type="number"
          />
        </Field>
        <Toggle
          label="Razorpay Live Mode"
          checked={form.razorpay_live_mode}
          onChange={(v) => set("razorpay_live_mode", v)}
        />
      </Section>

      <Section title="Gold Subscription">
        <Field label="Monthly Price (₹)">
          <TextInput
            value={form.gold_subscription_monthly_price}
            onChange={(v) =>
              set(
                "gold_subscription_monthly_price",
                toNumberOr(v, form.gold_subscription_monthly_price),
              )
            }
            type="number"
          />
        </Field>
        <Field label="Yearly Price (₹)">
          <TextInput
            value={form.gold_subscription_yearly_price}
            onChange={(v) =>
              set(
                "gold_subscription_yearly_price",
                toNumberOr(v, form.gold_subscription_yearly_price),
              )
            }
            type="number"
          />
        </Field>
      </Section>

      <Section title="Referrals & OTP">
        <Field label="Referral Reward (₹)">
          <TextInput
            value={form.referral_reward_amount}
            onChange={(v) =>
              set(
                "referral_reward_amount",
                toNumberOr(v, form.referral_reward_amount),
              )
            }
            type="number"
          />
        </Field>
        <Field label="Min Orders for Reward">
          <TextInput
            value={form.referral_min_orders}
            onChange={(v) =>
              set(
                "referral_min_orders",
                toNumberOr(v, form.referral_min_orders),
              )
            }
            type="number"
          />
        </Field>
        <Field label="OTP Expiry (minutes)">
          <TextInput
            value={form.otp_expiry_minutes}
            onChange={(v) =>
              set("otp_expiry_minutes", toNumberOr(v, form.otp_expiry_minutes))
            }
            type="number"
          />
        </Field>
      </Section>
    </div>
  );
}
