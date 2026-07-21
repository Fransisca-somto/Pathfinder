import { Router } from 'express';
import { getZones, createZone, updateZone, deleteZone, getAssignedVehicles, assignVehiclesToZone } from '../controllers/zoneController';
import { authenticateUser } from '../middlewares/authMiddleware';

const router = Router();

// All zone routes require authentication
router.get('/', authenticateUser, getZones);
router.post('/', authenticateUser, createZone);
router.put('/:id', authenticateUser, updateZone);
router.delete('/:id', authenticateUser, deleteZone);

// Vehicle assignment routes
router.get('/:id/vehicles', authenticateUser, getAssignedVehicles);
router.post('/:id/vehicles', authenticateUser, assignVehiclesToZone);

export default router;
