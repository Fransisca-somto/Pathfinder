"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const vehicleController_1 = require("../controllers/vehicleController");
const authMiddleware_1 = require("../middlewares/authMiddleware");
const router = (0, express_1.Router)();
// All vehicle routes require authentication
router.post('/register', authMiddleware_1.authenticateUser, vehicleController_1.registerVehicle);
router.get('/', authMiddleware_1.authenticateUser, vehicleController_1.getVehicles);
router.get('/:id', authMiddleware_1.authenticateUser, vehicleController_1.getVehicleById);
router.get('/:id/trips', authMiddleware_1.authenticateUser, vehicleController_1.getTrips);
router.put('/:id', authMiddleware_1.authenticateUser, vehicleController_1.updateVehicle);
router.post('/:id/drivers', authMiddleware_1.authenticateUser, vehicleController_1.assignDriver);
// Fingerprint specific routes
router.get('/:id/fingerprints', authMiddleware_1.authenticateUser, vehicleController_1.getFingerprints);
router.post('/:id/fingerprints', authMiddleware_1.authenticateUser, vehicleController_1.addFingerprint);
router.delete('/:id/fingerprints/:slotId', authMiddleware_1.authenticateUser, vehicleController_1.deleteFingerprint);
router.post('/:id/fingerprints/:slotId/toggle', authMiddleware_1.authenticateUser, vehicleController_1.toggleFingerprintStatus);
router.post('/:id/auth-bypass', authMiddleware_1.authenticateUser, vehicleController_1.setAuthBypass);
router.post('/:id/alarm', authMiddleware_1.authenticateUser, vehicleController_1.soundAlarm);
router.post('/:id/emergency-contact', authMiddleware_1.authenticateUser, vehicleController_1.setEmergencyContact);
router.delete('/:id', authMiddleware_1.authenticateUser, vehicleController_1.deleteVehicle);
exports.default = router;
//# sourceMappingURL=vehicleRoutes.js.map