import { Request, Response } from 'express';
export declare const getFingerprints: (req: Request, res: Response) => Promise<void>;
export declare const addFingerprint: (req: Request, res: Response) => Promise<void>;
export declare const deleteFingerprint: (req: Request, res: Response) => Promise<void>;
export declare const toggleFingerprintStatus: (req: Request, res: Response) => Promise<void>;
export declare const setAuthBypass: (req: Request, res: Response) => Promise<void>;
export declare const registerVehicle: (req: Request, res: Response) => Promise<void>;
export declare const getVehicles: (req: Request, res: Response) => Promise<void>;
export declare const getVehicleById: (req: Request, res: Response) => Promise<void>;
export declare const deleteVehicle: (req: Request, res: Response) => Promise<void>;
export declare const updateVehicle: (req: Request, res: Response) => Promise<void>;
export declare const assignDriver: (req: Request, res: Response) => Promise<void>;
export declare const getTrips: (req: Request, res: Response) => Promise<void>;
//# sourceMappingURL=vehicleController.d.ts.map