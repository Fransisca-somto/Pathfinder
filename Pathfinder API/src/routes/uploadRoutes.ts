import { Router, Request, Response } from 'express';
import multer from 'multer';
import { supabase } from '../config/supabase';
import { mqttClient } from '../services/mqttService';
import { emitNewMedia } from '../sockets/socketManager';

const router = Router();

// Store the uploaded file in memory so we can pipe it to Supabase easily
const storage = multer.memoryStorage();
const upload = multer({ storage });

router.post('/', upload.single('file'), async (req: Request, res: Response): Promise<any> => {
  try {
    const file = req.file;
    const deviceId = req.headers['x-device-id'] as string;

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
    const adminSupabase = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } }
    );

    // Retry up to 3 times to handle intermittent network issues
    let data: any = null;
    let error: any = null;
    for (let attempt = 1; attempt <= 3; attempt++) {
      const result = await adminSupabase.storage
        .from('media')
        .upload(fileName, file.buffer, {
          contentType: file.mimetype,
          upsert: false
        });
      data = result.data;
      error = result.error;
      if (!error) break;
      console.warn(`[Upload API] Attempt ${attempt}/3 failed:`, error.message || error);
      if (attempt < 3) await new Promise(r => setTimeout(r, 2000));
    }

    if (error) {
      console.error('[Upload API] Supabase upload error after 3 attempts:', error);
      return res.status(500).json({ error: 'Failed to upload to storage' });
    }

    // Get the public URL of the uploaded file
    const { data: urlData } = supabase.storage
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

    if (mqttClient) {
      const payload = JSON.stringify({ url: publicUrl, type: file.mimetype });
      mqttClient.publish(`pathfinder/devices/${deviceId}/media`, payload);
      console.log(`[Upload API] Published MQTT notification for new media`);
    }

    emitNewMedia({ deviceId: deviceId, mediaUrl: publicUrl, type: file.mimetype.includes('image') ? 'IMAGE' : 'AUDIO' });
    console.log(`[Upload API] Emitted WebSocket notification for new media`);

    return res.status(200).json({
      message: 'File uploaded successfully',
      url: publicUrl
    });

  } catch (err) {
    console.error('[Upload API] Unexpected error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:deviceId', async (req: Request, res: Response): Promise<any> => {
  try {
    const deviceId = req.params.deviceId as string;
    
    const { createClient } = require('@supabase/supabase-js');
    const adminSupabase = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } }
    );

    console.log(`[Upload API] Listing files for device: ${deviceId}`);

    const { data, error } = await adminSupabase.storage
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

    console.log(`[Upload API] Raw files found: ${data?.length || 0}`);

    if (!data || data.length === 0) {
      return res.status(200).json([]);
    }

    const filteredData = data.filter((file: any) => file.name !== '.emptyFolderPlaceholder');

    const mediaFiles = filteredData.map((file: any) => {
      const publicUrl = adminSupabase.storage.from('media').getPublicUrl(`${deviceId}/${file.name}`).data.publicUrl;
      const isImage = file.name.endsWith('.jpg') || file.name.endsWith('.png') || file.name.endsWith('.jpeg');
      return {
        url: publicUrl,
        type: isImage ? 'IMAGE' : 'AUDIO',
        created_at: file.created_at
      };
    });

    console.log(`[Upload API] Returning ${mediaFiles.length} media files`);
    return res.status(200).json(mediaFiles);
  } catch (err) {
    console.error('[Upload API] Unexpected error in GET:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
