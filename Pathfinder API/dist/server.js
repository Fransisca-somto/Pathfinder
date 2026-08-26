"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const http_1 = require("http");
const cors_1 = __importDefault(require("cors"));
const dotenv_1 = __importDefault(require("dotenv"));
const morgan_1 = __importDefault(require("morgan"));
const authRoutes_1 = __importDefault(require("./routes/authRoutes"));
const vehicleRoutes_1 = __importDefault(require("./routes/vehicleRoutes"));
const alertRoutes_1 = __importDefault(require("./routes/alertRoutes"));
const zoneRoutes_1 = __importDefault(require("./routes/zoneRoutes"));
const uploadRoutes_1 = __importDefault(require("./routes/uploadRoutes"));
const socketManager_1 = require("./sockets/socketManager");
const mqttService_1 = require("./services/mqttService");
dotenv_1.default.config();
const app = (0, express_1.default)();
app.set('etag', false);
const PORT = process.env.PORT || 3000;
// Middleware
app.use((0, cors_1.default)());
app.use(express_1.default.json());
app.use((0, morgan_1.default)('dev'));
// Routes
app.use('/auth', authRoutes_1.default);
app.use('/vehicles', vehicleRoutes_1.default);
app.use('/alerts', alertRoutes_1.default);
app.use('/zones', zoneRoutes_1.default);
app.use('/api/upload', uploadRoutes_1.default);
// Basic health check
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok', message: 'PathFinder API is running' });
});
const httpServer = (0, http_1.createServer)(app);
(0, socketManager_1.initializeSockets)(httpServer);
(0, mqttService_1.initializeMqtt)();
httpServer.listen(PORT, () => {
    console.log(`Server is running on http://localhost:${PORT}`);
});
//# sourceMappingURL=server.js.map