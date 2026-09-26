import { Router } from 'express';
import { login, register, getCurrentUser, refreshToken, logout } from '../controllers/authController';
import { authenticateUser } from '../middlewares/authMiddleware';

const router = Router();

router.post('/login',    login);
router.post('/register', register);
router.post('/refresh',  refreshToken);
router.post('/logout',   authenticateUser, logout);
router.get('/me',        authenticateUser, getCurrentUser);

export default router;
