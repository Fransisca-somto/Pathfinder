import { Router } from 'express';
import { registerVehicle, getVehicles, getVehicleById, deleteVehicle, updateVehicle, assignDriver, getFingerprints, addFingerprint, deleteFingerprint, setAuthBypass, toggleFingerprintStatus, getTrips, soundAlarm, setEmergencyContact } from '../controllers/vehicleController';
import { authenticateUser } from '../middlewares/authMiddleware';

const router = Router();

// All vehicle routes require authentication
router.post('/register', authenticateUser, registerVehicle);
router.get('/', authenticateUser, getVehicles);
router.get('/:id', authenticateUser, getVehicleById);
router.get('/:id/trips', authenticateUser, getTrips);
router.put('/:id', authenticateUser, updateVehicle);
router.post('/:id/drivers', authenticateUser, assignDriver);

// Fingerprint specific routes
router.get('/:id/fingerprints', authenticateUser, getFingerprints);
router.post('/:id/fingerprints', authenticateUser, addFingerprint);
router.delete('/:id/fingerprints/:slotId', authenticateUser, deleteFingerprint);
router.post('/:id/fingerprints/:slotId/toggle', authenticateUser, toggleFingerprintStatus);
router.post('/:id/auth-bypass', authenticateUser, setAuthBypass);
router.post('/:id/alarm', authenticateUser, soundAlarm);
router.post('/:id/emergency-contact', authenticateUser, setEmergencyContact);

router.delete('/:id', authenticateUser, deleteVehicle);

export default router;
