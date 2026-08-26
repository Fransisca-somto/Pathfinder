"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const multer_1 = __importDefault(require("multer"));
const supabase_1 = require("../config/supabase");
const mqttService_1 = require("../services/mqttService");
const socketManager_1 = require("../sockets/socketManager");
const router = (0, express_1.Router)();
// Store the uploaded file in memory so we can pipe it to Supabase easily
const storage = multer_1.default.memoryStorage();
const upload = (0, multer_1.default)({ storage });
router.post('/', upload.single('file'), async (req, res) => {
    try {
        const file = req.file;
        const deviceId = req.headers['x-device-id'];
        if (!file) {
            return res.status(400).json({ error: 'No file uploaded' });
        }
        if (!deviceId) {
            return res.status(400).json({ error: 'Missing X-Device-ID header' });
        }
        const fileExt = file.originalname.split('.').pop() || 'jpg';
        const fileName = `${deviceId}/${Date.now()}.${fileExt}`;
        console.log(`[Upload API] Received file from device ${deviceId}. Uploading to Supabase...`);
        // Ensure you have created a public bucket named 'media' in Supabase Storage
        const { createClient } = require('@supabase/supabase-js');
        const adminSupabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
        // Retry up to 3 times to handle intermittent network issues
        let data = null;
        let error = null;
        for (let attempt = 1; attempt <= 3; attempt++) {
            const result = await adminSupabase.storage
                .from('media')
                .upload(fileName, file.buffer, {
                contentType: file.mimetype,
                upsert: false
            });
            data = result.data;
            error = result.error;
            if (!error)
                break;
            console.warn(`[Upload API] Attempt ${attempt}/3 failed:`, error.message || error);
            if (attempt < 3)
                await new Promise(r => setTimeout(r, 2000));
        }
        if (error) {
            console.error('[Upload API] Supabase upload error after 3 attempts:', error);
            return res.status(500).json({ error: 'Failed to upload to storage' });
        }
        // Get the public URL of the uploaded file
        const { data: urlData } = supabase_1.supabase.storage
            .from('media')
            .getPublicUrl(fileName);
        const publicUrl = urlData.publicUrl;
        console.log(`[Upload API] Successfully uploaded. URL: ${publicUrl}`);
        // If you have a 'device_media' table in Supabase, you could insert the record here:
        /*
        await supabase.from('device_media').insert({
          device_id: deviceId,
          media_url: publicUrl,
          media_type: file.mimetype,
          created_at: new Date()
        });
        */
        if (mqttService_1.mqttClient) {
            const payload = JSON.stringify({ url: publicUrl, type: file.mimetype });
            mqttService_1.mqttClient.publish(`pathfinder/devices/${deviceId}/media`, payload);
            console.log(`[Upload API] Published MQTT notification for new media`);
        }
        (0, socketManager_1.emitNewMedia)({ deviceId: deviceId, mediaUrl: publicUrl, type: file.mimetype.includes('image') ? 'IMAGE' : 'AUDIO' });
        console.log(`[Upload API] Emitted WebSocket notification for new media`);
        return res.status(200).json({
            message: 'File uploaded successfully',
            url: publicUrl
        });
    }
    catch (err) {
        console.error('[Upload API] Unexpected error:', err);
        return res.status(500).json({ error: 'Internal server error' });
    }
});
router.get('/:deviceId', async (req, res) => {
    try {
        const deviceId = req.params.deviceId;
        const { data, error } = await supabase_1.supabase.storage
            .from('media')
            .list(deviceId, {
            limit: 100,
            offset: 0,
            sortBy: { column: 'created_at', order: 'desc' }
        });
        if (error) {
            console.error('[Upload API] Supabase list error:', error);
            return res.status(500).json({ error: 'Failed to fetch media' });
        }
        if (!data || data.length === 0) {
            return res.status(200).json([]);
        }
        const filteredData = data.filter(file => file.name !== '.emptyFolderPlaceholder');
        const mediaFiles = filteredData.map((file) => {
            const publicUrl = supabase_1.supabase.storage.from('media').getPublicUrl(`${deviceId}/${file.name}`).data.publicUrl;
            const isImage = file.name.endsWith('.jpg') || file.name.endsWith('.png') || file.name.endsWith('.jpeg');
            return {
                url: publicUrl,
                type: isImage ? 'IMAGE' : 'AUDIO',
                created_at: file.created_at
            };
        });
        return res.status(200).json(mediaFiles);
    }
    catch (err) {
        console.error('[Upload API] Unexpected error in GET:', err);
        return res.status(500).json({ error: 'Internal server error' });
    }
});
exports.default = router;
//# sourceMappingURL=uploadRoutes.js.map