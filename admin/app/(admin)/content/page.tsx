"use client";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { contentApi } from "@/lib/api";
import { StatusBadge } from "@/components/ui/status-badge";
import { toast } from "sonner";
import type { Banner } from "@/types";
import { Plus, Trash2, ImageIcon, Layout, Pencil } from "lucide-react";

const PROMO_BANNERS_BUCKET =
  process.env.NEXT_PUBLIC_APPWRITE_BANNERS_BUCKET ?? "promo-banners";

const bannerFormFields = [
  { label: "Title", key: "title", type: "text" },
  { label: "Image URL", key: "image_url", type: "text" },
  { label: "Deep Link", key: "deeplink", type: "text" },
  { label: "Sort Order", key: "sort_order", type: "number" },
] as const;

const parseSafeNumber = (value: string) => {
  const parsed = Number.parseFloat(value);
  return Number.isFinite(parsed) ? parsed : 0;
};

type BannerFormState = {
  title: string;
  image_url: string;
  deeplink: string;
  target_segment: Banner["target_segment"];
  sort_order: number;
  is_active: boolean;
};

const getDefaultBannerForm = (): BannerFormState => ({
  title: "",
  image_url: "",
  deeplink: "",
  target_segment: "customers",
  sort_order: 0,
  is_active: true,
});

function BannerCard({
  banner,
  onDelete,
  onToggle,
  onEdit,
}: {
  banner: Banner;
  onDelete: (id: string) => void;
  onToggle: (id: string, active: boolean) => void;
  onEdit: (banner: Banner) => void;
}) {
  return (
    <div className="card overflow-hidden">
      {banner.image_url ? (
        <div className="h-28 bg-surface-200 overflow-hidden">
          <img
            src={banner.image_url}
            alt={banner.title}
            className="w-full h-full object-cover"
          />
        </div>
      ) : (
        <div className="h-28 bg-surface-200 flex items-center justify-center">
          <ImageIcon size={24} className="text-text-muted" />
        </div>
      )}
      <div className="p-3">
        <div className="flex items-center justify-between mb-1">
          <p className="text-white text-sm font-medium truncate">
            {banner.title}
          </p>
          <StatusBadge status={banner.is_active ? "active" : "inactive"} />
        </div>
        <p className="text-text-muted text-xs mb-2 capitalize">
          {banner.target_segment} · #{banner.sort_order}
        </p>
        <div className="flex items-center gap-2">
          <button
            title="Edit banner"
            onClick={() => onEdit(banner)}
            className="text-text-muted hover:text-white transition-colors px-2"
          >
            <Pencil size={13} />
          </button>
          <button
            onClick={() => onToggle(banner.$id, !banner.is_active)}
            className="flex-1 text-xs py-1 rounded bg-white/5 hover:bg-white/10 text-text-muted transition-colors"
          >
            {banner.is_active ? "Deactivate" : "Activate"}
          </button>
          <button
            title="Delete banner"
            onClick={() => onDelete(banner.$id)}
            className="text-status-error/60 hover:text-status-error transition-colors px-2"
          >
            <Trash2 size={13} />
          </button>
        </div>
      </div>
    </div>
  );
}

