"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.emitNewMedia = exports.emitLiveTelemetry = exports.emitNewAlert = exports.initializeSockets = exports.io = void 0;
const socket_io_1 = require("socket.io");
const initializeSockets = (server) => {
    exports.io = new socket_io_1.Server(server, {
        cors: {
            origin: '*', // Allow connections from anywhere (Flutter, Web)
            methods: ['GET', 'POST']
        }
    });
    exports.io.on('connection', (socket) => {
        console.log(`[WebSocket] Client connected: ${socket.id}`);
        socket.on('disconnect', () => {
            console.log(`[WebSocket] Client disconnected: ${socket.id}`);
        });
        // Flutter App: User authenticates and joins their private room
        // This ensures they only receive telemetry for their own vehicles
        socket.on('authenticate_user', (userId) => {
            const room = `user_${userId}`;
            socket.join(room);
            console.log(`[WebSocket] Client ${socket.id} joined private room: ${room}`);
        });
        // Flutter App: User subscribes to updates for a specific vehicle
        socket.on('subscribe_vehicle', (vehicleId) => {
            const room = `vehicle_${vehicleId}`;
            socket.join(room);
            console.log(`[WebSocket] Client ${socket.id} joined room: ${room}`);
        });
        // Flutter App: User unsubscribes when leaving the screen
        socket.on('unsubscribe_vehicle', (vehicleId) => {
            const room = `vehicle_${vehicleId}`;
            socket.leave(room);
            console.log(`[WebSocket] Client ${socket.id} left room: ${room}`);
        });
    });
    console.log('[WebSocket] Server initialized');
};
exports.initializeSockets = initializeSockets;
// Helper function to emit new alerts to a specific user only
const emitNewAlert = (alertData, ownerId) => {
    if (exports.io) {
        if (ownerId) {
            exports.io.to(`user_${ownerId}`).emit('new_alert', alertData);
        }
        else {
            exports.io.emit('new_alert', alertData);
        }
    }
};
exports.emitNewAlert = emitNewAlert;
// Helper function to emit live telemetry to a specific user only
const emitLiveTelemetry = (telemetryData, ownerId) => {
    if (exports.io) {
        if (ownerId) {
            // Send ONLY to the owner's private room
            exports.io.to(`user_${ownerId}`).emit('live_telemetry', telemetryData);
        }
        // Also send to vehicle-specific room for detailed view
        if (telemetryData.deviceId) {
            exports.io.to(`vehicle_${telemetryData.deviceId}`).emit('live_telemetry', telemetryData);
        }
    }
};
exports.emitLiveTelemetry = emitLiveTelemetry;
// Helper function to emit new media updates
const emitNewMedia = (mediaData) => {
    if (exports.io) {
        exports.io.emit('new_media', mediaData);
    }
};
exports.emitNewMedia = emitNewMedia;
//# sourceMappingURL=socketManager.js.map