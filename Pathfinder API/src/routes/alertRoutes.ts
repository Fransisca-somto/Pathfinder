import { Router } from 'express';
import { getAlerts, markAlertAsRead, deleteAlert } from '../controllers/alertController';
import { authenticateUser } from '../middlewares/authMiddleware';

const router = Router();

// All alert routes require authentication
router.get('/', authenticateUser, getAlerts);
router.put('/:id/read', authenticateUser, markAlertAsRead);
router.delete('/:id', authenticateUser, deleteAlert);

export default router;
