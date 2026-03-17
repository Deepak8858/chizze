"use client";
import { useState, useRef, useCallback } from "react";
import Map, { Marker, Source, Layer, type MapRef } from "react-map-gl";
import type { LayerProps } from "react-map-gl";
import "mapbox-gl/dist/mapbox-gl.css";
import { useRiderLocations, useLiveOrders } from "@/lib/sse";
import { liveApi } from "@/lib/api";
import { useQuery } from "@tanstack/react-query";
import { Bike, MapPin, UtensilsCrossed, Layers, Zap, Thermometer, Search } from "lucide-react";
import { cn, formatCurrency, timeAgo } from "@/lib/utils";
import type { Restaurant } from "@/types";

const MAPBOX_TOKEN = process.env.NEXT_PUBLIC_MAPBOX_TOKEN ?? "";

// Map layer specs
const orderLineLayer: LayerProps = {
  id: "order-routes",
  type: "line",
  paint: {
    "line-color": ["get", "color"],
    "line-width": 2,
    "line-opacity": 0.8,
  },
};

const heatmapLayer: LayerProps = {
  id: "orders-heatmap",
  type: "heatmap",
  paint: {
    "heatmap-weight": 1,
    "heatmap-intensity": 1,
    "heatmap-color": [
      "interpolate", ["linear"], ["heatmap-density"],
      0, "rgba(0,0,0,0)",
      0.2, "rgba(244,157,37,0.3)",
      1, "rgba(244,157,37,0.9)",
    ],
    "heatmap-radius": 30,
    "heatmap-opacity": 0.6,
  },
};

