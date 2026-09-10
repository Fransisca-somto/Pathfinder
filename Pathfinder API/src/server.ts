import express from 'express';
import { createServer } from 'http';
import cors from 'cors';
import dotenv from 'dotenv';
import morgan from 'morgan';

import authRoutes from './routes/authRoutes';
import vehicleRoutes from './routes/vehicleRoutes';
import alertRoutes from './routes/alertRoutes';
import zoneRoutes from './routes/zoneRoutes';

import { initializeSockets } from './sockets/socketManager';
import { initializeMqtt } from './services/mqttService';

dotenv.config();

const app = express();
app.set('etag', false);

const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// Routes
app.use('/auth', authRoutes);
app.use('/vehicles', vehicleRoutes);
app.use('/alerts', alertRoutes);
app.use('/zones', zoneRoutes);


// Basic health check
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', message: 'PathFinder API is running' });
});

const httpServer = createServer(app);
initializeSockets(httpServer);
initializeMqtt();

httpServer.listen(PORT, () => {
  console.log(`Server is running on http://localhost:${PORT}`);
});
