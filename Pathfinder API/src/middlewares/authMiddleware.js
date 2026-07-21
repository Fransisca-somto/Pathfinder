"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.authenticateUser = void 0;
const supabase_1 = require("../config/supabase");
const authenticateUser = async (req, res, next) => {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            res.status(401).json({ error: 'Missing or invalid authorization header' });
            return;
        }
        const token = authHeader.split(' ')[1];
        // Verify token with Supabase
        const { data: { user }, error } = await supabase_1.supabase.auth.getUser(token);
        if (error || !user) {
            res.status(401).json({ error: 'Invalid or expired token' });
            return;
        }
        // Attach user to request
        req.user = user;
        next();
    }
    catch (err) {
        res.status(500).json({ error: 'Internal server error during authentication' });
    }
};
exports.authenticateUser = authenticateUser;
//# sourceMappingURL=authMiddleware.js.map