export default function LiveMapPage() {
  const mapRef = useRef<MapRef>(null);
  const [showHeatmap, setShowHeatmap] = useState(false);
  const [showZones, setShowZones] = useState(true);
  const [showSurge, setShowSurge] = useState(true);
  const [selectedRider, setSelectedRider] = useState<string | null>(null);
  const [search, setSearch] = useState("");

  const { riders } = useRiderLocations();
  const { orders } = useLiveOrders();

  const { data: restaurants } = useQuery<Restaurant[]>({
    queryKey: ["admin-restaurants-map"],
    queryFn: () => liveApi.ridersSnapshot() as Promise<Restaurant[]>,
    staleTime: 5 * 60_000,
  });

  // Filter riders by search
  const filteredRiders = riders.filter((r) =>
    !search || r.name.toLowerCase().includes(search.toLowerCase()) || r.phone.includes(search)
  );

  const panToRider = useCallback((lat: number, lng: number) => {
    mapRef.current?.flyTo({ center: [lng, lat], zoom: 14, duration: 1000 });
  }, []);

  // Build order routes GeoJSON
  const routesGeoJSON = {
    type: "FeatureCollection" as const,
    features: orders
      .filter((o) => o.restaurant_lat && o.customer_lat)
      .map((o) => ({
        type: "Feature" as const,
        properties: {
          color:
            o.status === "outForDelivery" ? "#22C55E"
            : o.status === "ready" ? "#FACC15"
            : "#3B82F6",
        },
        geometry: {
          type: "LineString" as const,
          coordinates: [
            [o.restaurant_lng, o.restaurant_lat],
            ...(o.rider_lng ? [[o.rider_lng, o.rider_lat!]] : []),
            [o.customer_lng, o.customer_lat],
          ],
        },
      })),
  };

  // Heatmap GeoJSON from customer locations
  const heatGeoJSON = {
    type: "FeatureCollection" as const,
    features: orders.map((o) => ({
      type: "Feature" as const,
      properties: {},
      geometry: { type: "Point" as const, coordinates: [o.customer_lng, o.customer_lat] },
    })),
  };

  return (
    <div className="relative h-[calc(100vh-60px-48px-48px)] rounded-xl overflow-hidden">
      {/* Map */}
      <Map
        ref={mapRef}
        mapboxAccessToken={MAPBOX_TOKEN}
        initialViewState={{ longitude: 77.59, latitude: 12.97, zoom: 11 }}
        style={{ width: "100%", height: "100%" }}
        mapStyle="mapbox://styles/mapbox/dark-v11"
      >
        {/* Order routes layer */}
        <Source id="routes" type="geojson" data={routesGeoJSON}>
          <Layer {...orderLineLayer} />
        </Source>

        {/* Heatmap */}
        {showHeatmap && (
          <Source id="heatmap" type="geojson" data={heatGeoJSON}>
            <Layer {...heatmapLayer} />
          </Source>
        )}

        {/* Rider pins */}
        {filteredRiders.map((rider) => (
          <Marker
            key={rider.rider_id}
            longitude={rider.longitude}
            latitude={rider.latitude}
            onClick={() => {
              setSelectedRider(rider.rider_id === selectedRider ? null : rider.rider_id);
              panToRider(rider.latitude, rider.longitude);
            }}
          >
            <div
              className={cn(
                "w-8 h-8 rounded-full flex items-center justify-center border-2 cursor-pointer transition-transform hover:scale-110",
                rider.is_on_delivery
                  ? "bg-brand-500 border-brand-600"
                  : "bg-success/80 border-success"
              )}
              title={rider.name}
            >
              <Bike size={14} className="text-white" />
            </div>
            {/* Popup */}
            {selectedRider === rider.rider_id && (
              <div className="absolute bottom-10 left-1/2 -translate-x-1/2 bg-bg-elevated border border-white/10 rounded-lg p-3 text-xs whitespace-nowrap z-10 shadow-xl">
                <p className="font-semibold text-white">{rider.name}</p>
                <p className="text-text-muted">{rider.phone}</p>
                <p className={cn("mt-1 font-medium", rider.is_on_delivery ? "text-brand-400" : "text-success")}>
                  {rider.is_on_delivery ? "On Delivery" : "Idle"}
                </p>
                {rider.current_order_id && (
                  <p className="text-text-muted">Order: {rider.current_order_id.slice(0, 8)}</p>
                )}
                <p className="text-text-muted">{timeAgo(rider.last_update)}</p>
              </div>
            )}
          </Marker>
        ))}

        {/* Restaurant pins */}
        {(restaurants ?? []).map((r) => (
          <Marker key={r.$id} longitude={r.longitude} latitude={r.latitude}>
            <div
              className={cn(
                "w-6 h-6 rounded-full flex items-center justify-center border cursor-pointer",
                r.is_online
                  ? "bg-brand-500/80 border-brand-500"
                  : "bg-text-muted/30 border-text-muted"
              )}
              title={r.name}
            >
              <UtensilsCrossed size={10} className="text-white" />
            </div>
          </Marker>
        ))}
      </Map>

      {/* Sidebar panel */}
      <div className="absolute top-3 right-3 w-72 bg-bg-elevated/95 border border-white/10 rounded-xl overflow-hidden backdrop-blur-sm">
        {/* Stats */}
        <div className="px-4 py-3 border-b border-white/[0.06] grid grid-cols-3 gap-2 text-center">
          <div>
            <p className="text-lg font-bold text-success">{riders.filter(r => r.is_on_delivery).length}</p>
            <p className="text-[10px] text-text-muted">On Delivery</p>
          </div>
          <div>
            <p className="text-lg font-bold text-brand-400">{orders.length}</p>
            <p className="text-[10px] text-text-muted">Active Orders</p>
          </div>
          <div>
            <p className="text-lg font-bold text-info">{riders.length}</p>
            <p className="text-[10px] text-text-muted">Online Riders</p>
          </div>
        </div>

        {/* Search riders */}
        <div className="px-3 py-2 border-b border-white/[0.06]">
          <div className="flex items-center gap-2 bg-bg-card border border-white/10 rounded-lg px-2 h-8">
            <Search size={12} className="text-text-muted" />
            <input
              type="text"
              placeholder="Search rider…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="flex-1 bg-transparent text-xs text-white placeholder-text-muted outline-none"
            />
          </div>
        </div>

        {/* Rider list */}
        <div className="max-h-48 overflow-y-auto">
          {filteredRiders.map((rider) => (
            <button
              key={rider.rider_id}
              onClick={() => panToRider(rider.latitude, rider.longitude)}
              className="w-full flex items-center gap-2 px-3 py-2 hover:bg-bg-hover text-left transition-colors"
            >
              <div className={cn(
                "w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0",
                rider.is_on_delivery ? "bg-brand-500/20" : "bg-success/20"
              )}>
                <Bike size={10} className={rider.is_on_delivery ? "text-brand-400" : "text-success"} />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-xs text-white truncate">{rider.name}</p>
                <p className="text-[10px] text-text-muted">{rider.vehicle_type}</p>
              </div>
              <span className={cn(
                "text-[10px] font-medium",
                rider.is_on_delivery ? "text-brand-400" : "text-success"
              )}>
                {rider.is_on_delivery ? "Active" : "Idle"}
              </span>
            </button>
          ))}
        </div>

        {/* Overlay toggles */}
        <div className="px-3 py-3 border-t border-white/[0.06] flex gap-2 flex-wrap">
          {[
            { label: "Heatmap", state: showHeatmap, toggle: setShowHeatmap, icon: <Thermometer size={10} /> },
            { label: "Zones", state: showZones, toggle: setShowZones, icon: <Layers size={10} /> },
            { label: "Surge", state: showSurge, toggle: setShowSurge, icon: <Zap size={10} /> },
          ].map((item) => (
            <button
              key={item.label}
              onClick={() => item.toggle(!item.state)}
              className={cn(
                "flex items-center gap-1 text-[10px] font-medium px-2 py-1 rounded transition-colors",
                item.state
                  ? "bg-brand-500/20 text-brand-400 border border-brand-500/30"
                  : "bg-bg-card text-text-muted border border-white/10"
              )}
            >
              {item.icon}{item.label}
            </button>
          ))}
        </div>
      </div>

      {/* Legend */}
      <div className="absolute bottom-3 left-3 bg-bg-elevated/90 border border-white/10 rounded-lg px-3 py-2 text-[10px] space-y-1 backdrop-blur-sm">
        <div className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-success" /> Idle Rider</div>
        <div className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-brand-500" /> On Delivery</div>
        <div className="flex items-center gap-1.5"><span className="w-4 h-0.5 bg-success" /> Out for Delivery</div>
        <div className="flex items-center gap-1.5"><span className="w-4 h-0.5 bg-warning" style={{ borderTop: "1px dashed #FACC15" }} /> Ready to pickup</div>
      </div>
    </div>
  );
}
