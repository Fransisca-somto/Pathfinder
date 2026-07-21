import { Router } from 'express';
import { login, register, getCurrentUser } from '../controllers/authController';
import { authenticateUser } from '../middlewares/authMiddleware';

const router = Router();

router.post('/login', login);
router.post('/register', register);
router.get('/me', authenticateUser, getCurrentUser);

export default router;
