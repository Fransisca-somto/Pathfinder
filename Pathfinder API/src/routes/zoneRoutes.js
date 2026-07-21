"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zoneController_1 = require("../controllers/zoneController");
const authMiddleware_1 = require("../middlewares/authMiddleware");
const router = (0, express_1.Router)();
// All zone routes require authentication
router.get('/', authMiddleware_1.authenticateUser, zoneController_1.getZones);
router.post('/', authMiddleware_1.authenticateUser, zoneController_1.createZone);
router.put('/:id', authMiddleware_1.authenticateUser, zoneController_1.updateZone);
router.delete('/:id', authMiddleware_1.authenticateUser, zoneController_1.deleteZone);
// Vehicle assignment routes
router.get('/:id/vehicles', authMiddleware_1.authenticateUser, zoneController_1.getAssignedVehicles);
router.post('/:id/vehicles', authMiddleware_1.authenticateUser, zoneController_1.assignVehiclesToZone);
exports.default = router;
//# sourceMappingURL=zoneRoutes.js.map