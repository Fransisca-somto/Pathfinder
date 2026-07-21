import { Server as SocketIOServer, Socket } from 'socket.io';
import { Server as HttpServer } from 'http';

export let io: SocketIOServer;

export const initializeSockets = (server: HttpServer) => {
  io = new SocketIOServer(server, {
    cors: {
      origin: '*', // Allow connections from anywhere (Flutter, Web)
      methods: ['GET', 'POST']
    }
  });

  io.on('connection', (socket: Socket) => {
    console.log(`[WebSocket] Client connected: ${socket.id}`);

    socket.on('disconnect', () => {
      console.log(`[WebSocket] Client disconnected: ${socket.id}`);
    });

    // Flutter App: User authenticates and joins their private room
    // This ensures they only receive telemetry for their own vehicles
    socket.on('authenticate_user', (userId: string) => {
      const room = `user_${userId}`;
      socket.join(room);
      console.log(`[WebSocket] Client ${socket.id} joined private room: ${room}`);
    });

    // Flutter App: User subscribes to updates for a specific vehicle
    socket.on('subscribe_vehicle', (vehicleId: string) => {
      const room = `vehicle_${vehicleId}`;
      socket.join(room);
      console.log(`[WebSocket] Client ${socket.id} joined room: ${room}`);
    });

    // Flutter App: User unsubscribes when leaving the screen
    socket.on('unsubscribe_vehicle', (vehicleId: string) => {
      const room = `vehicle_${vehicleId}`;
      socket.leave(room);
      console.log(`[WebSocket] Client ${socket.id} left room: ${room}`);
    });
  });

  console.log('[WebSocket] Server initialized');
};

// Helper function to emit new alerts to a specific user only
export const emitNewAlert = (alertData: any, ownerId?: string) => {
  if (io) {
    if (ownerId) {
      io.to(`user_${ownerId}`).emit('new_alert', alertData);
    } else {
      io.emit('new_alert', alertData);
    }
  }
};

// Helper function to emit live telemetry to a specific user only
export const emitLiveTelemetry = (telemetryData: any, ownerId?: string) => {
  if (io) {
    if (ownerId) {
      // Send ONLY to the owner's private room
      io.to(`user_${ownerId}`).emit('live_telemetry', telemetryData);
    }
    // Also send to vehicle-specific room for detailed view
    if (telemetryData.deviceId) {
      io.to(`vehicle_${telemetryData.deviceId}`).emit('live_telemetry', telemetryData);
    }
  }
};

// Helper function to emit new media updates
export const emitNewMedia = (mediaData: any) => {
  if (io) {
    io.emit('new_media', mediaData);
  }
};