export default function ContentPage() {
  const [activeTab, setActiveTab] = useState<"banners" | "categories">("banners");
  const [showForm, setShowForm] = useState(false);
  const [editingBannerId, setEditingBannerId] = useState<string | null>(null);
  const [form, setForm] = useState<BannerFormState>(getDefaultBannerForm);
  const [isUploadingImage, setIsUploadingImage] = useState(false);
  const qc = useQueryClient();

  const closeForm = () => {
    setShowForm(false);
    setEditingBannerId(null);
    setForm(getDefaultBannerForm());
  };

  const openCreateForm = () => {
    setEditingBannerId(null);
    setForm(getDefaultBannerForm());
    setShowForm(true);
  };

  const openEditForm = (banner: Banner) => {
    setEditingBannerId(banner.$id);
    setForm({
      title: banner.title ?? "",
      image_url: banner.image_url ?? "",
      deeplink: banner.deeplink ?? "",
      target_segment: banner.target_segment ?? "all",
      sort_order: Number.isFinite(Number(banner.sort_order))
        ? Number(banner.sort_order)
        : 1,
      is_active: Boolean(banner.is_active),
    });
    setShowForm(true);
  };

  const { data: banners, isLoading: bannersLoading } = useQuery({
    queryKey: ["admin-banners"],
    queryFn: () => contentApi.getBanners() as Promise<{ data: Banner[] }>,
  });

  const { data: categories, isLoading: catLoading } = useQuery({
    queryKey: ["admin-categories"],
    queryFn: () => contentApi.getCategories() as Promise<{ data: { $id: string; name: string; image_url: string; position: number }[] }>,
  });

  const createMutation = useMutation({
    mutationFn: (body: BannerFormState) => contentApi.createBanner(body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["admin-banners"] });
      toast.success("Banner created");
      closeForm();
    },
    onError: () => toast.error("Failed"),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, body }: { id: string; body: BannerFormState }) =>
      contentApi.updateBanner(id, body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["admin-banners"] });
      toast.success("Banner updated");
      closeForm();
    },
    onError: () => toast.error("Failed to update banner"),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => contentApi.deleteBanner(id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-banners"] }); toast.success("Deleted"); },
  });

  const toggleMutation = useMutation({
    mutationFn: ({ id, is_active }: { id: string; is_active: boolean }) => contentApi.updateBanner(id, { is_active }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin-banners"] }),
  });

  const handleBannerImageUpload = async (
    e: React.ChangeEvent<HTMLInputElement>,
  ) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsUploadingImage(true);
    try {
      const formData = new FormData();
      formData.append("file", file);
      formData.append("bucket_id", PROMO_BANNERS_BUCKET);

      const uploadResult = (await contentApi.uploadBannerImage(formData)) as {
        data?: { image_url?: string };
      };

      const imageUrl = uploadResult?.data?.image_url?.trim() ?? "";
      if (!imageUrl) {
        throw new Error("Missing image URL in upload response");
      }

      setForm((f) => ({ ...f, image_url: imageUrl }));
      toast.success("Banner image uploaded");
    } catch {
      toast.error("Failed to upload image. You can still paste an image URL.");
    } finally {
      setIsUploadingImage(false);
      e.target.value = "";
    }
  };

  const isSavingBanner = createMutation.isPending || updateMutation.isPending;

  const handleBannerSubmit = () => {
    const payload: BannerFormState = {
      title: form.title.trim(),
      image_url: form.image_url.trim(),
      deeplink: form.deeplink.trim(),
      target_segment: form.target_segment,
      sort_order: form.sort_order,
      is_active: form.is_active,
    };

    if (!payload.title || !payload.image_url) {
      toast.error("Title and image are required");
      return;
    }

    if (editingBannerId) {
      updateMutation.mutate({ id: editingBannerId, body: payload });
      return;
    }

    createMutation.mutate(payload);
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Layout size={20} className="text-brand-400" /> Content Management
          </h1>
          <p className="text-sm text-text-muted">
            Banners, categories and app content
          </p>
        </div>
        {activeTab === "banners" && (
          <button
            onClick={openCreateForm}
            className="flex items-center gap-2 px-3 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium transition-colors"
          >
            <Plus size={14} /> Add Banner
          </button>
        )}
      </div>

      <div className="flex gap-1 bg-surface-200 rounded-lg p-1 w-fit">
        {(["banners", "categories"] as const).map((t) => (
          <button
            key={t}
            onClick={() => setActiveTab(t)}
            className={`text-xs px-4 py-1.5 rounded-md capitalize transition-colors ${activeTab === t ? "bg-brand-500 text-white" : "text-text-muted hover:text-white"}`}
          >
            {t}
          </button>
        ))}
      </div>

      {activeTab === "banners" &&
        (bannersLoading ? (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4">
            {[...Array(4)].map((_, i) => (
              <div key={i} className="skeleton h-48 rounded-xl" />
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4">
            {banners?.data?.map((b) => (
              <BannerCard
                key={b.$id}
                banner={b}
                onDelete={(id) => deleteMutation.mutate(id)}
                onToggle={(id, active) =>
                  toggleMutation.mutate({ id, is_active: active })
                }
                onEdit={openEditForm}
              />
            ))}
          </div>
        ))}

      {activeTab === "categories" &&
        (catLoading ? (
          <div className="grid grid-cols-3 sm:grid-cols-4 lg:grid-cols-6 gap-3">
            {[...Array(6)].map((_, i) => (
              <div key={i} className="skeleton h-24 rounded-xl" />
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-3 sm:grid-cols-4 lg:grid-cols-6 gap-3">
            {categories?.data?.map((c) => (
              <div key={c.$id} className="card p-3 text-center">
                {c.image_url ? (
                  <img
                    src={c.image_url}
                    alt={c.name}
                    className="w-12 h-12 rounded-full object-cover mx-auto mb-2"
                  />
                ) : (
                  <div className="w-12 h-12 rounded-full bg-brand-500/20 mx-auto mb-2 flex items-center justify-center">
                    <span className="text-brand-400 text-lg font-bold">
                      {c.name.charAt(0)}
                    </span>
                  </div>
                )}
                <p className="text-white text-xs font-medium truncate">
                  {c.name}
                </p>
                <p className="text-text-muted text-xs">#{c.position}</p>
              </div>
            ))}
          </div>
        ))}

      {showForm && (
        <div
          className="fixed inset-0 bg-black/70 flex items-center justify-center z-50"
          onClick={closeForm}
        >
          <div
            className="card w-full max-w-sm p-6 space-y-4"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="text-lg font-bold text-white">
              {editingBannerId ? "Edit Banner" : "New Banner"}
            </h2>
            {bannerFormFields.map(({ label, key, type }) => (
              <div key={key}>
                <label className="text-xs text-text-muted mb-1 block">
                  {label}
                </label>
                <input
                  title={label}
                  placeholder={label}
                  type={type}
                  value={form[key]}
                  onChange={(e) =>
                    setForm((f) => ({
                      ...f,
                      [key]:
                        type === "number"
                          ? parseSafeNumber(e.target.value)
                          : e.target.value,
                    }))
                  }
                  className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
                />
              </div>
            ))}
            <div>
              <label className="text-xs text-text-muted mb-1 block">
                Upload Image
              </label>
              <input
                title="Upload banner image"
                placeholder="Upload banner image"
                type="file"
                accept="image/*"
                onChange={handleBannerImageUpload}
                disabled={isUploadingImage}
                className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white file:mr-3 file:border-0 file:bg-brand-500 file:px-3 file:py-1.5 file:text-white file:rounded-md"
              />
              {isUploadingImage && (
                <p className="text-xs text-text-muted mt-1">
                  Uploading image...
                </p>
              )}
            </div>
            <div>
              <label className="text-xs text-text-muted mb-1 block">
                Target Segment
              </label>
              <select
                title="Target segment"
                value={form.target_segment}
                onChange={(e) =>
                  setForm((f) => ({
                    ...f,
                    target_segment: e.target
                      .value as BannerFormState["target_segment"],
                  }))
                }
                className="w-full bg-surface-200 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-brand-500"
              >
                {["all", "customers", "gold_members", "new_users"].map((t) => (
                  <option key={t} value={t}>
                    {t.replace(/_/g, " ")}
                  </option>
                ))}
              </select>
              <p className="text-[11px] text-text-muted mt-1">
                For the customer home offers banner, keep this as customers.
              </p>
            </div>
            <label className="flex items-center gap-2 text-xs text-text-muted">
              <input
                type="checkbox"
                checked={form.is_active}
                onChange={(e) =>
                  setForm((f) => ({ ...f, is_active: e.target.checked }))
                }
                className="rounded border-white/10 bg-surface-200"
              />
              Active banner
            </label>
            <div className="flex gap-3">
              <button
                onClick={handleBannerSubmit}
                disabled={
                  !form.title ||
                  !form.image_url ||
                  isUploadingImage ||
                  isSavingBanner
                }
                className="flex-1 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium disabled:opacity-50 transition-colors"
              >
                {editingBannerId ? "Save" : "Create"}
              </button>
              <button
                onClick={closeForm}
                className="flex-1 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-text-secondary text-sm transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
