interface ZoneCacheItem {
    id: string;
    name: string;
    type: string;
    shape_type: string;
    center_latitude: number;
    center_longitude: number;
    radius_meters: number;
    polygon_points: [number, number][];
    owner_id: string;
    assigned_vehicles: Set<string>;
}
export declare const isPointInZone: (lat: number, lng: number, zone: ZoneCacheItem) => boolean;
export declare const refreshZoneCache: () => Promise<void>;
export declare const processVehicleLocation: (vehicleId: string, deviceId: string, lat: number, lng: number, acc: boolean, ownerId: string) => Promise<void>;
export {};
//# sourceMappingURL=zoneService.d.ts.map