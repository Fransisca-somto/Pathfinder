"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const alertController_1 = require("../controllers/alertController");
const authMiddleware_1 = require("../middlewares/authMiddleware");
const router = (0, express_1.Router)();
// All alert routes require authentication
router.get('/', authMiddleware_1.authenticateUser, alertController_1.getAlerts);
router.put('/:id/read', authMiddleware_1.authenticateUser, alertController_1.markAlertAsRead);
router.delete('/:id', authMiddleware_1.authenticateUser, alertController_1.deleteAlert);
exports.default = router;
//# sourceMappingURL=alertRoutes.js.map