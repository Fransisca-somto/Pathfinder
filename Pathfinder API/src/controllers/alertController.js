"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteAlert = exports.markAlertAsRead = exports.getAlerts = void 0;
const supabase_1 = require("../config/supabase");
// GET /alerts — List all alerts for the authenticated user
const getAlerts = async (req, res) => {
    try {
        const ownerId = req.user.id;
        const { data, error } = await supabase_1.supabase
            .from('alerts')
            .select('*, vehicle:vehicles(name, plate_number)')
            .eq('owner_id', ownerId)
            .order('created_at', { ascending: false });
        if (error) {
            console.error('[Alert] Fetch error:', error);
            res.status(500).json({ error: 'Failed to fetch alerts' });
            return;
        }
        res.status(200).json(data || []);
    }
    catch (err) {
        console.error('[Alert] Fetch error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.getAlerts = getAlerts;
// PUT /alerts/:id/read — Mark an alert as read
const markAlertAsRead = async (req, res) => {
    try {
        const ownerId = req.user.id;
        const alertId = req.params.id;
        // Verify ownership before updating
        const { data: alert } = await supabase_1.supabase
            .from('alerts')
            .select('id')
            .eq('id', alertId)
            .eq('owner_id', ownerId)
            .single();
        if (!alert) {
            res.status(404).json({ error: 'Alert not found or you do not have permission' });
            return;
        }
        const { error } = await supabase_1.supabase
            .from('alerts')
            .update({ is_read: true })
            .eq('id', alertId);
        if (error) {
            console.error('[Alert] Update error:', error);
            res.status(500).json({ error: 'Failed to update alert' });
            return;
        }
        res.status(200).json({ message: 'Alert marked as read' });
    }
    catch (err) {
        console.error('[Alert] Update error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.markAlertAsRead = markAlertAsRead;
// DELETE /alerts/:id — Hard delete an alert
const deleteAlert = async (req, res) => {
    try {
        const ownerId = req.user.id;
        const alertId = req.params.id;
        // Verify ownership before deleting
        const { data: alert } = await supabase_1.supabase
            .from('alerts')
            .select('id')
            .eq('id', alertId)
            .eq('owner_id', ownerId)
            .single();
        if (!alert) {
            res.status(404).json({ error: 'Alert not found or you do not have permission' });
            return;
        }
        const { error } = await supabase_1.supabase
            .from('alerts')
            .delete()
            .eq('id', alertId);
        if (error) {
            console.error('[Alert] Delete error:', error);
            res.status(500).json({ error: 'Failed to delete alert' });
            return;
        }
        res.status(200).json({ message: 'Alert deleted successfully' });
    }
    catch (err) {
        console.error('[Alert] Delete error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.deleteAlert = deleteAlert;
//# sourceMappingURL=alertController.js.map