import { Server as SocketIOServer } from 'socket.io';
import { Server as HttpServer } from 'http';
export declare let io: SocketIOServer;
export declare const initializeSockets: (server: HttpServer) => void;
export declare const emitNewAlert: (alertData: any, ownerId?: string) => void;
export declare const emitLiveTelemetry: (telemetryData: any, ownerId?: string) => void;
export declare const emitNewMedia: (mediaData: any) => void;
//# sourceMappingURL=socketManager.d.ts.map